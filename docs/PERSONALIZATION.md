# Personalization

Shakespeare learns through bounded context, not remote fine-tuning. Learning is
on by default, disclosed during setup, and can be paused or disabled under
**Settings → My Style**.

## What is used

For style-aware writing, Shakespeare may use:

1. the writer's requested meaning, facts, quotations, and instructions;
2. compact, reviewed style notes learned from recurring evidence;
3. a general writing-quality baseline;
4. relevant sections of the editable style reference;
5. up to two recent rewrites the writer changed and saved; and
6. up to two relevant excerpts from deliberately imported samples.

The style packet is capped at 8,000 characters. A separate 2,600-character map
provides limited document flow and continuity. Samples are examples of voice,
not instructions or factual sources, and their distinctive content must not be
copied.

The general baseline is informed by the MIT-licensed
[Avoid AI Writing](https://github.com/conorbronsdon/avoid-ai-writing) guide and
cross-checked against Wikipedia's descriptive
[Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
field guide and the [Microsoft](https://learn.microsoft.com/en-us/style-guide/brand-voice-above-all-simple-human)
and [Google](https://developers.google.com/style/tone) style guides. It treats
common model habits as contextual editing signals, not proof of authorship or
hard bans. Reviewed personal notes and deliberate choices in the draft take
precedence.

## Writing-option contracts

| Option | Dedicated prompt and guidance | Personal style |
| --- | --- | --- |
| Selection feedback | Focused critique, preserve strengths, at most three points | Reviewed notes plus bounded reference, rewrite, and sample excerpts |
| Inline gap fill | Write only the missing prose, connect both sides, invent no facts | Reviewed notes plus bounded reference, rewrite, and sample excerpts |
| Ambient review | Sparse, high-signal, anchored suggestions with a silence threshold | Reviewed notes plus bounded reference, rewrite, and sample excerpts |
| Automatic grammar | Precision-first objective grammar rules plus a conservative verification pass | Deliberately excluded |
| Thorough proofread | Broader objective inspection without stylistic rewriting | Deliberately excluded |

Each option has its own model-service instance and cache-routing session. The
three personalized options select their own section of the general baseline;
grammar options use separate style-neutral rules so correctness cannot drift
with a learned voice profile.

Ordinary research chat and grammar checks do not receive permanent style
context. An explicit **Feedback** request on selected text does, because the
writer is asking for an editorial comparison to their voice.

## Samples and edits

Use **Add Samples…** to import representative `.txt` or `.md` files. Files stay
in Shakespeare's owner-only local data folder; only selected excerpts are sent
for relevant style-aware requests.

Shakespeare waits for a successful save and uses only high-confidence outcomes.
Accepted-unchanged model prose never becomes a sample of the writer's voice.
An accepted suggestion can still contribute its abstract rationale as a weak
preference signal. A final passage enters the runtime rewrite-example layer
only when the writer changed it materially; punctuation or one-word tweaks stay
contrastive edit evidence instead of turning the surrounding model prose into a
voice sample. Repeated signals can become proposed preferences, but the writer
must review them before use. The proposed profile condenses those signals into
short, actionable notes about voice, syntax, rhythm, diction, punctuation, and
paragraph movement; it is not a raw-text archive.

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
the current **Writing Model** selection (Gemini Flash by default) and the same live
style evidence. Each option has its own system prompt, task-selected guidance,
output contract, and private cache-routing session. Ordinary research chat uses
the separate **Research Model** selection (Gemini Flash by default). Grammar and
spelling checks stay
style-neutral so correctness is not bent toward a personal voice. Automatic
grammar and the writer-invoked thorough proofread have distinct prompts and
cache sessions: the automatic option optimizes for interruption-worthy
precision, while the thorough option inspects more broadly without turning
style preferences into errors.

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

## Prompt caching

Every model-backed feature uses a private, per-session cache-routing identifier
and a cacheable instruction prefix. Different writing options do not share a
cache-routing session. Style-aware requests place the task-selected general
guidance and current reviewed profile in a stable cacheable block, followed by
task-relevant reference excerpts, examples, the live selection, nearby prose,
and document flow as a dynamic suffix. The complete prompt also
gets a final cache breakpoint so exact retries can reuse it. In general chat,
the previous and current user turns are cache breakpoints so a growing
conversation can reuse its history. Because provider caches are
content-addressed, changing the style profile, conversation, or document
produces a new entry instead of reusing stale text. Generated suggestions and
answers are never cached or replayed by Shakespeare.

OpenRouter usage events expose prompt, cache-read, and cache-write token counts
so cache behavior can be verified without recording document content.
