# Repository contributor guide

`AGENTS.md` is the canonical source of repository instructions. Read it before making changes and keep this compatibility file intentionally brief so guidance cannot drift between tools.

## Required validation

Before handing off a change, run:

```bash
make typecheck
make evals
make service-test # when Service/ or Trainer/ changes
swift build -Xswiftc -warnings-as-errors
```

Run `make install` when `/Applications/Shakespeare.app` should be updated.

## Architecture guardrails

- Preserve the single JavaScript-to-Swift bridge described in `AGENTS.md`.
- Keep inference providers behind `InferenceSettings` and `LanguageModelService`.
- Keep personalized event capture in `TrainingEventStore` and remote training in `Trainer/`.
- Keep hosted identity, tenancy, durable jobs, and model lifecycle in `Service/`.
- Preserve separate local and hosted personalization consent scopes.
- Access packaged resources through `Bundle.shakespeareResources`.
- Preserve user documents, settings, and unrelated worktree changes.
