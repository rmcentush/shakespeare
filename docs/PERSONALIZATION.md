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

Ordinary research chat and grammar checks do not receive permanent style
context. An explicit **Feedback** request on selected text does, because the
writer is asking for an editorial comparison to their voice.

## Samples and edits

Use **Add Samples…** to import representative `.txt` or `.md` files. Files stay
in Shakespeare's owner-only local data folder; only selected excerpts are sent
for relevant style-aware requests.

Shakespeare waits for a successful save and uses only high-confidence outcomes.
Accepted-unchanged model prose never becomes a sample of the writer's voice.
Repeated signals can become proposed preferences, but the writer must review
them before use.

## Inline writing gaps

Type `[[a short note about what belongs here]]`, then hover or place the cursor
in the gap and use the sparkle button. **Command-Return** works too. Shakespeare
uses the note, nearby prose, document flow, and the reviewed style profile to
draft one fill. Animated dots stay inside the brackets while it writes. The fill
remains inline with a **✓** to use it or **×** to leave the brackets in place.

If a used fill is saved unchanged, only its abstract style choices become a
weak preference signal—the generated wording is deliberately omitted from the
voice samples. If the writer changes the fill and saves it, the final
writer-edited wording becomes higher-quality style evidence. Leaving the gap,
rewriting it after rejection, or returning to it later is also resolved at save
time so the outcome reflects what remains in the document.

## Feedback on selected text

Select a passage and use the small sparkle beside the highlight. Shakespeare
sends the selected text, a bounded view of the surrounding draft, and the
latest reviewed style context to the writing model. It returns one direct
assessment and no more than three specific points in the chat sidebar.
Selection feedback never starts a web search; research remains available as a
separate follow-up when needed.

Selection feedback, inline gap fills, and ambient editorial suggestions all use
the current **Writing Model** selection (Kimi K3 by default) and the same live
style packet. Ordinary research chat uses the separate **Research Model**
selection (Gemini Flash by default). Grammar and spelling checks stay
style-neutral so correctness is not bent toward a personal voice.

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
