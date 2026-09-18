# Giving an agent a GitHub identity

`hansolo-reviewer` cannot approve a pull request that the same account opened. GitHub refuses it at the API, not at the permission layer:

```
422 Unprocessable Entity — Can not approve your own pull request
```

No token, scope or branch setting changes that. An approval needs a second identity, and this is how to get one.

______________________________________________________________________

## You need one identity, not one per agent

The rule GitHub enforces is **author ≠ approver**. Nothing stops one identity reviewing another's work, so only the reviewing side needs to be somebody new.

| Agent              | Acts as      | Needs its own identity                             |
| :----------------- | :----------- | :------------------------------------------------- |
| `luke-backend`     | the author   | **No** — pull requests open under your own account |
| `rey-frontend`     | the author   | **No** — same account; it opens the pull request   |
| `hansolo-reviewer` | the approver | **Yes**                                            |

Giving the implementers identities too costs an account each and buys nothing: both are already distinct from Han Solo the moment Han Solo is distinct from you. They are the authoring side, and the authoring side may be one account or ten.

It also runs into GitHub's Terms of Service, which permit exactly one:

> One person or legal entity may maintain no more than one free Account (if you also maintain a machine account, that's fine, but it can only be used for running a machine).

One machine account is sanctioned. Two is not.

______________________________________________________________________

## Which mechanism, for which repository

|                 | `kigster/dot-agents` (private, personal)                    | `equilibris-ai/*` (private, org)                                                    |
| :-------------- | :---------------------------------------------------------- | :---------------------------------------------------------------------------------- |
| Machine account | Free — collaborators on private personal repos cost nothing | **Costs a seat.** The org is on Team with 2 of 2 filled, so this means a third seat |
| GitHub App      | Works, more setup                                           | **Free** — apps do not consume seats                                                |

So: a **machine account** for the personal repository, a **GitHub App** for the organisation. If you only ever want one mechanism, make it the App.

______________________________________________________________________

## Route A — machine account

1. Sign out, create an account — `hansolo-reviews` or similar. Use an address you control; `+` addressing works (`you+hansolo@…`).
1. Turn on two-factor authentication. Private-repo collaborators in an org with 2FA enforcement are rejected without it.
1. From your own account, invite it: **Settings → Collaborators → Add people**. `Write` is enough; `Read` cannot approve.
1. On the machine account, create a **fine-grained personal access token**: **Settings → Developer settings → Personal access tokens → Fine-grained**.
   - Repository access: only the repositories it reviews.
   - Permissions: `Pull requests: Read and write`. Nothing else.
   - Expiry: 90 days. Put the renewal in a calendar; an expired token fails as a permissions error and reads like a misconfiguration.
1. Store it encrypted, never in plaintext:
   ```bash
   EDITOR=vim sopsy edit .env.encrypted    # add HANSOLO_GH_TOKEN=github_pat_…
   ```
1. Approve with it:
   ```bash
   GH_TOKEN="$HANSOLO_GH_TOKEN" gh pr review "$PR" --approve --body "…"
   ```

______________________________________________________________________

## Route B — GitHub App

**One App is enough for every repository you own.** It is *owned* by one account and *installed* on as many as you like, so the organisation and your personal account share an App ID, a private key and a bot identity. Only the installation ID differs, and it selects whose repositories a minted token can reach.

| Thing                  | How many                                      |
| :--------------------- | :-------------------------------------------- |
| App                    | one                                           |
| App ID and private key | one, shared                                   |
| Bot identity           | `your-app[bot]`, the same reviewer everywhere |
| Installation ID        | **one per account it is installed on**        |

A second App buys a second *name* in the Reviewers panel. It is not how you reach a second organisation.

1. **Organisation → Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Homepage URL: the repository. Webhook: **off**.
   - Repository permissions: `Pull requests: Read and write`. Nothing else.
   - Where can this GitHub App be installed: **Any account**. Not "only this account", or it can never install onto your personal repositories.
1. Generate a private key. It downloads once. Store it with `sopsy`, not on disk.
1. **Install it twice** — once on the organisation, once on your personal account — choosing the repositories each time.
1. Note the **App ID**, and one **installation ID** per installation: the trailing number in each install's settings URL.
1. Mint an installation token when you need one. It lasts an hour.

```bash
jwt=$(ruby -rjwt -e '
  key = OpenSSL::PKey::RSA.new(File.read(ENV["APP_PRIVATE_KEY_PATH"]))
  now = Time.now.to_i
  puts JWT.encode({iat: now - 60, exp: now + 540, iss: ENV["APP_ID"]}, key, "RS256")')

token=$(gh api -X POST "app/installations/$INSTALLATION_ID/access_tokens" \
  -H "Authorization: Bearer $jwt" -q .token)

GH_TOKEN="$token" gh pr review "$PR" --approve --body "…"
```

Reviews then appear as `your-app[bot]`. In CI, skip the exchange and use `actions/create-github-app-token`.

______________________________________________________________________

## Make the approval mean something

An approval nobody requires is a comment with a green tick. Add a branch protection rule on `main`: **Require a pull request before merging → Require approvals: 1**.

The useful property is that you cannot satisfy it yourself. Every merge then needs Han Solo to have looked, which is the whole point of him.

______________________________________________________________________

## What the harness now enforces

`FORBIDDEN_COMMANDS` is real. It was a regular expression that nothing referenced — a guard in the shape of a constant — which is how `gh pr review` came to be reachable by every agent and granted to none. It is now a list of commands withheld through `claude --disallowedTools Bash(<command>:*)`:

```
git push · git commit · gh pr create · gh pr edit · gh pr merge
gh pr review · gh pr comment · gh release create
```

An agent lifts one by naming it in its own file. Han Solo's:

```yaml
may: [gh pr review, gh pr comment]
```

`UNGRANTABLE` — `git push` and `gh pr merge` — cannot be lifted by any `may:`, however the definition is written. That is the approve-but-never-merge line, and it is now a property of the harness rather than an instruction in a prompt. An approval is reversible, visible and attributable to whoever made it; a merge changes a branch everyone else builds on.

The agent is also *told* what it has been granted. An agent that does not know it may approve simply never approves, and that looks exactly like an agent approving nothing worth approving.

### Still true, and still worth knowing

`network: false` denies `WebFetch` and `WebSearch`. It does not deny the network: an agent with `Bash` reaches GitHub through `gh` perfectly well. The command list above is what actually bounds that, so the flag is a statement about two tools and should be read as one.

______________________________________________________________________

## If you would rather not do any of this

Han Solo can leave a review that is not an approval, from your own account:

```bash
gh pr review "$PR" --comment --body "…"
```

It lands in the Reviews timeline rather than the conversation, so it reads as a review. It will not satisfy branch protection, and it should not — nobody independent has looked.
