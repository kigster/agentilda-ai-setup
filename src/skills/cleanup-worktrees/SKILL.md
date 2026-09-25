---
name: clean-worktrees
description: Inspect every git worktree of the current repository, salvage anything useful into pull requests (draft or ready, with lint and tests passing), then remove the worktrees that hold nothing left to lose. Use when asked to clean up, prune, triage or delete worktrees.
---

# Clean worktrees

A worktree is removed only after everything in it exists somewhere else: on `main`, or on a pushed branch with an open pull request. Removing a worktree that holds uncommitted or unpushed work deletes data that cannot be recovered.

## 1. Inventory (read-only)

```bash
git fetch --prune origin
git worktree list --porcelain
alock list                                  # locks held in this repo
(unset GH_TOKEN; gh pr list --state all --limit 200 --json number,headRefName,state,isDraft,title)
```

Record these facts for each worktree except the main checkout:

| Fact                      | Command, run in the worktree                                                   |
| ------------------------- | ------------------------------------------------------------------------------ |
| Branch and HEAD           | `git branch --show-current`, `git rev-parse --short HEAD`                      |
| Uncommitted changes       | `git status --porcelain` (include untracked files)                             |
| Commits missing from main | `git log --oneline origin/main..HEAD`                                          |
| Commits never pushed      | `git log --oneline @{u}..HEAD`, or all of them if there is no upstream         |
| Pull request              | Match the branch to the `gh pr list` output: none, open, merged or closed      |
| In use by an agent        | `alock list` shows locks under this path, or files changed in the last 2 hours |
| Last activity             | `git log -1 --format=%cr`, plus the mtime of the newest changed file           |

A worktree that is locked or was active recently belongs to a live session. Report it and skip it. Never break a lock without asking first.

## 2. Classify

- **Empty**: clean, and every commit is already on `origin/main` (merged, or no commits of its own). It can be removed.
- **Superseded**: its commits or changes are already on `main` under different hashes. Check with `git cherry -v origin/main HEAD` and by diffing the changed files against `main`. It can be removed. Say what superseded it.
- **Covered**: clean, everything pushed, and an open pull request contains every commit (`gh pr view <n> --json commits`). It can be removed; the pull request keeps the work.
- **Salvage**: has unmerged work that is not superseded and not yet in an open pull request. Go to step 3.
- **Unclear**: you cannot tell whether the work matters. Ask the user. Do not guess.

Read the diff before calling anything useless. A branch name says what its author intended, not what the branch contains.

## 3. Salvage into a pull request

For each salvage worktree:

1. Claim it: `alock acquire <worktree-path> "salvaging for PR"`.
1. Seed it with `~/.agents/bin/setup-worktree`, then run `direnv allow .`.
1. Commit any uncommitted work on its branch as atomic commits that follow the repository's commit rules. If the branch's pull request was already merged, create a new branch from `origin/main` and cherry-pick the unmerged commits onto it.
1. Rebase onto `origin/main`. Resolve conflicts, or stop and report them.
1. Run the project's own checks and get them green: `just lint && just test` where a justfile exists, otherwise the project's own commands. Fix failures. Do not push red.
1. Push, then open the pull request with `/create-pr`:
   - **Ready for review** when the work is complete for its stated purpose, the checks pass, and it has tests.
   - **Draft** when it is partial, has TODOs or stubs, lacks tests, or you had to guess at its intent. Say which in the body.
1. Verify the result. Do not trust the push output:
   ```bash
   (unset GH_TOKEN; gh pr view <n> --json state,isDraft,commits)
   git log --oneline origin/main..origin/<branch>
   ```
1. Release the lock by path.

## 4. Confirm, then remove

Show the user one table: worktree, branch, class, reason, and pull request number. **Ask before removing anything.** Removal cannot be undone for anything that never left the machine.

After the user approves:

```bash
git worktree remove <path>          # never --force; a refusal means something is still uncommitted
git branch -d <branch>              # -d, not -D: git refuses if the branch is unmerged
git worktree prune
```

Delete remote branches only for merged pull requests, and only when asked.

## 5. Report

- Pull requests opened: number, draft or ready, and one line each.
- Worktrees removed, grouped by class.
- Worktrees kept, with the reason for each: locked, active, unclear or failing checks.
- Anything that needs the user's decision.
