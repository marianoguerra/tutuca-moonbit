# Git Hooks

## Pre-commit Hook

This pre-commit hook performs automatic checks before finalizing your commit.

### Usage Instructions

Enable them with the `setup` task, which is the same `git config` invocation
plus the npm install the node-driven checks need:

```bash
moon run --target native cmd/dev -- setup
```

By hand, if you only want the hooks:

```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

The hook then runs on every `git commit`.

### What it checks, and what it does not

`moon check` on the DEFAULT target only. That is a deliberate floor rather than
a full gate: a pre-commit hook has to finish in the time someone is willing to
wait, and the real gate is `cmd/dev -- ci`, which type-checks all three targets
with `--warn-list +unnecessary_annotation`, runs the tests and the drift checks.
A commit that passes the hook can still fail CI, and that is the intended trade.
