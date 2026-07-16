from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

SYSTEM_PROMPT = (
    "You are a writing assistant adapting to one writer. Preserve meaning, factual claims, "
    "and formatting while following the writer's instruction and established voice."
)


@dataclass(frozen=True)
class CompileResult:
    source_events: int
    accepted_edit_examples: int
    rejected_preference_examples: int
    continuation_examples: int
    skipped_events: int
    train_documents: int
    eval_documents: int
    sft_train_examples: int
    sft_eval_examples: int
    dpo_train_examples: int
    dpo_eval_examples: int


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                value = json.loads(stripped)
            except json.JSONDecodeError as error:
                raise ValueError(f"Invalid JSON at {path}:{line_number}: {error}") from error
            if not isinstance(value, dict):
                raise ValueError(f"Expected an object at {path}:{line_number}")
            records.append(value)
    return records


def _write_jsonl(path: Path, records: Iterable[dict[str, Any]]) -> int:
    count = 0
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
            count += 1
    return count


def _is_eval_document(document_id: str, eval_fraction: float) -> bool:
    bucket = int(hashlib.sha256(document_id.encode("utf-8")).hexdigest()[:8], 16) / 0xFFFFFFFF
    return bucket < eval_fraction


def _clean(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _edit_prompt(event: dict[str, Any]) -> str:
    instruction = _clean(event.get("instruction")) or "Revise this passage in my voice."
    original = _clean(event.get("originalText"))
    context = _clean(event.get("surroundingText"))
    category = _clean(event.get("learningCategory"))
    parts = [f"Instruction: {instruction}"]
    if category:
        parts.append(f"Editorial category: {category}")
    if context and context != original:
        parts.append(f"Context:\n{context}")
    parts.append(f"Passage:\n{original}")
    return "\n\n".join(parts)


def _snapshot_examples(event: dict[str, Any]) -> list[dict[str, Any]]:
    text = _clean(event.get("finalText"))
    paragraphs = [part.strip() for part in text.replace("\r\n", "\n").split("\n\n")]
    paragraphs = [part for part in paragraphs if 20 <= len(part.split()) and len(part) <= 4_000]
    examples: list[dict[str, Any]] = []
    for index in range(1, len(paragraphs)):
        context = "\n\n".join(paragraphs[max(0, index - 3) : index])[-4_000:]
        examples.append(
            {
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": "Continue this draft naturally in my established voice.\n\nDraft:\n" + context,
                    },
                    {"role": "assistant", "content": paragraphs[index]},
                ],
                "metadata": {
                    "document_id": _clean(event.get("documentID")),
                    "source_event_id": _clean(event.get("id")),
                    "example_type": "continuation",
                },
            }
        )
    return examples


def compile_ledger(input_path: Path, output_dir: Path, eval_fraction: float = 0.15) -> CompileResult:
    if not 0 <= eval_fraction < 1:
        raise ValueError("eval_fraction must be in [0, 1)")
    events = _read_jsonl(input_path)
    output_dir.mkdir(parents=True, exist_ok=True)

    sft: dict[str, list[dict[str, Any]]] = {"train": [], "eval": []}
    dpo: dict[str, list[dict[str, Any]]] = {"train": [], "eval": []}
    seen_event_ids: set[str] = set()
    documents: dict[str, str] = {}
    accepted = rejected = continuations = skipped = 0

    for event in events:
        event_id = _clean(event.get("id"))
        document_id = _clean(event.get("documentID"))
        if (
            event.get("schemaVersion") != 1
            or not event_id
            or event_id in seen_event_ids
            or not document_id
            or event.get("consent", {}).get("collectionEnabled") is not True
        ):
            skipped += 1
            continue
        seen_event_ids.add(event_id)
        split = "eval" if _is_eval_document(document_id, eval_fraction) else "train"
        documents[document_id] = split

        if event.get("eventType") == "document_snapshot":
            examples = _snapshot_examples(event)
            sft[split].extend(examples)
            continuations += len(examples)
            if not examples:
                skipped += 1
            continue

        if event.get("eventType") != "edit_decision":
            skipped += 1
            continue

        original = _clean(event.get("originalText"))
        proposed = _clean(event.get("proposedText"))
        final = _clean(event.get("finalText"))
        prompt = _edit_prompt(event)
        metadata = {
            "document_id": document_id,
            "source_event_id": event_id,
            "learning_category": _clean(event.get("learningCategory")),
        }

        if event.get("decision") == "accept" and final and final != original:
            sft[split].append(
                {
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": prompt},
                        {"role": "assistant", "content": final},
                    ],
                    "metadata": {**metadata, "example_type": "accepted_edit"},
                }
            )
            accepted += 1
        elif event.get("decision") in {"reject", "dismiss"} and original and proposed and original != proposed:
            dpo[split].append(
                {
                    "comparison": {
                        "prompt_conversation": [
                            {"role": "system", "content": SYSTEM_PROMPT},
                            {"role": "user", "content": prompt},
                        ],
                        "completion_A": [{"role": "assistant", "content": original}],
                        "completion_B": [{"role": "assistant", "content": proposed}],
                    },
                    "label": "A",
                    "metadata": {**metadata, "example_type": "rejected_edit"},
                }
            )
            rejected += 1
        else:
            skipped += 1

    counts = {
        "sft_train_examples": _write_jsonl(output_dir / "sft_train.jsonl", sft["train"]),
        "sft_eval_examples": _write_jsonl(output_dir / "sft_eval.jsonl", sft["eval"]),
        "dpo_train_examples": _write_jsonl(output_dir / "dpo_train.jsonl", dpo["train"]),
        "dpo_eval_examples": _write_jsonl(output_dir / "dpo_eval.jsonl", dpo["eval"]),
    }
    result = CompileResult(
        source_events=len(events),
        accepted_edit_examples=accepted,
        rejected_preference_examples=rejected,
        continuation_examples=continuations,
        skipped_events=skipped,
        train_documents=sum(value == "train" for value in documents.values()),
        eval_documents=sum(value == "eval" for value in documents.values()),
        **counts,
    )
    manifest = {
        "schema_version": 1,
        "source": str(input_path.resolve()),
        "source_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "eval_fraction": eval_fraction,
        "split_strategy": "sha256(document_id)",
        "result": asdict(result),
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return result
