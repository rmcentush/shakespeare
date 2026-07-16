import hashlib
import json
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

from shakespeare_train.dataset import compile_ledger


def event(**overrides):
    value = {
        "schemaVersion": 1,
        "id": "event-1",
        "eventType": "edit_decision",
        "documentID": "document-a",
        "consent": {"collectionEnabled": True, "scope": "local_personalization"},
        "decision": "accept",
        "instruction": "Make this tighter.",
        "learningCategory": "concision",
        "originalText": "This is quite long and slow.",
        "proposedText": "This is slow.",
        "finalText": "This is slow.",
        "surroundingText": "This is quite long and slow.",
    }
    value.update(overrides)
    return value


class DatasetCompilerTests(unittest.TestCase):
    def compile(self, events, eval_fraction=0):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        ledger = root / "events.jsonl"
        ledger.write_text(
            "".join(json.dumps(item) + "\n" for item in events), encoding="utf-8"
        )
        output = root / "compiled"
        result = compile_ledger(ledger, output, eval_fraction)
        return result, output

    def test_accepted_edits_become_sft(self):
        result, output = self.compile([event()])
        self.assertEqual(result.sft_train_examples, 1)
        row = json.loads((output / "sft_train.jsonl").read_text(encoding="utf-8"))
        self.assertEqual(row["messages"][-1]["content"], "This is slow.")

    def test_rejected_edits_become_preferences(self):
        result, output = self.compile(
            [event(decision="reject", finalText=None, proposedText="This is terrible.")]
        )
        self.assertEqual(result.dpo_train_examples, 1)
        row = json.loads((output / "dpo_train.jsonl").read_text(encoding="utf-8"))
        self.assertEqual(row["label"], "A")
        self.assertEqual(
            row["comparison"]["completion_A"][0]["content"],
            "This is quite long and slow.",
        )
        self.assertEqual(
            row["comparison"]["completion_B"][0]["content"], "This is terrible."
        )

    def test_documents_never_cross_splits(self):
        first = event(id="one", documentID="shared")
        second = event(
            id="two",
            documentID="shared",
            originalText="A",
            proposedText="B",
            finalText="B",
        )
        result, _ = self.compile([first, second], eval_fraction=0.5)
        self.assertTrue(result.sft_train_examples == 0 or result.sft_eval_examples == 0)

    def test_multiple_documents_guarantee_an_evaluation_split(self):
        first = event(id="one", documentID="document-a")
        second = event(id="two", documentID="document-b")
        result, _ = self.compile([first, second], eval_fraction=0.15)
        self.assertEqual(result.train_documents, 1)
        self.assertEqual(result.eval_documents, 1)

    def test_opt_out_and_duplicate_events_are_skipped(self):
        opted_out = event(id="out", consent={"collectionEnabled": False})
        result, _ = self.compile([event(), event(), opted_out])
        self.assertEqual(result.sft_train_examples, 1)
        self.assertEqual(result.skipped_events, 2)

    def test_local_consent_scope_is_required(self):
        cloud_only = event(
            consent={"collectionEnabled": True, "scope": "service_personalization"}
        )
        result, _ = self.compile([cloud_only])
        self.assertEqual(result.source_events, 1)
        self.assertEqual(result.skipped_events, 1)


class PromotionGateTests(unittest.TestCase):
    def test_report_must_pass_and_match_manifest(self):
        from shakespeare_train.cli import _load_evaluation_gate

        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        manifest = root / "manifest.json"
        manifest.write_text('{"schema_version": 1}\n', encoding="utf-8")
        report = root / "evaluation.json"
        report.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "status": "passed",
                    "dataset_manifest_sha256": hashlib.sha256(
                        manifest.read_bytes()
                    ).hexdigest(),
                    "sampler_path": "tinker://checkpoint-a",
                    "metrics": {"style_preference_win_rate": 0.72},
                }
            ),
            encoding="utf-8",
        )
        loaded = _load_evaluation_gate(report, manifest, "tinker://checkpoint-a")
        self.assertEqual(loaded["status"], "passed")

    def test_report_must_match_checkpoint(self):
        from shakespeare_train.cli import _load_evaluation_gate

        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        manifest = root / "manifest.json"
        manifest.write_text("{}", encoding="utf-8")
        report = root / "evaluation.json"
        report.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "status": "passed",
                    "dataset_manifest_sha256": hashlib.sha256(
                        manifest.read_bytes()
                    ).hexdigest(),
                    "sampler_path": "tinker://different-checkpoint",
                    "metrics": {},
                }
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(RuntimeError, "sampler checkpoint"):
            _load_evaluation_gate(report, manifest, "tinker://checkpoint-a")

    def test_promote_is_a_separate_auditable_action(self):
        from shakespeare_train.cli import promote_command

        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        dataset = root / "dataset"
        run = root / "run"
        dataset.mkdir()
        run.mkdir()
        manifest = dataset / "manifest.json"
        manifest.write_text('{"schema_version": 1}\n', encoding="utf-8")
        sampler_path = "tinker://checkpoint-a"
        (run / "checkpoints.jsonl").write_text(
            json.dumps({"final": True, "sampler_path": sampler_path}) + "\n",
            encoding="utf-8",
        )
        report = run / "evaluation.json"
        report.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "status": "passed",
                    "dataset_manifest_sha256": hashlib.sha256(
                        manifest.read_bytes()
                    ).hexdigest(),
                    "sampler_path": sampler_path,
                    "metrics": {"blind_style_preference_win_rate": 0.72},
                }
            ),
            encoding="utf-8",
        )
        registry = root / "model_registry.json"
        result = promote_command(
            Namespace(
                dataset_dir=dataset,
                log_path=run,
                evaluation_report=report,
                base_model="thinkingmachines/Inkling",
                registry=registry,
            )
        )
        self.assertEqual(result, 0)
        promoted = json.loads(registry.read_text(encoding="utf-8"))
        self.assertEqual(promoted["schemaVersion"], 2)
        self.assertEqual(promoted["samplerPath"], sampler_path)
        self.assertEqual(promoted["evaluation"]["status"], "passed")


if __name__ == "__main__":
    unittest.main()
