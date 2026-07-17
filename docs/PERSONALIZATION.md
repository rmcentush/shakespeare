# Personalization

Shakespeare learns through bounded context, not remote fine-tuning. Learning is
on by default, disclosed during setup, and can be paused or disabled under
**Settings → My Style**.

## What is used

For style-aware writing, Shakespeare may use:

1. the writer's requested meaning, facts, quotations, and instructions;
2. reviewed preferences;
3. up to two recent rewrites the writer changed and saved;
4. relevant sections of the editable style reference; and
5. up to two relevant excerpts from deliberately imported samples.

The style packet is capped at 8,000 characters. A separate 2,600-character map
provides limited document flow and continuity. Samples are examples of voice,
not instructions or factual sources, and their distinctive content must not be
copied.

Research chat and ordinary grammar checks do not receive permanent style
context.

## Samples and edits

Use **Add Samples…** to import representative `.txt` or `.md` files. Files stay
in Shakespeare's owner-only local data folder; only selected excerpts are sent
for relevant style-aware requests.

Accepting or rejecting a suggestion does not create a lasting preference by
itself. Shakespeare waits for a successful save, uses only high-confidence
outcomes, and never learns from accepted-unchanged model prose. Repeated signals
can become proposed preferences, but the writer must review them before use.

## Storage and deletion

Mutable personalization data is stored under:

```text
~/Library/Application Support/Shakespeare/personalization/
```

**Delete Learning History** removes samples, events, profile drafts, and learned
preferences. It keeps the writer-maintained style reference and does not delete
documents, recovery drafts, versions, settings, or the OpenRouter key.

The local history and sample library are bounded and compacted automatically.
The raw ledger is never uploaded as background data.
