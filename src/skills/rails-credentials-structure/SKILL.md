---
name: rails-credentials-structure
description: Inspect the key structure of encrypted Rails credentials WITHOUT printing any secret values. Use whenever you need to know what keys exist in config/credentials (any environment) — e.g. to wire a credentials.dig(...) lookup — instead of running a bare `credentials:show`, which would dump secrets into the transcript.
---

# Rails credentials: structure only, never values

To see which keys exist in encrypted credentials without exposing the values,
run (from the app root, with the right master/environment key available):

```bash
rails credentials:show --environment production | awk 'BEGIN{FS=":"}{printf "%s:\n", $1}' | sed '/^:$/d'
```

- Swap `--environment production` for `development`, `staging`, or drop it for
  the default `config/credentials.yml.enc`.
- Indentation is preserved, so nested keys remain readable as a tree.
- On macOS with the user's toolchain conventions, `gawk`/`gsed` are drop-in
  replacements for `awk`/`sed` if the BSD versions misbehave.
- In direnv-managed projects run it as `direnv exec . bin/rails credentials:show ... | ...`.

Never run a bare `credentials:show` when only the structure is needed — the
output lands in transcripts/logs and leaks every secret in the file.
