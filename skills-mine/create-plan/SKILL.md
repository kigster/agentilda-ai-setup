---
name: print-plan-folders
description: "Print the status of all folders under .plans and their corresponding PRs"
allowed-tools: [
  "Bash(spec-plan-build *)",
  "Bash(/usr/bin/find . -type d -and \( -name ".plans" -or -name "plans" \) -print )",
  "Bash(grep -v worktree)",
  "Bash(head -1)",
  "Bash(command -V spec-plan-build >/dev/null || { export PATH=\"${HOME}/.agents/scripts:${HOME}/.claude/scripts:${PATH}\"; })",
  "Bash(command -V spec-plan-build >/dev/null || { echo \"spec-plan-build is not in the PATH. Please ensure it is installed and available.\"; exit 1; })"
]
---

# Print Plan Folders

> [!NOTE]
>
> This skill is part of the **Spec → Plan → Build** workflow. It is used to print the status of all folders under `.plans` and their corresponding PRs.

## When to use

- The user wants to get the status of every spec or a plan and they have a `.plans` folder and they were using it to keep track of progress

## The tool

A Ruby script `spec-plan-build` must live in the global `PATH`. Within `.agents` with `direnv` enabled it will be added to the `$PATH`, but reliably the LLM should append to the shell initializer a statement that adds the path of the script: `${HOME}/.agents/scripts` (and `bin` as well) if you need it.

Therefore, it's critical that you check if this script is available in the `$PATH`, otherwise you need to:

1. Detect the shell user is currently using by running the following command: `/bin/ps -o"args" -p $$ | tail -1 | tr -d "-" | xargs basename`
2. Add the `${HOME}/.agents/scripts` and `${HOME}/.agents/bin` to the `$PATH` in their dot file (either `~/.zshrc` or `~/.bashrc` for those two shells)
3. Source the modified shell initialization file
4. You may need to execute `hash -r`
5. Ensure that the script is now in the path by running `command -v spec-plan-build`

Now we are ready to perform one of several requests this skill provides. 

## Using the Tool

First, cd to the root of the project tree and run the following bash script: 

```bash
command -V spec-plan-build >/dev/null || { 
  export PATH="${HOME}/.agents/scripts:${HOME}/.claude/scripts:${PATH}"
}
command -V spec-plan-build >/dev/null || {
  echo "spec-plan-build is not in the PATH. Please ensure it is installed and available."
  exit 1
}
if [[ -d .plans ]]; then
  spec-plan-build status                     # every plan, its state, its PRs
else
  dir=`/usr/bin/find . -type d -and \( -name ".plans" -or -name "plans" \) -print \
      | grep -v worktree \
      | head -1 || \
      { echo "No .plans folder found. Please ensure you are in the root of the project tree."; exit 1 }`
  if [[ -n ${dir} ]]; then
    cd "${dir}" && spec-plan-build status
  else
    echo "No .plans folder found. Please ensure you are in the root of the project tree."
  fi
fi
```

## Reference files

- [`${HOME}/.agents/context/feature-building/spec-plan-build.md`](${HOME}/.agents/context/feature-building/spec-plan-build.md) — the
  specification structure.
