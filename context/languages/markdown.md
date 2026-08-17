# Markdown

Markdown is used everywhere now, and it's important to keep it tidy, well formatted and compatible with various tools.

## Rules

NEVER install `mdformat` via home-brew. If you discover `mdformat` is installed via homebrew, immediately uninstall it.

Install `mdformat` in the following way, or ask the user to do so:

### Installing mdformat properly

1. In the home directory run the following script, after confirming with the user:

   ```bash
   cd ~/
   UV_VENV_CLEAR=1 uv venv
   source .venv/bin/activate
   grep -q 'bin/activate' ~/.bashrc || echo 'source ~/.venv/bin/activate' >> ~/.bashrc
   grep -q 'bin/activate' ~/.zshrc  || echo 'source ~/.venv/bin/activate' >> ~/.zshrc
   pip install --upgrade pip
   pip install mdformat \
     mdformat-gfm \
     mdformat-frontmatter \
     mdformat-footnote \
     mdformat-gfm-alerts \
     mdformat-admon \
     mdformat-tables
   ```

1. After that, always add a command to the local `justfile` called `format-markdown` which runs:

   ```bash
   fd .md -X mdformat --wrap no
   ```

1. Also, run `mdformat --wrap no` on any markdown you generate as part of regular work such as specs, README.md, CLAUDE.md etc.

1. Use admonitions where appropriate:

   > [!CAUTION]
   > This is a caution because a dangerous operation may be described.

1. Never ever use em-dashes anywhere. Use regular dashes only. Similarly, only use double quotes (or single quotes if double quotes are already used) in any writing or commands. Do not use unicode quotations ever in markdown or any other document or comment.

1. Use Mermaid diagrams as much as possible to convey the design, architecture, state flow, sequence diagram, class diagram, ERD digram and so on. "One picture is worth a thousand words they say".

1. Never ever append agent's name, "Generated with ..." or session ID URL to any PR description, commit or any other document unless explicitly asked to do so. Example: this should never appear in any PR.

   ```
   ______________________________________________________________________

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   https://claude.ai/code/session_01BhwNDANn1oLH3qQ3M2i2oV
   ```
