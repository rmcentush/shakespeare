# Personalization

Shakespeare personalizes writing through bounded context, not remote post-training. This keeps the system immediate, inspectable, inexpensive, and easy to delete.

## Layers and precedence

For a style-aware writing request, Shakespeare assembles at most 8,000 characters (about 2,000 tokens) in this order:

1. Preserve the writer's requested meaning, facts, quotations, and explicit instructions.
2. Apply reviewed learned preferences.
3. Use up to two recent rewrites the writer actively changed and saved as positive, non-general examples.
4. Use task-relevant excerpts from the editable author reference.
5. Use up to two relevant writing-sample excerpts as rhythm and voice examples.
6. Use the current document only for topic and continuity.

Samples are never instructions or factual sources. The prompt explicitly forbids copying their names, facts, quotations, or distinctive phrases. Research chat and ordinary grammar checks do not receive permanent style context.

For edit and rewrite suggestions, Shakespeare also builds a separate document-flow map capped at 2,600 characters. It includes headings, opening and ending material, section boundaries, target-adjacent paragraphs, and evenly spaced checkpoints. The model uses this sparse map to understand the thesis, progression, transitions, and role of the editable passage, but it may target only the separately supplied full-fidelity blocks.

## Starting from writing samples

Enable **Learn From My Writing** in **Settings → My Style**, then choose **Add Samples…**. Import `.txt` or `.md` files that you wrote and consider representative.

- Files remain local in the owner-only Shakespeare data folder.
- Exact duplicates, very short pieces, unstructured pieces, and oversized files are rejected.
- At request time, local lexical retrieval selects no more than two relevant excerpts under a 1,600-character component budget, with at most one excerpt from each source file.
- When the writer asks to refine the durable profile, Shakespeare samples the beginning, middle, and end of at most five unprocessed source files. The complete files are not sent.
- Five substantial, independent pieces are a useful starting point.

This provides value immediately; there is no training job, uploaded dataset, checkpoint, or second provider account.

## Learning from edits

Learning is on by default and can be paused at any time. An explicit disabled choice is preserved. While enabled:

1. Shakespeare records a proposed edit decision locally.
2. Accepting or rejecting it does not by itself create a durable preference.
3. On successful save, the editor classifies whether the text was kept, revised, reverted, or rewritten.
4. Only high-confidence outcomes can contribute to the style evidence pool.
5. Text the writer actively modified or rewrote can enter a two-example runtime layer on the next review. Accepted-unchanged model prose is excluded to prevent self-reinforcement.
6. Repeated signals can be proposed as learned preferences.
7. The writer reviews and edits every proposed preference before approval.

Raw events and approved preferences remain separate. This avoids treating an accidental click or temporary wording choice as the writer's voice.

## Storage and deletion

All mutable style data is under:

```text
~/Library/Application Support/Shakespeare/personalization/
├── events/
└── style/
```

The tree and files are owner-only. **Delete Learning History** removes samples, events, and learned preferences. It does not delete documents, recovery drafts, version history, settings, or the OpenRouter key.

The local ledger retains a versioned historical field named `trainingEligible` for backward-compatible decoding. In the current product it means “high-confidence learning signal”; no training pipeline consumes it.

## Efficiency safeguards

- Style packets have a hard 8,000-character ceiling and a 2,000-token target.
- The durable profile has a separate 1,800-character ceiling.
- Ambient review examines at most 16 changed or cursor-near blocks plus the 2,600-character document-flow map.
- Imported samples and confirmed rewrites are locally retrieved instead of appended wholesale.
- Profile refinement sends bounded cross-document excerpts and at most 40 compact edit records, never the raw ledger.
- System guidance is cache-marked where OpenRouter and the selected model support prompt caching.
- Writing and research both default to `moonshotai/kimi-k3`, with one OpenRouter-native `~x-ai/grok-latest` fallback. Explicit Advanced overrides do not inherit that fallback, and both purposes share one credential.
- No vector database, embedding call, background upload, hosted control plane, or Python runtime is required.
