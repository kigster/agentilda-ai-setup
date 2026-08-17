# Color Mapping

The Authoritative Source: [spec-plan-build](~/.agents/context/feature-building/spec-plan-build.md)

# Directory Naming convention

## The Pattern:

```bash
\d\d\d-[status]-<feature-name-slug>

# Example:
cd 002-✅-dev-foundation
```

## Files Allowed to Exist in These Folders:

| Expected | Allowed |
| :--------: | :--------: |
| `spec.me` | `blocked.md`|
| `plan.md` | `rejected.md`|
| `pull-requests.md` |`delayed.md` |

## The Short Map & File Requirements
s
| Symbol | Meaning | Files Required| Description |
|:----:| :----: | :----: | :---- |
| ⚪️ | **new** | `spec.md` | a new feature or spec that has not been planned NOR implemented yet. |
| ⭐️ | **ready** | `plan.md` | the feature or spec is ready to be implemented. |
| 🟡 | **work in<br> progress** | `pull-requests.md` | the feature or spec is being implemented. |  
| ✅ | **done** | `pull-requests.md` | the feature or spec has been implemented. |
| 🅱️ | **product<br> blockages** | `blocked.md` | Product Specification Block: we *cannot* proceed; a PM must decide something first. |
| ⭕️ | **implementation blockage** | `blocked.md` | we *cannot* proceed; an engineer/CTO must decide something first. |
| ⛔️ | **rejected** | `rejected.md` | it never going to be implemented. |
| ☢️ | **deffered** | `delayed.md` | this is a deferred time bomb. Deferral with no trigger is indistinguishable from rot, and this status exists precisely so that deferrals stay honest instead of quietly becoming 🟢. Record the decision, the date, and who made it so that we can spank them. |

## Detailed Breakdown

- The [status] in the folder name is a single emoji.

1. For specifications created (eg, `spec.md` exists) but not yet planned, the `[status]` is ⚪️ (new)

2. For specifications that have juset `spec.md` and `plan.md` the [status] is ⭐️ (ready)

3. For specifications are in progress, the `[status]` is 🟡 (work in progress)

4. For specifications that are done, i.e. all open PRs within have been merged, the `[status]` becomes ✅ (done)

5. For specifications that are blocked due to ambiguity, contradiction to previous assumption, or any other reason in such a way that the plan can not be produced without breaking some past product decision, the `[status]` becomes 🅱️ and the agent must surface the blocking situation to the user and wait for human's decisions on how to proceed. The file `blocked.md` must be created in such a folder that describes in detail the reason this can not proceed forward without human's (typically Product Manager's) decision or approval. It's meant for humans and should be broken down into questions B1, B2, etc.

6. Another type of block that may occur is for technical reasons. For such cases, the `[status]` becomes ⭕️ (implementation constrained) and the agent must surface the blocking situation to the engineer or a CTO and wait for human's decisions on how to proceed. The file `blocked.md` must be created in such a folder that describes in detail the reason this can not proceed forward without human's (typically CTO's) decision or approval. It's meant for humans and should be broken down into questions B1, B2, etc.

7. For specifications that are intentionally delayed where the remaining work is **deliberately deferred** — not blocked, not declined, simply not now — the `[status]` is ☢️ ("revisit later ").
6. Another type of block that may occur is for technical reasons. For such cases, the `[status]` becomes ⭕️ (implementation constrained) and the agent must surface the blocking situation to the engineer or a CTO and wait for human's decisions on how to proceed. The file `blocked.md` must be created in such a folder that describes in detail the reason this can not proceed forward without human's (typically CTO's) decision or approval. It's meant for humans and should be broken down into questions B1, B2, etc.

7. For specifications that are intentionally delayed where the remaining work is **deliberately deferred** — not blocked, not declined, simply not now — the `[status]` is ☢️ ("revisit later ").

8. For specifications that have been written, possibly planned, possibly part-implemented, but ultimately rejected on the product grounds, or it was decided not to implement this feature because some other feature is either contradictory or in conflict with this one. The file `aborted.md` should be created with explanations and links and references to any related specs ⛔️. This is a terminal state.
