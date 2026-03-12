#!/usr/bin/env python3
"""
Download Havelock models from HuggingFace and convert to CoreML.

Produces:
  - HavelockBERT.mlpackage  (shared BERT encoder → 768-dim pooler output)
  - havelock_regressor_head.json  (Linear(768,1) weights + bias)
  - havelock_category_head.json   (Linear(768,2) weights + bias)
  - havelock_subtype_head.json    (Linear(768,71) weights + bias)
  - bert_marker_category_labels.json  (copied from HF)
  - bert_marker_subtype_labels.json   (copied from HF)
  - vocab.txt  (BERT tokenizer vocab)
"""

import json
import os
import sys
import shutil

import torch
import torch.nn as nn
import numpy as np
import coremltools as ct
from transformers import BertModel, BertTokenizer

HF_REPO = "thestalwart/havelock-orality"
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Sources", "WordProcessor", "Resources", "Havelock")

# ── Model definitions (must match training code) ──────────────────────────

class BertOralityRegressor(nn.Module):
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


class BertClassifier(nn.Module):
    def __init__(self, num_classes, bert_model_name='bert-base-uncased', dropout=0.1):
        super().__init__()
        self.bert = BertModel.from_pretrained(bert_model_name)
        self.dropout = nn.Dropout(dropout)
        self.classifier = nn.Linear(self.bert.config.hidden_size, num_classes)

    def forward(self, input_ids, attention_mask):
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        pooled_output = outputs.pooler_output
        pooled_output = self.dropout(pooled_output)
        return self.classifier(pooled_output)


# ── BERT-only wrapper for CoreML export ───────────────────────────────────

class BertEncoderOnly(nn.Module):
    """Just the BERT encoder, outputs pooler_output."""
    def __init__(self, bert):
        super().__init__()
        self.bert = bert

    def forward(self, input_ids, attention_mask):
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        return outputs.pooler_output


# ── Helpers ───────────────────────────────────────────────────────────────

def download_file(filename):
    """Download a file from the HF repo using huggingface_hub or urllib."""
    cache_dir = os.path.join(os.path.dirname(__file__), ".havelock_cache")
    os.makedirs(cache_dir, exist_ok=True)
    local_path = os.path.join(cache_dir, filename)
    if os.path.exists(local_path):
        print(f"  Using cached {filename}")
        return local_path

    url = f"https://huggingface.co/{HF_REPO}/resolve/main/{filename}"
    print(f"  Downloading {filename} ...")
    import urllib.request
    urllib.request.urlretrieve(url, local_path)
    return local_path


def extract_head_weights(state_dict, prefix):
    """Extract weight and bias from a linear head in a state dict."""
    weight_key = None
    bias_key = None
    for k in state_dict:
        if prefix in k and "weight" in k and "bert" not in k:
            weight_key = k
        if prefix in k and "bias" in k and "bert" not in k:
            bias_key = k
    # Fallback: find by layer name
    if weight_key is None:
        for k in state_dict:
            if "bert" not in k and "weight" in k:
                weight_key = k
            if "bert" not in k and "bias" in k:
                bias_key = k

    w = state_dict[weight_key].cpu().numpy().tolist()
    b = state_dict[bias_key].cpu().numpy().tolist()
    return {"weight": w, "bias": b}


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Output directory: {OUTPUT_DIR}\n")

    # ── Step 1: Download model files ──────────────────────────────────
    print("Step 1: Downloading model files from HuggingFace...")
    regressor_path = download_file("bert_orality_regressor.pt")
    category_path = download_file("bert_marker_category.pt")
    subtype_path = download_file("bert_marker_subtype.pt")
    cat_labels_path = download_file("bert_marker_category_labels.json")
    sub_labels_path = download_file("bert_marker_subtype_labels.json")

    # ── Step 2: Load models and extract head weights ──────────────────
    print("\nStep 2: Loading models...")

    # Load regressor
    regressor = BertOralityRegressor()
    regressor.load_state_dict(torch.load(regressor_path, map_location='cpu', weights_only=False))
    regressor.eval()

    # Load category classifier (2 classes)
    category_model = BertClassifier(num_classes=2)
    category_model.load_state_dict(torch.load(category_path, map_location='cpu', weights_only=False))
    category_model.eval()

    # Load subtype classifier (71 classes based on label file)
    with open(sub_labels_path) as f:
        subtype_labels = json.load(f)
    num_subtypes = len(subtype_labels)
    print(f"  Subtype classes: {num_subtypes}")

    subtype_model = BertClassifier(num_classes=num_subtypes)
    subtype_model.load_state_dict(torch.load(subtype_path, map_location='cpu', weights_only=False))
    subtype_model.eval()

    # ── Step 3: Extract head weights ──────────────────────────────────
    print("\nStep 3: Extracting head weights...")

    reg_head = extract_head_weights(regressor.state_dict(), "regressor")
    print(f"  Regressor head: weight {len(reg_head['weight'])}x{len(reg_head['weight'][0]) if isinstance(reg_head['weight'][0], list) else 1}")

    cat_head = extract_head_weights(category_model.state_dict(), "classifier")
    print(f"  Category head: weight shape {len(cat_head['weight'])}x{len(cat_head['weight'][0])}")

    sub_head = extract_head_weights(subtype_model.state_dict(), "classifier")
    print(f"  Subtype head: weight shape {len(sub_head['weight'])}x{len(sub_head['weight'][0])}")

    # Save head weights as JSON
    for name, head in [("regressor", reg_head), ("category", cat_head), ("subtype", sub_head)]:
        out_path = os.path.join(OUTPUT_DIR, f"havelock_{name}_head.json")
        with open(out_path, "w") as f:
            json.dump(head, f)
        size_kb = os.path.getsize(out_path) / 1024
        print(f"  Saved {name} head: {size_kb:.0f} KB")

    # ── Step 4: Convert BERT encoder to CoreML ────────────────────────
    print("\nStep 4: Converting BERT encoder to CoreML...")

    # Use the BERT from the regressor (all 3 share bert-base-uncased weights,
    # but we use the fine-tuned version from the regressor)
    bert_encoder = BertEncoderOnly(regressor.bert)
    bert_encoder.eval()

    # Create dummy inputs
    dummy_ids = torch.zeros(1, 128, dtype=torch.long)
    dummy_mask = torch.ones(1, 128, dtype=torch.long)

    # Trace
    print("  Tracing model...")
    traced = torch.jit.trace(bert_encoder, (dummy_ids, dummy_mask))

    # Convert to CoreML
    print("  Converting to CoreML (float16)...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, ct.RangeDim(1, 512)), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, ct.RangeDim(1, 512)), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="pooler_output")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )

    mlpackage_path = os.path.join(OUTPUT_DIR, "HavelockBERT.mlpackage")
    if os.path.exists(mlpackage_path):
        shutil.rmtree(mlpackage_path)
    mlmodel.save(mlpackage_path)
    # Calculate size
    total_size = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, _, fns in os.walk(mlpackage_path)
        for f in fns
    )
    print(f"  Saved CoreML model: {total_size / 1024 / 1024:.1f} MB")

    # ── Step 5: Copy label files and vocab ────────────────────────────
    print("\nStep 5: Copying label files and vocab...")

    shutil.copy(cat_labels_path, os.path.join(OUTPUT_DIR, "bert_marker_category_labels.json"))
    shutil.copy(sub_labels_path, os.path.join(OUTPUT_DIR, "bert_marker_subtype_labels.json"))

    # Save tokenizer vocab
    tokenizer = BertTokenizer.from_pretrained("bert-base-uncased")
    vocab_path = os.path.join(OUTPUT_DIR, "vocab.txt")
    tokenizer.save_vocabulary(OUTPUT_DIR)
    print(f"  Vocab file: {os.path.getsize(vocab_path) / 1024:.0f} KB")

    print(f"\nDone! All files saved to {OUTPUT_DIR}")
    print("\nFiles:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        p = os.path.join(OUTPUT_DIR, f)
        if os.path.isdir(p):
            total = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(p) for fn in fns)
            print(f"  {f}/ ({total / 1024 / 1024:.1f} MB)")
        else:
            print(f"  {f} ({os.path.getsize(p) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
