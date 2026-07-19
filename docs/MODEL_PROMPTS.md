# Model prompt architecture

Shakespeare treats each model-backed feature as a separate contract. A contract
owns the role, task boundary, evidence rules, output shape, and local validation
for one user-visible option. Research, selection feedback, gap fill, ambient
review, automatic grammar, thorough proofread, grammar verification, and style
profile refinement do not share mutable conversation history.

## Contract rules

- Stable role and task instructions are system content. Each writing option has
  a distinct model-service instance, inference purpose, and cache-routing
  session.
- Writer text, document excerpts, samples, learned notes, saved rewrites, and
  model-produced evidence are untrusted data. Structured prompt payloads escape
  framework-owned tag delimiters; JSON payloads remain quoted data.
- Subjective writing options share the writing-quality baseline, then apply
  reviewed learned notes, relevant author-reference sections, and a small set of
  task-relevant examples according to an explicit precedence contract.
- Automatic grammar and thorough proofread deliberately exclude personal style.
  Their schemas accept only objective rule categories, and the automatic pass
  uses a separate conservative verifier.
- Machine-consumed responses use strict JSON Schema with described, bounded
  fields and `additionalProperties: false`. OpenRouter routing requires support
  for every requested parameter. Local decoders then validate anchors, limits,
  uniqueness, and safe applicability before anything reaches the editor.
- Research is the only flow that may enable web search. Search is selected by a
  deterministic policy, citations are validated as HTTP(S) URLs, and research
  history never enters editorial-writing requests.
- No generated edit is applied automatically. Empty, malformed, unanchorable,
  stale, duplicated, or structurally inconsistent output fails closed.

## Cache layout

Stable instructions come first. Reviewed learned notes and the option-selected
baseline form a stable style prefix. Live author-reference excerpts, samples,
document blocks, selections, and flow maps follow as dynamic content. The final
user prefix is also marked for exact retries. Each service sends a private
`session_id`, allowing OpenRouter sticky routing without sharing state between
features.

This follows OpenRouter's guidance for
[prompt caching](https://openrouter.ai/docs/guides/best-practices/prompt-caching)
and [strict structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs),
including `strict: true`, described schema fields, and
`provider.require_parameters: true`. Prompt structure follows Anthropic's
[prompting guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)
on explicit roles and consistent tagged boundaries, with untrusted content
handled according to its
[prompt-injection guidance](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks).

## Regression checks

`make check` verifies that every model call supplies a system prompt, editorial
options use separate services and cache sessions, style-aware options keep the
stable profile prefix ahead of live prose, structured outputs are strict, prompt
tags remain balanced, injection-shaped writer text is escaped, and deterministic
validators reject unsafe model output.
