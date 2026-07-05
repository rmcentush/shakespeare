# Plan: minimal LLM edits + adaptive style guide

Two features, independent but complementary:

1. **Minimal edits** — LLM suggestions should replace the smallest changed span (a bracketed placeholder, a phrase), never a whole sentence/paragraph when only part of it changed.
2. **Adaptive style guide** — every accept/reject decision feeds back into the style-preference markdown, so the voice reference improves with use.

## Current state (verified against the code)

- **Sidebar edits** (`ClaudeChatViewModel.swift`): Claude calls tools (`propose_edit`, `replace_selection`, `insert_at_cursor`, `find_and_replace`, defined in `ClaudeAPIService.swift:38-120`). `propose_edit` targets `{block_id, exact_original, prefix, suffix, occurrence_index, document_revision, document_hash}`. The system prompt *already asks* for the smallest span (lines ~35-37), but nothing enforces it.
- **Ambient review** (`EditorViewModel.swift:747-877`): returns JSON comments with optional `suggested_replacement`; lands as anchored comments, convertible to pending edits.
- **Pending edits** (`Editor/src/pendingEdits.ts`): decoration + widget system. `sentenceSplitPendingEdits` (lines ~672-713) is the only mechanical granularity refinement — it splits a multi-sentence rewrite into per-sentence pending edits, but goes no finer.
- **Accept/reject**: `acceptPendingEdit`/`rejectPendingEdit` in `pendingEdits.ts` (~813-848) are the single choke points for every accept/reject (widget buttons, Tab/Shift-Tab, sidebar). **No decision is logged anywhere** — reject just filters the edit from plugin state.
- **Style guide**: `Sources/WordProcessor/Resources/david_oks_style_guide.md`, loaded once and cached by `AuthorStyleReference.swift` via `Bundle.module`. Read-only; changing it requires a rebuild. Injected as a prompt-cached `<author_voice_reference>` block in both the sidebar and ambient prompts.

---

## Part 1 — Minimal edits

Prompting alone won't guarantee minimality. Enforce it mechanically at the choke point where all edits are queued, and improve targeting upstream.

### 1a. Deterministic edit minimizer (the core change)

In `pendingEdits.ts`, where proposals become pending edits (`queueProposedEdit` / `queuePendingEdits`, alongside `sentenceSplitPendingEdits`):

- Run a **word-level diff** (Myers diff on word tokens; a small vendored implementation, no dependency needed) between the edit's `originalText` and the plain-text of `newHtml`.
- Emit **one pending edit per contiguous changed region**, trimmed to word boundaries with the common prefix/suffix stripped. All fragments from one proposal share a `groupId` (the existing sentence-splitter already establishes this pattern, so widget UI and accept-all semantics carry over unchanged).
- Coalesce changed regions separated by fewer than ~3 unchanged words into one edit, so the user isn't asked to approve five two-word confetti edits for one rewritten clause.

**HTML safety rules** (this is where naive diffing breaks):
- If `newHtml` is plain text or trivial inline HTML → diff on text, rebuild fragments as plain text (the existing `colorizeHTMLTextNodes` accepted-edit tinting still works).
- If the replacement's *text* equals the original but HTML differs (formatting-only change) → keep the edit whole; don't diff.
- If the replacement contains block-level structure (`<p>`, headers, lists) → fall back to the existing sentence-split path.

This guarantees minimality regardless of model behavior: even if Claude returns a full-paragraph rewrite, the user sees only the words that actually changed.

### 1b. Bracket-placeholder awareness

David drafts with bracketed placeholders (`[stat here]`, `[link]` — the style guide itself endorses this). Make them first-class targets:

- In `editContext.ts`, detect `[...]` spans per block and list them in the `<edit_context>` payload (e.g. `<placeholder block_id=... text="[stat here]"/>`).
- In the sidebar system prompt (`ClaudeChatViewModel.swift` `baseSystemPrompt`): "When the document contains bracketed placeholders, prefer `propose_edit` targeting exactly the bracketed span, including the brackets, over rewriting surrounding text."

### 1c. Server-side guardrail in `executeTool` (cheap, optional but recommended)

In `ClaudeChatViewModel.executeTool`, before queuing a `propose_edit`: compute the diff ratio between `exact_original` and the replacement text. If the span is long (> ~200 chars) and < ~25% of it changed, still queue it (the JS minimizer will shrink it) but return a `tool_result` note: "Queued, but only N words of your M-word target differ — target smaller spans." This trains the model within the conversation without costing an extra round-trip.

### Acceptance criteria

- Asking the sidebar to "tighten this paragraph" where one clause changes produces pending edit(s) covering only that clause.
- A fill-in of `[stat here]` produces an edit spanning exactly the bracketed text.
- Formatting-only and structural rewrites still work (no mangled HTML).
- Accept-all on a group reproduces the full intended rewrite.

---

## Part 2 — Adaptive style guide

Three sub-problems: make the guide writable, capture decisions, and turn decisions into guide updates without degrading a carefully hand-crafted document.

### 2a. Writable style guide

- On first launch, copy the bundled guide to `~/Library/Application Support/Shakespeare/style/david_oks_style_guide.md` (same directory pattern as `KeychainService`). `AuthorStyleReference` prefers the writable copy, falls back to the bundle, and drops its load-once cache in favor of an mtime check (or a `reload()` called after updates).
- Keep the *hand-written* guide pristine. All machine-driven learning goes in a **separate file**: `style/learned_preferences.md`, injected as its own prompt block (see cache note below).

### 2b. Decision capture

At the JS choke points `acceptPendingEdit` / `rejectPendingEdit` (and accept-all/reject-all), emit a new bridge message before mutating state:

```
sendToSwift('editDecision', { decision: 'accept'|'reject', source, kind,
  originalText, replacementText, surroundingSentence, groupId, timestamp })
```

Include `surroundingSentence` (extract from the doc at decision time) — a diff pair without context is much weaker evidence. Wire through `BridgeMessage.swift` and `EditorViewModel.handleBridgeMessage`, then append to `style/feedback_log.jsonl` via a new `StyleFeedbackStore.swift`. Also log decisions on ambient-review comments (accept-as-edit vs dismiss), which carry extra signal: the ambient `kind` (voice/concision/etc.) and rationale text.

Log everything; filter at distillation time. **Do not** treat each event as a style rule — a rejection can mean "factually wrong," "wrong span," or "leave my draft alone," not "bad style."

### 2c. Distillation into rules (batched, user-approved)

**Not** per-decision live rewriting — that churns the guide on weak evidence, degrades a curated document, and thrashes the prompt cache. Instead:

- **Trigger**: when the log accumulates ~20 new decisions, or manually via a Settings button ("Update style preferences from my edit history"). Surface a subtle indicator when an update is pending.
- **Distiller call** (Haiku-class model is fine): input = current `learned_preferences.md` + the new decision batch (accepted diffs, rejected diffs, with context and ambient rationales). Output = a proposed new version of `learned_preferences.md` only. Prompt constraints:
  - Each rule must be supported by **≥2 consistent decisions**; single observations go under a "Tentative" subsection or are dropped.
  - Rules must be phrased as actionable editing guidance ("Never replace 'very' doubling — doubled intensifiers are deliberate"), each with a date and evidence count.
  - The distiller must also **prune or merge** existing rules contradicted by newer decisions.
  - Hard cap (~30 rules / ~1,500 words) so the block never bloats the prompt.
- **User approval**: present the proposed file as a diff in a sheet (Settings or a toolbar affordance) with Approve / Edit / Discard. The whole feature is about respecting the author's judgment; silently mutating his style reference would be self-defeating. Mark processed log entries so they aren't re-distilled.

### 2d. Prompt integration and cache ordering

Prompt caching is prefix-based, so order blocks stable-first in both `buildSystemPrompt` (sidebar) and the ambient prompt:

```
base prompt → author_voice_reference (stable) → writing_style_guidance (stable)
→ learned_style_preferences (changes occasionally) → uncached document/context
```

The learned block sits last among cached blocks, so guide updates only invalidate its own suffix. Frame it as: `<learned_style_preferences>Rules distilled from the author's accepted/rejected edits. Where these conflict with the general voice reference, these win — they are more recent and more specific.</learned_style_preferences>`

### 2e. Quick win: short-term rejection memory (independent of distillation)

Feed the last ~10 rejected suggestions into the ambient-review prompt alongside the existing `<existing_comments>` dedup block ("the author rejected these recently; do not re-suggest similar changes"), and into the sidebar's edit context. This makes rejection feel immediately consequential while the batched distillation handles long-term learning. Costs one small uncached block.

---

## Suggested implementation order

1. **Decision capture** (2b) — smallest change, and every day without it is lost training data.
2. **Edit minimizer + bracket awareness** (1a, 1b, 1c).
3. **Writable guide + learned-preferences injection** (2a, 2d).
4. **Distillation + approval UI** (2c), then the rejection-memory quick win (2e).

## Files to touch

| File | Change |
|------|--------|
| `Editor/src/pendingEdits.ts` | Word-diff minimizer; `editDecision` events at accept/reject choke points |
| `Editor/src/editContext.ts` | Bracket-placeholder spans in edit context |
| `Sources/WordProcessor/Bridge/BridgeMessage.swift` | New `editDecision` payload case |
| `Sources/WordProcessor/ViewModels/EditorViewModel.swift` | Route `editDecision` → store; ambient prompt: learned block + rejection memory |
| `Sources/WordProcessor/ViewModels/ClaudeChatViewModel.swift` | Prompt tweaks (brackets, minimality); learned block in cache order; `executeTool` diff-ratio note |
| `Sources/WordProcessor/Services/ClaudeAPIService.swift` | Tool description tightening for `propose_edit` |
| `Sources/WordProcessor/Services/AuthorStyleReference.swift` | Writable-copy resolution, reload |
| **New** `Services/StyleFeedbackStore.swift` | JSONL log, batch trigger, processed markers |
| **New** `Services/StyleGuideUpdater.swift` | Distillation call, proposed-diff plumbing |
| `Sources/WordProcessor/Views/SettingsView.swift` | Update button, approval sheet, learned-prefs viewer |

## Deeper architectural changes (optional but high-leverage)

The plan above works within the current architecture. These four changes attack the *reasons* parts of it are fiddly. Ranked by leverage-to-effort; B and C are the ones most worth doing.

### A. Unified suggestion pipeline (bigger refactor; do only if investing long-term)

Today there are two divergent LLM-suggestion paths: sidebar → tools → pending edits, and ambient review → JSON → comments → (optionally) pending edits. Every cross-cutting concern in this plan — decision capture, minimization, dedup, rejection memory — must be built twice or wired at two entry points.

Deeper fix: one canonical `Suggestion` type (`{id, source, anchor (block_id + exact_original + prefix/suffix), originalText, replacementText, rationale?, kind?}`) and a single queue both surfaces feed into. Presentation (inline widget vs. comment) becomes a rendering choice, not a separate data path. Decision events, the minimizer, and dedup then live in exactly one place. This also cleans up the current asymmetry where ambient suggestions carry a rationale (`kind`, `comment`) but sidebar edits don't — the rationale field is valuable distillation signal and should exist on every suggestion.

### B. Provenance marks + accepted-then-revised tracking (highest learning value)

The current accepted-edit treatment — baking teal color into document HTML via `colorizeHTMLTextNodes` — is styling masquerading as provenance. Replace it with a real ProseMirror mark, e.g. `llmProvenance` with attrs `{editId, source, acceptedAt}`:

- The teal rendering becomes a style derived from the mark (and can be stripped on export/copy, which the baked color can't).
- **The payoff**: post-accept revisions become observable. When an accepted LLM edit is later rewritten by hand, log a third event type — `revised` — with Claude's version vs. the author's final version. *Accepted-then-revised pairs are the richest style signal available*, far stronger than binary accept/reject: they show exactly how the author's phrasing differs from Claude's near-miss. Implementation: on accept, the mark tags the span; a transaction observer watches marked ranges; after an idle period, if the text inside changed, snapshot `{suggested, final, context}` to the feedback log.
- Feed these pairs to the distiller as first-class evidence ("Claude wrote X, the author changed it to Y") — a handful of these teaches more than fifty rejections.

### C. Plain-text-first edit protocol (kills the hardest part of the minimizer)

The minimizer's complexity comes entirely from `replacement_html` being arbitrary HTML. Constrain the protocol instead:

- **Inline edits** (`propose_edit`, `replace_selection` for sub-paragraph spans): replacement is **text with a whitelisted inline vocabulary** — plain text plus `<em>`, `<strong>`, links. (Plain-text-only would be lossy: italics are load-bearing in this voice.) Word-diffing text-with-inline-marks is straightforward; arbitrary HTML diffing is not.
- **Structural edits**: a separate `rewrite_block` tool that replaces whole blocks and is *expected* to be coarse — no minimization attempted, rendered as a block-level before/after.

This does more than simplify the diff: the tool shapes the model's behavior. When the inline tool *can't* express a paragraph rewrite, Claude must either target small spans or explicitly reach for the block tool — minimality becomes the path of least resistance instead of an instruction to obey. Enforce the whitelist in `executeTool` (sanitize or bounce with a corrective `tool_result`).

### D. Single `PromptAssembler` service (small; do it)

Prompt assembly, block ordering, and cache-control flags are duplicated between `ClaudeChatViewModel.buildSystemPrompt` and the ambient path in `EditorViewModel`. Extract one service that owns the ordered block list — `[base, voice reference, tropes, learned preferences, rejection memory, document, edit context]` — with per-block cache flags. Sections 2d and 2e then become one-line changes, both surfaces stay consistent by construction, and future blocks (e.g. per-document notes) have an obvious home.

### E. Learned preferences as data, not prose (small-medium; optional)

Instead of a free-form `learned_preferences.md` that the distiller rewrites, store rules as structured records (`{id, ruleText, evidence: [event ids], status: tentative|active|retired, createdAt, lastConfirmedAt}`) and *render* markdown for the prompt. Evidence counting, the ≥2-observation threshold, contradiction pruning, and caps become mechanical checks instead of LLM judgment calls, and the approval UI can show each rule with the actual diffs that produced it. The LLM's job shrinks to the one thing it's needed for: phrasing candidate rules from clustered evidence.

### How these change the implementation order

If adopting B and C (recommended): do C first (protocol change shrinks the minimizer to a text differ), then decision capture including the provenance mark from day one (B) — retrofitting provenance later loses all interim revision data. A is worth it only as part of a broader investment in the app; D is cheap and should ride along with whichever prompt work happens first; E can wait until the first distillation pass proves the loop works.

## Risks and mitigations

- **Rejection ≠ style signal** → context captured per event; distiller prompt distinguishes style rejections from factual/targeting ones; ≥2-observation threshold; user approves everything.
- **Guide degradation** → hand-written guide never machine-edited; learned rules live in a separate, capped, dated, user-approved file.
- **HTML mangling in the minimizer** → conservative fallback ladder (plain-text diff → whole-edit → sentence split); never diff across block boundaries.
- **Prompt-cache thrash** → batched updates + learned block placed last among cached blocks.
- **Edit confetti** → coalesce nearby changed regions; group accept-all preserved via `groupId`.
