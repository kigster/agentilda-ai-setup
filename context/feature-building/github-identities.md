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
| `luke-implementer` | the author   | **No** — pull requests open under your own account |
| `hansolo-reviewer` | the approver | **Yes**                                            |

Giving Luke an identity too costs a second account and buys nothing: he is already distinct from Han Solo the moment Han Solo is distinct from you.

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

1. **Organisation → Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Homepage URL: the repository. Webhook: **off**.
   - Repository permissions: `Pull requests: Read and write`. Nothing else.
   - Where can this be installed: **only this account**.
1. Generate a private key; it downloads once. Store it with `sopsy`, not on disk.
1. **Install** the App and choose the repositories it reviews.
1. Note the **App ID** and the **installation ID** (the trailing number in the install settings URL).
1. Mint an installation token when you need one — it lasts an hour:
   ```bash
   jwt=$(ruby -rjwt -rtime -e '
     key = OpenSSL::PKey::RSA.new(File.read(ENV["APP_PRIVATE_KEY_PATH"]))
     now = Time.now.to_i
     puts JWT.encode({iat: now - 60, exp: now + 540, iss: ENV["APP_ID"]}, key, "RS256")')

   token=$(gh api -X POST "app/installations/$INSTALLATION_ID/access_tokens" \
     -H "Authorization: Bearer $jwt" -q .token)

   GH_TOKEN="$token" gh pr review "$PR" --approve --body "…"
   ```
   Reviews then appear as `your-app[bot]`.

In CI, skip all of that and use `actions/create-github-app-token`, which does the JWT exchange for you.

______________________________________________________________________

## Make the approval mean something

An approval nobody requires is a comment with a green tick. Add a branch protection rule on `main`: **Require a pull request before merging → Require approvals: 1**.

The useful property is that you cannot satisfy it yourself. Every merge then needs Han Solo to have looked, which is the whole point of him.

______________________________________________________________________

## Two things to change in this repository first

Both are live today, and both matter more once an agent holds a token that can approve.

**`gh pr review` is not in `FORBIDDEN_COMMANDS`.**

```ruby
FORBIDDEN_COMMANDS = /\bgit\s+(push|commit)\b|\bgh\s+(pr|release)\s+(create|edit|merge)\b/
```

`create`, `edit` and `merge` are blocked; `review` and `comment` are not. Han Solo can already post to GitHub, and nothing intended that. Approving should be allowed for him *specifically*, while `gh pr merge` stays blocked for everyone — that is the "approve but never merge" line, and it is not drawn yet.

**`network: false` does not mean offline.**

```ruby
def denied_for(agent) = agent.network ? [] : DENIED_TOOLS   # WebFetch, WebSearch
```

It denies two tools. Han Solo has `Bash`, and `gh` reaches the network perfectly well through it. The flag is a statement about `WebFetch` and `WebSearch`, not a boundary — worth renaming or enforcing before it is trusted as one.

______________________________________________________________________

## If you would rather not do any of this

Han Solo can leave a review that is not an approval, from your own account:

```bash
gh pr review "$PR" --comment --body "…"
```

It lands in the Reviews timeline rather than the conversation, so it reads as a review. It will not satisfy branch protection, and it should not — nobody independent has looked.
