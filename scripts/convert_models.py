#!/usr/bin/env python3
"""
Download Havelock BERT models from HuggingFace and convert to CoreML.

Three separate models:
1. bert_orality_regressor.pt → HavelockRegressor.mlpackage (doc-level scoring)
2. bert_marker_category.pt  → HavelockCategory.mlpackage  (oral/literate classification)
3. bert_marker_subtype.pt   → HavelockSubtype.mlpackage   (marker detection)
"""

import os
import json
import torch
import torch.nn as nn
import numpy as np
import coremltools as ct
from transformers import BertModel, BertTokenizer, BertForSequenceClassification
from huggingface_hub import hf_hub_download

MODEL_REPO = "thestalwart/havelock-orality"
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Sources", "WordProcessor", "Resources", "Havelock")


class BertOralityRegressor(nn.Module):
    """Matches the architecture in havelock-demo app.py exactly."""
    def __init__(self, bert_model_name='bert-base-uncased', dropout=0.1):
        super().__init__()
        self.bert = BertModel.from_pretrained(bert_model_name)
        self.dropout = nn.Dropout(dropout)
        self.regressor = nn.Linear(self.bert.config.hidden_size, 1)
        self.sigmoid = nn.Sigmoid()

    def forward(self, input_ids, attention_mask):
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        pooled_output = outputs.pooler_output
        pooled_output = self.dropout(pooled_output)
        logits = self.regressor(pooled_output)
        return self.sigmoid(logits).squeeze(-1)


def download_models():
    """Download all model files from HuggingFace Hub."""
    print("Downloading models from HuggingFace Hub...")
    files = {
        "regressor": hf_hub_download(repo_id=MODEL_REPO, filename="bert_orality_regressor.pt"),
        "category": hf_hub_download(repo_id=MODEL_REPO, filename="bert_marker_category.pt"),
        "subtype": hf_hub_download(repo_id=MODEL_REPO, filename="bert_marker_subtype.pt"),
        "cat_labels": hf_hub_download(repo_id=MODEL_REPO, filename="bert_marker_category_labels.json"),
        "sub_labels": hf_hub_download(repo_id=MODEL_REPO, filename="bert_marker_subtype_labels.json"),
    }
    print("Downloads complete.")
    return files


def convert_regressor(model_path, output_path):
    """Convert the document-level regressor to CoreML."""
    print("\n=== Converting Regressor ===")
    model = BertOralityRegressor()
    model.load_state_dict(torch.load(model_path, map_location="cpu", weights_only=True))
    model.eval()

    # Trace with example input (batch=1, seq_len=128)
    dummy_ids = torch.randint(0, 30522, (1, 128), dtype=torch.int32)
    dummy_mask = torch.ones(1, 128, dtype=torch.int32)

    traced = torch.jit.trace(model, (dummy_ids, dummy_mask))

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, 128), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="score")],
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT32,
    )
    mlmodel.save(output_path)
    print(f"  Saved: {output_path}")


def convert_classifier(model_path, labels_path, output_path, name):
    """Convert a BertForSequenceClassification model to CoreML."""
    print(f"\n=== Converting {name} ===")
    with open(labels_path) as f:
        labels = json.load(f)
    num_labels = len(labels)
    print(f"  Labels ({num_labels}): {list(labels.keys())[:5]}{'...' if num_labels > 5 else ''}")

    model = BertForSequenceClassification.from_pretrained(
        'bert-base-uncased', num_labels=num_labels
    )
    model.load_state_dict(torch.load(model_path, map_location="cpu", weights_only=True))
    model.eval()

    # Wrapper that returns softmax probabilities instead of raw logits
    class ClassifierWrapper(nn.Module):
        def __init__(self, bert_model):
            super().__init__()
            self.model = bert_model

        def forward(self, input_ids, attention_mask):
            outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
            return torch.softmax(outputs.logits, dim=1)

    wrapper = ClassifierWrapper(model)
    wrapper.eval()

    dummy_ids = torch.randint(0, 30522, (1, 128), dtype=torch.int32)
    dummy_mask = torch.ones(1, 128, dtype=torch.int32)

    traced = torch.jit.trace(wrapper, (dummy_ids, dummy_mask))

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, 128), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="probabilities")],
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT32,
    )
    mlmodel.save(output_path)
    print(f"  Saved: {output_path}")


def verify_models(files):
    """Quick sanity check: run all three models on a test sentence."""
    print("\n=== Verification ===")
    tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
    test = "We will fight on the beaches, we will fight on the landing grounds."

    encoding = tokenizer(test, truncation=True, max_length=128, padding='max_length', return_tensors='pt')
    ids = encoding['input_ids'].numpy().astype(np.int32)
    mask = encoding['attention_mask'].numpy().astype(np.int32)

    reg = ct.models.MLModel(os.path.join(OUTPUT_DIR, "HavelockRegressor.mlpackage"))
    cat = ct.models.MLModel(os.path.join(OUTPUT_DIR, "HavelockCategory.mlpackage"))
    sub = ct.models.MLModel(os.path.join(OUTPUT_DIR, "HavelockSubtype.mlpackage"))

    reg_out = reg.predict({"input_ids": ids, "attention_mask": mask})
    cat_out = cat.predict({"input_ids": ids, "attention_mask": mask})
    sub_out = sub.predict({"input_ids": ids, "attention_mask": mask})

    print(f"  Test: \"{test}\"")
    print(f"  Regressor score: {reg_out['score'].item():.3f}")

    cat_probs = cat_out['probabilities'].flatten()
    with open(files["cat_labels"]) as f:
        cat_labels = json.load(f)
    cat_id_to_label = {v: k for k, v in cat_labels.items()}
    pred_idx = int(np.argmax(cat_probs))
    print(f"  Category: {cat_id_to_label[pred_idx]} ({cat_probs[pred_idx]:.3f})")

    sub_probs = sub_out['probabilities'].flatten()
    with open(files["sub_labels"]) as f:
        sub_labels = json.load(f)
    sub_id_to_label = {v: k for k, v in sub_labels.items()}
    top3 = np.argsort(sub_probs)[-3:][::-1]
    markers = [(sub_id_to_label[int(i)], float(sub_probs[i])) for i in top3]
    print(f"  Top markers: {markers}")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    files = download_models()

    convert_regressor(
        files["regressor"],
        os.path.join(OUTPUT_DIR, "HavelockRegressor.mlpackage"),
    )

    convert_classifier(
        files["category"],
        files["cat_labels"],
        os.path.join(OUTPUT_DIR, "HavelockCategory.mlpackage"),
        "Category Classifier",
    )

    convert_classifier(
        files["subtype"],
        files["sub_labels"],
        os.path.join(OUTPUT_DIR, "HavelockSubtype.mlpackage"),
        "Subtype Classifier",
    )

    verify_models(files)

    # Clean up old single-model files
    old_model = os.path.join(OUTPUT_DIR, "HavelockBERT.mlpackage")
    if os.path.exists(old_model):
        import shutil
        shutil.rmtree(old_model)
        print(f"\n  Removed old {old_model}")

    for old_head in ["havelock_regressor_head.json", "havelock_category_head.json", "havelock_subtype_head.json"]:
        p = os.path.join(OUTPUT_DIR, old_head)
        if os.path.exists(p):
            os.remove(p)
            print(f"  Removed old {p}")

    print("\nDone! Three CoreML models ready in Resources/Havelock/")


if __name__ == "__main__":
    main()
