from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from .dataset import compile_ledger


def default_ledger() -> Path:
    return (
        Path.home()
        / "Library/Application Support/Shakespeare/personalization/training_events.jsonl"
    )


def default_registry() -> Path:
    return (
        Path.home()
        / "Library/Application Support/Shakespeare/personalization/model_registry.json"
    )


def compile_command(args: argparse.Namespace) -> int:
    result = compile_ledger(args.input, args.output, args.eval_fraction)
    print(json.dumps(asdict(result), indent=2, sort_keys=True))
    if result.sft_train_examples == 0:
        print(
            "No SFT training examples were produced; collect more accepted edits or longer document snapshots."
        )
    return 0


def _final_checkpoint(log_path: Path) -> dict[str, object]:
    checkpoint_file = log_path / "checkpoints.jsonl"
    if not checkpoint_file.exists():
        raise RuntimeError(f"Training completed without {checkpoint_file}")
    records = [
        json.loads(line)
        for line in checkpoint_file.read_text(encoding="utf-8").splitlines()
        if line
    ]
    finals = [
        record
        for record in records
        if record.get("final") is True and record.get("sampler_path")
    ]
    if not finals:
        raise RuntimeError("Training completed without a final sampler checkpoint")
    return finals[-1]


def _promote_checkpoint(
    registry_path: Path,
    checkpoint: dict[str, object],
    base_model: str,
    manifest_path: Path,
    evaluation_report: dict[str, object],
) -> None:
    record = {
        "schemaVersion": 2,
        "baseModel": base_model,
        "samplerPath": checkpoint["sampler_path"],
        "statePath": checkpoint.get("state_path"),
        "trainedAt": datetime.now(timezone.utc).isoformat(),
        "datasetManifest": str(manifest_path.resolve()),
        "evaluation": evaluation_report,
    }
    registry_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = registry_path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.chmod(temporary, 0o600)
    temporary.replace(registry_path)


def _load_evaluation_gate(
    report_path: Path, manifest_path: Path, sampler_path: str
) -> dict[str, object]:
    if not report_path.exists():
        raise RuntimeError(f"Evaluation report does not exist: {report_path}")
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Invalid evaluation report JSON: {error}") from error
    if not isinstance(report, dict) or report.get("schema_version") != 1:
        raise RuntimeError("Evaluation report must be a schema_version 1 object")
    if report.get("status") != "passed":
        raise RuntimeError("Checkpoint promotion requires a passing evaluation report")
    manifest_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    if report.get("dataset_manifest_sha256") != manifest_hash:
        raise RuntimeError("Evaluation report does not match this dataset manifest")
    if report.get("sampler_path") != sampler_path:
        raise RuntimeError("Evaluation report does not match this sampler checkpoint")
    if not isinstance(report.get("metrics"), dict):
        raise RuntimeError("Evaluation report metrics must be an object")
    return report


async def _train(args: argparse.Namespace) -> None:
    if not os.environ.get("TINKER_API_KEY"):
        raise RuntimeError("TINKER_API_KEY is required for training")
    train_file = args.dataset_dir / "sft_train.jsonl"
    manifest = args.dataset_dir / "manifest.json"
    if not train_file.exists() or not manifest.exists():
        raise RuntimeError(
            "Compile the ledger before training; sft_train.jsonl and manifest.json are required"
        )
    if train_file.stat().st_size == 0:
        raise RuntimeError("sft_train.jsonl is empty")

    try:
        from tinker_cookbook import model_info
        from tinker_cookbook.supervised import (
            FromConversationFileBuilder,
            ChatDatasetBuilderCommonConfig,
        )
        from tinker_cookbook.supervised import train
    except ImportError as error:
        raise RuntimeError(
            "Install Trainer dependencies with: python -m pip install -e Trainer"
        ) from error

    renderer = model_info.get_recommended_renderer_name(args.base_model)
    builder = FromConversationFileBuilder(
        file_path=str(train_file),
        common_config=ChatDatasetBuilderCommonConfig(
            model_name_for_tokenizer=args.base_model,
            renderer_name=renderer,
            max_length=args.max_length,
            batch_size=args.batch_size,
        ),
    )
    config = train.Config(
        log_path=str(args.log_path),
        model_name=args.base_model,
        recipe_name="shakespeare_personal_sft",
        renderer_name=renderer,
        dataset_builder=builder,
        learning_rate=args.learning_rate,
        num_epochs=args.epochs,
        lora_rank=args.lora_rank,
        save_every=0,
        eval_every=0,
        infrequent_eval_every=0,
    )
    await train.main(config)
    checkpoint = _final_checkpoint(args.log_path)
    print(json.dumps(checkpoint, indent=2, sort_keys=True))


def train_command(args: argparse.Namespace) -> int:
    asyncio.run(_train(args))
    return 0


def dpo_command(args: argparse.Namespace) -> int:
    if not os.environ.get("TINKER_API_KEY"):
        raise RuntimeError("TINKER_API_KEY is required for training")
    train_file = args.dataset_dir / "dpo_train.jsonl"
    eval_file = args.dataset_dir / "dpo_eval.jsonl"
    if not train_file.exists() or train_file.stat().st_size == 0:
        raise RuntimeError(
            "dpo_train.jsonl is missing or empty; collect rejected edit decisions first"
        )

    try:
        from tinker_cookbook import model_info
        from tinker_cookbook.preference import train_dpo
        from tinker_cookbook.preference.dpo_datasets import (
            DPODatasetBuilderFromComparisons,
        )
        from tinker_cookbook.preference.preference_datasets import (
            ComparisonBuilderFromJsonl,
        )
        from tinker_cookbook.supervised import ChatDatasetBuilderCommonConfig
    except ImportError as error:
        raise RuntimeError(
            "Install Trainer dependencies with: python -m pip install -e Trainer"
        ) from error

    renderer = model_info.get_recommended_renderer_name(args.base_model)
    comparisons = ComparisonBuilderFromJsonl(
        train_path=str(train_file),
        test_path=str(eval_file)
        if eval_file.exists() and eval_file.stat().st_size
        else None,
    )
    builder = DPODatasetBuilderFromComparisons(
        comparison_builder=comparisons,
        common_config=ChatDatasetBuilderCommonConfig(
            model_name_for_tokenizer=args.base_model,
            renderer_name=renderer,
            max_length=args.max_length,
            batch_size=args.batch_size,
        ),
    )
    config = train_dpo.Config(
        log_path=str(args.log_path),
        model_name=args.base_model,
        recipe_name="shakespeare_personal_dpo",
        renderer_name=renderer,
        dataset_builder=builder,
        load_checkpoint_path=args.load_checkpoint,
        learning_rate=args.learning_rate,
        num_epochs=args.epochs,
        dpo_beta=args.beta,
        lora_rank=args.lora_rank,
        num_replicas=1,
        save_every=0,
        eval_every=0,
        infrequent_eval_every=0,
    )
    train_dpo.main(config)
    checkpoint = _final_checkpoint(args.log_path)
    print(json.dumps(checkpoint, indent=2, sort_keys=True))
    return 0


def promote_command(args: argparse.Namespace) -> int:
    manifest = args.dataset_dir / "manifest.json"
    if not manifest.exists():
        raise RuntimeError("Compiled dataset manifest.json is required for promotion")
    checkpoint = _final_checkpoint(args.log_path)
    sampler_path = checkpoint.get("sampler_path")
    if not isinstance(sampler_path, str) or not sampler_path:
        raise RuntimeError("Final checkpoint is missing sampler_path")
    evaluation = _load_evaluation_gate(args.evaluation_report, manifest, sampler_path)
    _promote_checkpoint(
        args.registry, checkpoint, args.base_model, manifest, evaluation
    )
    print(f"Promoted checkpoint to {args.registry}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compile and train Shakespeare personal style models"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    compile_parser = subparsers.add_parser(
        "compile", help="Compile the local event ledger"
    )
    compile_parser.add_argument("--input", type=Path, default=default_ledger())
    compile_parser.add_argument(
        "--output", type=Path, default=Path("Trainer/data/compiled")
    )
    compile_parser.add_argument("--eval-fraction", type=float, default=0.15)
    compile_parser.set_defaults(handler=compile_command)

    train_parser = subparsers.add_parser("train", help="Run Inkling SFT through Tinker")
    train_parser.add_argument(
        "--dataset-dir", type=Path, default=Path("Trainer/data/compiled")
    )
    train_parser.add_argument("--log-path", type=Path, required=True)
    train_parser.add_argument("--learning-rate", type=float, required=True)
    train_parser.add_argument("--base-model", default="thinkingmachines/Inkling")
    train_parser.add_argument("--batch-size", type=int, default=4)
    train_parser.add_argument("--max-length", type=int, default=4096)
    train_parser.add_argument("--epochs", type=int, default=1)
    train_parser.add_argument("--lora-rank", type=int, default=32)
    train_parser.set_defaults(handler=train_command)

    dpo_parser = subparsers.add_parser(
        "train-dpo", help="Run preference training from rejected edits"
    )
    dpo_parser.add_argument(
        "--dataset-dir", type=Path, default=Path("Trainer/data/compiled")
    )
    dpo_parser.add_argument("--log-path", type=Path, required=True)
    dpo_parser.add_argument("--learning-rate", type=float, required=True)
    dpo_parser.add_argument("--base-model", default="thinkingmachines/Inkling")
    dpo_parser.add_argument(
        "--load-checkpoint", help="Optional SFT state_path to continue from"
    )
    dpo_parser.add_argument("--batch-size", type=int, default=2)
    dpo_parser.add_argument("--max-length", type=int, default=4096)
    dpo_parser.add_argument("--epochs", type=int, default=1)
    dpo_parser.add_argument("--lora-rank", type=int, default=32)
    dpo_parser.add_argument("--beta", type=float, default=0.1)
    dpo_parser.set_defaults(handler=dpo_command)

    promote_parser = subparsers.add_parser(
        "promote", help="Promote an evaluated final checkpoint"
    )
    promote_parser.add_argument(
        "--dataset-dir", type=Path, default=Path("Trainer/data/compiled")
    )
    promote_parser.add_argument("--log-path", type=Path, required=True)
    promote_parser.add_argument("--evaluation-report", type=Path, required=True)
    promote_parser.add_argument("--base-model", default="thinkingmachines/Inkling")
    promote_parser.add_argument("--registry", type=Path, default=default_registry())
    promote_parser.set_defaults(handler=promote_command)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return args.handler(args)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
