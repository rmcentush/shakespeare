# Personal style training

Shakespeare has a local-first personalization pipeline for adapting Inkling to one writer. Collection is disabled by default and the app never starts a training run automatically.

## Data flow

1. The writer enables **Settings → Personalization → Collect local training events**.
2. The editor records accepted and rejected assistant edits, including the original instruction, editorial category, rationale, surrounding text, provider, and exact model/checkpoint.
3. A deduplicated final-text snapshot is recorded after a successful document save.
4. The local compiler creates document-separated SFT and DPO train/evaluation files.
5. An explicit CLI command submits a LoRA training run to Tinker.
6. A held-out evaluation produces a report tied to the exact dataset manifest.
7. A separate `promote` command verifies the report and writes the passing checkpoint to the local model registry. Selecting **Tinker / Inkling** in Settings then uses that checkpoint for inference.

Raw data lives at:

```text
~/Library/Application Support/Shakespeare/personalization/training_events.jsonl
```

The directory is owner-only (`0700`) and the ledger and model registry are owner-only files (`0600`). Use the Personalization settings tab to reveal or delete the ledger.

## Compile and inspect

No Tinker dependency or API key is needed to compile data or run its regression tests.

```bash
make personalization-evals

PYTHONPATH=Trainer python3 -m shakespeare_train compile \
  --output Trainer/data/compiled
```

The compiler emits:

- `sft_train.jsonl` and `sft_eval.jsonl` from accepted edits and final prose continuations.
- `dpo_train.jsonl` and `dpo_eval.jsonl` from rejected assistant edits.
- `manifest.json` with counts, source hash, and the deterministic split policy.

All examples from a document stay in one split. This prevents near-identical passages from the same draft leaking from training into evaluation.

## Train Inkling with Tinker

Use a dedicated virtual environment. Training is the only step that uploads compiled examples to Tinker.

```bash
python3.11 -m venv .venv-trainer
source .venv-trainer/bin/activate
python -m pip install -e Trainer
export TINKER_API_KEY='...'
```

The project pins the Tinker Cookbook version because its dataset-builder and checkpoint APIs are still evolving.

Start with a one-epoch SFT run. Inkling does not have a universal learning rate for personal writing data, so the CLI requires an explicit value instead of silently choosing one.

```bash
shakespeare-train train \
  --dataset-dir Trainer/data/compiled \
  --log-path Trainer/runs/inkling-sft-001 \
  --learning-rate <experiment-value> \
  --epochs 1
```

Rejected edits can drive a separate DPO run. It can start from the base model or from the SFT run's `state_path`:

```bash
shakespeare-train train-dpo \
  --dataset-dir Trainer/data/compiled \
  --log-path Trainer/runs/inkling-dpo-001 \
  --learning-rate <experiment-value> \
  --load-checkpoint '<sft-state-path>'
```

Do not promote a checkpoint solely because training completed. Compare it with the base model on the held-out documents first: blind preference, instruction adherence, factual preservation, unwanted phrase copying, and regression on grammar/mechanical edits. Keep the base provider available as a rollback.

The promotion report is a versioned JSON object. `dataset_manifest_sha256` must be the SHA-256 digest of the exact `manifest.json`, and `metrics` must contain the measured evaluation results:

```json
{
  "schema_version": 1,
  "status": "passed",
  "dataset_manifest_sha256": "<sha256-of-manifest.json>",
  "sampler_path": "<exact-final-sampler-path>",
  "metrics": {
    "blind_style_preference_win_rate": 0.72,
    "factual_preservation_rate": 1.0
  }
}
```

After evaluating the final checkpoint, promote it explicitly:

```bash
shakespeare-train promote \
  --dataset-dir Trainer/data/compiled \
  --log-path Trainer/runs/inkling-sft-001 \
  --evaluation-report Trainer/runs/inkling-sft-001/evaluation.json
```

The CLI binds the report to the exact dataset manifest and sampler path. Training and activation are separate actions, so a missing, failed, stale, or mismatched report cannot silently activate a checkpoint.

## Product boundary

The editor should remain native and local-first. A web service is useful as an optional control plane for accounts, scheduled training, experiment tracking, billing, and multi-device checkpoint distribution. It should not become the source of truth for documents or raw writing events unless the writer explicitly opts into that separate sync boundary. The hosted boundary is described in [Service architecture](SERVICE_ARCHITECTURE.md).
