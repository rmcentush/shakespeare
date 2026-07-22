# Personalization

Shakespeare can adapt writing suggestions to a writer's preferences. This
feature is local-first, off by default, and controlled under
**Settings → My Style**.

## Information used

When personal style guidance is enabled, Shakespeare may use a limited set of:

1. reviewed style notes;
2. relevant sections of the editable style reference;
3. recent revisions that the writer changed and saved; and
4. excerpts from deliberately imported `.txt` or `.md` writing samples.

The context sent for a writing request is size-limited. Samples are treated as
examples of voice, not as instructions or factual sources. Research and grammar
checks do not receive personal style history.

## Review and learning

Shakespeare records style evidence only after a successful save. Unchanged
suggestions do not become examples of the writer's voice. Repeated signals can
produce a proposed preference, but the writer must review it before it is used.

Inline gap fills, feedback on selected text, and editorial suggestions can use
the current reviewed style guidance. Objective grammar and proofreading remain
style-neutral.

## Writing samples

Use **Add Samples…** to import representative `.txt` or `.md` files. The files
are copied to Shakespeare's owner-only local data folder. Only relevant,
size-limited excerpts are included when the writer requests a style-aware
feature.

## Inline writing gaps

Type `[[a short note about what belongs here]]`, then place the pointer or cursor
in the gap and use the sparkle button. **Command-Return** works too. The proposed
fill remains inline until the writer accepts or dismisses it.

A fill saved without changes remains interaction history and does not become
style evidence. If the writer revises the fill and saves the document, the final
writer-edited wording may become style evidence.

## Storage and deletion

Mutable personalization data is stored under:

```text
~/Library/Application Support/Shakespeare/personalization/
```

**Delete Learning History** removes imported samples, recorded events, proposed
profiles, and learned preferences. It keeps the writer-maintained style
reference and does not delete documents, recovery drafts, versions, settings,
or connection credentials.

The local history and sample library are bounded and compacted automatically.
They are not uploaded as background data.
