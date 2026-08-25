# Color mapping — moved

> [!IMPORTANT]
> **This file no longer holds the status table.** It is kept only so that
> older links do not dangle.

The status vocabulary, the files each state requires, the transition table and
the numbering rules are **generated from the state machine**:

- Source of truth: `~/.agents/lib/spec_plan_build/lifecycle.rb`
- Generated document: [spec-plan-build.md](../../../context/feature-building/spec-plan-build.md)
- Regenerate with: `spec-plan-build docs -o context/feature-building/spec-plan-build.md`

## Why it moved

There were, at one point, **three** hand-maintained copies of the status
table: this file, the conventions document, and the emoji table inside the
folder-creation script. They disagreed.

The creator script could mint 🔵 and 🟢, which the reader did not recognise,
and could **not** mint ⭐️, ✅, 🅱️, ⛔️, ⬜️ or ☢️, which the reader required — so
a folder created by the tool could be unreadable by the tool.

That is what a fourth copy would cost, and it is why this one is now a
pointer.

To see the current states at any time:

```bash
spec-plan-build docs | less
```
