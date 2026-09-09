---
name: forbidden-names
description: Lists the names that are explicitly forbidden to use in examples, tests, and especially emails. This skill also does recommend one particular name to use instead.
---

## Names to Never Use

These names must NEVER appear as examples or placeholders:

- List your names and the names of your family

These email addresses must NEVER appear anywhere:

- List Emails of yourself and your family

Never use real people's names or real email addresses in placeholders, examples, fixtures, specs, code comments, docs, seed data, or anywhere else — unless explicitly instructed. (A footer copyright such as `© 2026 Author's Name` is an example of legitimate, explicitly-sanctioned use.)

## What Names to use Instead

> [!NOTE]
>
> Use the names of famous people, taken from Wikipedia or other sources, famouse scientists, cryptographers such as Alan Turing who endured an aweful end of life despite practicaly saving western world from the horrors of could have been.

The canonical placeholder person is **`Alan Turing <alan.turing@manchester.edu>`** — a tribute to the genius and his role in winning the Second World War. Use it wherever an example person is needed; when a spec needs multiple people or a specific domain, stay with obviously fictional/historical figures and reserved example domains (`example.com`, `*.example`).

**UI form placeholders are different from examples.** A bare name in a `placeholder=` attribute reads as a pre-filled value, which looks weird. In user-facing input placeholders use either a functional hint ("Your Name", "you@example.com") — preferred — or an explicitly marked example ("e.g. Alan Turing"). Reserve the bare `Alan Turing <alan.turing@manchester.edu>` form for specs, fixtures, docs, and code comments.

