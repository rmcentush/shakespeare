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
MAX_CONTINUATIONS_PER_DOCUMENT = 12
MIN_TRAINING_CONFIDENCE = 0.8


@dataclass(frozen=True)
class CompileResult:
    source_events: int
    accepted_edit_examples: int
    modified_accept_examples: int
    rejected_preference_examples: int
    continuation_examples: int
    ambiguous_rejections_skipped: int
    superseded_snapshots_skipped: int
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
                raise ValueError(
                    f"Invalid JSON at {path}:{line_number}: {error}"
                ) from error
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


def _document_splits(document_ids: set[str], eval_fraction: float) -> dict[str, str]:
    ordered = sorted(
        document_ids,
        key=lambda document_id: hashlib.sha256(document_id.encode("utf-8")).hexdigest(),
    )
    if eval_fraction == 0 or len(ordered) < 2:
        return {document_id: "train" for document_id in ordered}
    eval_count = max(1, min(len(ordered) - 1, int(len(ordered) * eval_fraction + 0.5)))
    eval_documents = set(ordered[:eval_count])
    return {
        document_id: "eval" if document_id in eval_documents else "train"
        for document_id in ordered
    }


def _clean(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _valid_event(event: dict[str, Any]) -> bool:
    consent = event.get("consent")
    schema_version = event.get("schemaVersion")
    event_type = event.get("eventType")
    allowed_types = {"edit_decision", "document_snapshot"}
    if schema_version == 2:
        allowed_types.add("edit_outcome")
    if (
        schema_version not in {1, 2}
        or event_type not in allowed_types
        or not isinstance(consent, dict)
        or consent.get("collectionEnabled") is not True
        or consent.get("scope") != "local_personalization"
    ):
        return False
    if not _clean(event.get("id")) or not _clean(event.get("documentID")):
        return False
    limits = {
        "instruction": 20_000,
        "originalText": 250_000,
        "proposedText": 250_000,
        "finalText": 500_000,
        "surroundingText": 250_000,
        "rationale": 20_000,
    }
    for field, maximum in limits.items():
        value = event.get(field)
        if value is not None and (not isinstance(value, str) or len(value) > maximum):
            return False
    if event_type == "edit_outcome":
        confidence = event.get("confidence")
        if (
            not _clean(event.get("parentEventID"))
            or not _clean(event.get("outcome"))
            or not isinstance(confidence, (int, float))
            or not 0 <= confidence <= 1
            or not isinstance(event.get("trainingEligible"), bool)
        ):
            return False
    return True


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


def _evenly_bounded_indices(length: int, limit: int) -> list[int]:
    if length <= limit:
        return list(range(length))
    if limit == 1:
        return [length - 1]
    return sorted({round(index * (length - 1) / (limit - 1)) for index in range(limit)})


def _snapshot_examples(event: dict[str, Any]) -> list[dict[str, Any]]:
    text = _clean(event.get("finalText"))
    paragraphs = [part.strip() for part in text.replace("\r\n", "\n").split("\n\n")]
    paragraphs = [
        part for part in paragraphs if 20 <= len(part.split()) and len(part) <= 4_000
    ]
    candidates: list[dict[str, Any]] = []
    for index in range(1, len(paragraphs)):
        context = "\n\n".join(paragraphs[max(0, index - 3) : index])[-4_000:]
        candidates.append(
            {
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": "Continue this draft naturally in my established voice.\n\nDraft:\n"
                        + context,
                    },
                    {"role": "assistant", "content": paragraphs[index]},
                ],
                "metadata": {
                    "document_id": _clean(event.get("documentID")),
                    "source_event_id": _clean(event.get("id")),
                    "example_type": "continuation",
                    "signal_confidence": 1,
                },
            }
        )
    return [
        candidates[index]
        for index in _evenly_bounded_indices(
            len(candidates), MAX_CONTINUATIONS_PER_DOCUMENT
        )
    ]


def _latest_by(events: Iterable[dict[str, Any]], key: str) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    for event in events:
        value = _clean(event.get(key))
        if not value:
            continue
        existing = latest.get(value)
        if existing is None or float(event.get("recordedAt") or 0) >= float(
            existing.get("recordedAt") or 0
        ):
            latest[value] = event
    return latest


def compile_ledger(
    input_path: Path, output_dir: Path, eval_fraction: float = 0.15
) -> CompileResult:
    if not 0 <= eval_fraction < 1:
        raise ValueError("eval_fraction must be in [0, 1)")
    events = _read_jsonl(input_path)
    output_dir.mkdir(parents=True, exist_ok=True)

    sft: dict[str, list[dict[str, Any]]] = {"train": [], "eval": []}
    dpo: dict[str, list[dict[str, Any]]] = {"train": [], "eval": []}
    seen_event_ids: set[str] = set()
    valid_events: list[dict[str, Any]] = []
    skipped = 0

    for event in events:
        event_id = _clean(event.get("id"))
        if not _valid_event(event) or event_id in seen_event_ids:
            skipped += 1
            continue
        seen_event_ids.add(event_id)
        valid_events.append(event)

    documents = _document_splits(
        {_clean(event.get("documentID")) for event in valid_events}, eval_fraction
    )
    outcomes = _latest_by(
        (event for event in valid_events if event.get("eventType") == "edit_outcome"),
        "parentEventID",
    )
    snapshots = [
        event for event in valid_events if event.get("eventType") == "document_snapshot"
    ]
    latest_snapshots = _latest_by(snapshots, "documentID")
    superseded_snapshots = len(snapshots) - len(latest_snapshots)
    skipped += superseded_snapshots

    accepted = modified_accepts = rejected = continuations = ambiguous_rejections = 0

    for event in latest_snapshots.values():
        split = documents[_clean(event.get("documentID"))]
        examples = _snapshot_examples(event)
        sft[split].extend(examples)
        continuations += len(examples)
        if not examples:
            skipped += 1

    for event in valid_events:
        if event.get("eventType") != "edit_decision":
            continue

        event_id = _clean(event.get("id"))
        document_id = _clean(event.get("documentID"))
        split = documents[document_id]
        original = _clean(event.get("originalText"))
        proposed = _clean(event.get("proposedText"))
        final = _clean(event.get("finalText"))
        outcome_name = "legacy"
        confidence = 1.0
        training_eligible = event.get("schemaVersion") == 1

        if event.get("schemaVersion") == 2:
            outcome = outcomes.get(event_id)
            if outcome is None:
                if event.get("decision") in {"reject", "dismiss"}:
                    ambiguous_rejections += 1
                skipped += 1
                continue
            outcome_name = _clean(outcome.get("outcome"))
            confidence = float(outcome.get("confidence") or 0)
            training_eligible = outcome.get("trainingEligible") is True
            final = _clean(outcome.get("finalText"))

        if not training_eligible or confidence < MIN_TRAINING_CONFIDENCE:
            if event.get("decision") in {"reject", "dismiss"}:
                ambiguous_rejections += 1
            skipped += 1
            continue

        prompt = _edit_prompt(event)
        metadata = {
            "document_id": document_id,
            "source_event_id": event_id,
            "learning_category": _clean(event.get("learningCategory")),
            "signal_outcome": outcome_name,
            "signal_confidence": confidence,
        }

        accepted_outcomes = {
            "accepted_unchanged",
            "accepted_modified",
            "later_accepted",
        }
        is_legacy_accept = (
            event.get("schemaVersion") == 1 and event.get("decision") == "accept"
        )
        if (
            (outcome_name in accepted_outcomes or is_legacy_accept)
            and final
            and final != original
        ):
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
            if outcome_name == "accepted_modified":
                modified_accepts += 1
        elif outcome_name == "rejected_rewritten" and final != proposed:
            dpo[split].append(
                {
                    "comparison": {
                        "prompt_conversation": [
                            {"role": "system", "content": SYSTEM_PROMPT},
                            {"role": "user", "content": prompt},
                        ],
                        "completion_A": [{"role": "assistant", "content": final}],
                        "completion_B": [{"role": "assistant", "content": proposed}],
                    },
                    "label": "A",
                    "metadata": {**metadata, "example_type": "rejected_then_rewritten"},
                }
            )
            rejected += 1
        else:
            if event.get("decision") in {"reject", "dismiss"}:
                ambiguous_rejections += 1
            skipped += 1

    counts = {
        "sft_train_examples": _write_jsonl(
            output_dir / "sft_train.jsonl", sft["train"]
        ),
        "sft_eval_examples": _write_jsonl(output_dir / "sft_eval.jsonl", sft["eval"]),
        "dpo_train_examples": _write_jsonl(
            output_dir / "dpo_train.jsonl", dpo["train"]
        ),
        "dpo_eval_examples": _write_jsonl(output_dir / "dpo_eval.jsonl", dpo["eval"]),
    }
    result = CompileResult(
        source_events=len(events),
        accepted_edit_examples=accepted,
        modified_accept_examples=modified_accepts,
        rejected_preference_examples=rejected,
        continuation_examples=continuations,
        ambiguous_rejections_skipped=ambiguous_rejections,
        superseded_snapshots_skipped=superseded_snapshots,
        skipped_events=skipped,
        train_documents=sum(value == "train" for value in documents.values()),
        eval_documents=sum(value == "eval" for value in documents.values()),
        **counts,
    )
    manifest = {
        "schema_version": 2,
        "source": str(input_path.resolve()),
        "source_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "eval_fraction": eval_fraction,
        "split_strategy": "sha256_ranked_documents_v2",
        "signal_policy": {
            "minimum_confidence": MIN_TRAINING_CONFIDENCE,
            "ambiguous_rejections_in_dpo": False,
            "latest_snapshot_only": True,
            "max_continuations_per_document": MAX_CONTINUATIONS_PER_DOCUMENT,
        },
        "result": asdict(result),
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return result
