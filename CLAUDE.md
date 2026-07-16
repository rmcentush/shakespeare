# Repository contributor guide

`AGENTS.md` is the canonical source of repository instructions. Read it before making changes and keep this compatibility file intentionally brief so guidance cannot drift between tools.

## Required validation

Before handing off a change, run:

```bash
make typecheck
make evals
swift build -Xswiftc -warnings-as-errors
```

Run `make install` when `/Applications/Shakespeare.app` should be updated.

## Architecture guardrails

- Preserve the single JavaScript-to-Swift bridge described in `AGENTS.md`.
- Keep inference providers behind `LanguageModelService.Provider`.
- Keep personalized training and fine-tuning in a dedicated service layer.
- Access packaged resources through `Bundle.shakespeareResources`.
- Preserve user documents, settings, and unrelated worktree changes.
