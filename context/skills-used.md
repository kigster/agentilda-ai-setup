# Skills actually used

Generated 2026-08-21 by grepping every local Claude Code session transcript
(`~/.claude/projects/*/*.jsonl`, 420 files on this machine) for `Skill` tool
invocations, then counting by name.

> [!NOTE]
> This is usage data from **this machine only** — whatever session history
> happens to still be on disk. It undercounts: it doesn't see skills invoked
> from other machines, sessions already rotated out of local history, or use
> through a slash command in `src/commands/` (those back `spec-plan-build`
> directly and aren't `Skill` tool calls at all).

| Count | Skill | Source |
| ----: | :---- | :----- |
| 10 | `create-pr` | this repo — `skills/create-pr` |
| 5 | `update-config` | this repo — `skills/update-config` |
| 4 | `frontend-design:frontend-design` | plugin `frontend-design` |
| 4 | `grilling` | this repo — `skills/grilling` |
| 4 | `resolving-merge-conflicts` | this repo — `skills/resolving-merge-conflicts` |
| 3 | `github:create-pull-request` | plugin `github` |
| 2 | `create-plan` | **`src/skills/create-plan`** |
| 2 | `frontend:clerk-cli` | plugin `frontend` |
| 2 | `resend` | this repo — `skills/resend` |
| 1 | `artifact-design` | this repo — `skills/artifact-design` |
| 1 | `frontend-component-build` | this repo — `skills/frontend-component-build` |
| 1 | `grill-me` | this repo — `skills/grill-me` |
| 1 | `init` | this repo — `skills/init` |
| 1 | `landing-page-copy` | this repo — `skills/landing-page-copy` |
| 1 | `marketing-skills:marketing-ideas` | plugin `marketing-skills` |
| 1 | `mermaid-diagrams` | this repo — `skills/mermaid-diagrams` |
| 1 | `postgres-schema` | **`src/skills/postgres-schema`** |
| 1 | `stripe:stripe-best-practices` | plugin `stripe` |

18 distinct skills invoked at least once. Both `skills-mine/` skills
(`create-plan`, `postgres-schema`) show real use — small sample, but neither
is dead weight.

Everything else currently sitting in `skills/` (well over a hundred entries,
mostly SEO/marketing/product-design skills) shows **zero** invocations in
local history. That's not proof they're worthless — a skill earns its keep by
existing for the one time it's needed — but it is the honest answer to "which
have I actually reached for," and the input `scripts/install-sources` needs
to eventually prune or re-source deliberately rather than by hand.

## Regenerating this

```bash
python3 - <<'PY'
import json, collections, glob, os

counts = collections.Counter()
for path in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
    with open(path, errors="ignore") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            content = (obj.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if isinstance(item, dict) and item.get("type") == "tool_use" and item.get("name") == "Skill":
                    name = (item.get("input") or {}).get("skill")
                    if name:
                        counts[name] += 1

for name, n in sorted(counts.items(), key=lambda kv: -kv[1]):
    print(f"{n:4d}  {name}")
PY
```
