import json
import tempfile
import unittest
from pathlib import Path

from shakespeare_train.dataset import compile_ledger


def event(**overrides):
    value = {
        "schemaVersion": 1,
        "id": "event-1",
        "eventType": "edit_decision",
        "documentID": "document-a",
        "consent": {"collectionEnabled": True},
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
        ledger.write_text("".join(json.dumps(item) + "\n" for item in events), encoding="utf-8")
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
        self.assertEqual(row["comparison"]["completion_B"][0]["content"], "This is terrible.")

    def test_documents_never_cross_splits(self):
        first = event(id="one", documentID="shared")
        second = event(id="two", documentID="shared", originalText="A", proposedText="B", finalText="B")
        result, _ = self.compile([first, second], eval_fraction=0.5)
        self.assertTrue(result.sft_train_examples == 0 or result.sft_eval_examples == 0)

    def test_opt_out_and_duplicate_events_are_skipped(self):
        opted_out = event(id="out", consent={"collectionEnabled": False})
        result, _ = self.compile([event(), event(), opted_out])
        self.assertEqual(result.sft_train_examples, 1)
        self.assertEqual(result.skipped_events, 2)


if __name__ == "__main__":
    unittest.main()
