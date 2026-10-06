# Decisions on the pr-review-respond skill

A skill that tells an agent its open pull requests are under review, by a human or another agent, and that it must answer every review comment: fix and resolve what it agrees with, rebut what it does not.

## D1. Name and location

- **Decision:** a plain skill at `src/skills/pr-review-respond/`, invoked as `/pr-review-respond`.
- **Rejected:** a local plugin `pr-review` exposing `/pr-review:respond`. This repo has no local plugin build path, and adding one is out of scope for a single skill.
- **Date:** 2026-10-05

## D2. Which pull requests are in scope

- **Decision:** open pull requests in the current repository authored by the current `gh` user (`gh pr list --author @me`). Agents push as that user, so this covers agent PRs and hand-made ones alike.
- **Rejected:** filtering by the `kig/` branch prefix (misses `tilda run` worktree branches); every open PR (would push to other people's branches).
- **Date:** 2026-10-05

## D3. Waiting for reviews

- **Decision:** poll every 60 seconds. Any new activity is handled: a first review on an unreviewed PR, a reviewer reply on a thread the agent answered, or a fresh review after a push. Each new item resets a 5-minute idle clock. The agent exits after 5 quiet minutes, or at a hard cap of 30 minutes total.
- **Rejected:** a fixed 5-minute window with no reset; ignoring replies to rebuttals.
- **Date:** 2026-10-05

## D4. Where fixes are made

- **Decision:** if a worktree already has the PR's branch checked out, reuse it after claiming it with `alock`; a held claim means skip that PR and report it. Otherwise create a worktree under `~/.agents.worktrees/<branch-slug>` and seed it with `~/.claude/bin/setup-worktree`. Run the project's lint and test (`just lint && just test` where there is a justfile) before every push.
- **Rejected:** a throwaway worktree per PR (fails when another worktree holds the branch); the current checkout (collides with concurrent agents).
- **Date:** 2026-10-05

## D5. Replies and resolving

- **Decision:**
  - Fixed: reply "Fixed in `<sha>`" plus one line on what changed, then resolve the thread.
  - Rebutted: reply with evidence (spec, test, measurement) and leave the thread unresolved for the reviewer.
  - Question needing no code change: answer it, leave it unresolved.
  - Review summary bodies and PR conversation comments: one PR-level reply quoting each point and saying fixed or rebutted.
- **Rejected:** resolving rebutted threads (overrides the global rule that the human resolves disagreements); never resolving.
- **Date:** 2026-10-05

## D6. Bot notices are not reviews

- **Decision:** a review body or conversation comment matching `/Review limit reached/` or `/Review skipped/` is ignored: it needs no answer, and it does not make a PR count as reviewed. CodeRabbit's walkthrough summary is still a review and still gets an answer, since it sometimes carries real findings.
- **Where:** the `notice` filter in `scripts/pr-reviews`.
- **Date:** 2026-10-05

## D7. Fixes are proven by tests, never by running state-changing recipes

- **Decision:** the agent verifies fixes with the project's tests and linters only. A worktree seeded by `setup-worktree` carries the developer's real `.env`, so a reset, migrate, seed, import or drop recipe hits real local data.
- **Why:** during the first eval round, a run without the skill tested PR #226's production guard by running `just db-reset`, which dropped schema `atlas` in the local `atlas_development`. Restored the same day from `atlas_rename_check` (1162 / 54473 / 1662 rows, 5 migrations; no embeddings existed in any copy).
- **Date:** 2026-10-05

## D8. Claims about what runs are settled by the code that runs it

- **Decision:** a verdict that turns on runtime behaviour (evaluated, called, reachable, untrusted) cites the line that does it, or the search that found none, and the fix is sized to it.
- **Why:** in round 1 on #227, the run with the skill also guarded table `domain` bounds, which `taxreturn/src` never evaluates; the run without it read the code and left them alone.
- **Date:** 2026-10-05

## D9. A pull request that is no longer open is reported, never worked

- **Decision:** `pr-reviews pending <n>` returns `state` and, for a merged or closed PR, `status: merged` or `closed`. The agent answers nothing there and pushes nothing: a merged branch accepts pushes in silence.
- **Why:** in round 2, #229 merged mid-run; `pending 229` still reported it as a live PR because the open-only filter applied only when no number was given.
- **Date:** 2026-10-05
