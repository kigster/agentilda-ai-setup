# Custom System for Building Multi-Step Software

Each software project is to have a root folder named `.plans`

You can copy this document as a README.md into that folder, so that this information lives next to the plans themselves.

For each medium to large sized feature, you are to create a folder under `.plans/` that starts with a numeric number that's monotonically increasing with each new feature. The naming convention of these directories serves both as the status of the feature as the documentation about how and why things were implemented the way they were.

## Color Mapping

The Authoritative Source: [SPECS_AND_PLANS](~/.agents/context/SPECS-AND-PLANS.md)

## The Pattern:

```bash
\d\d\d\.\d\d-[status]-<feature-name-slug>

# Example:
cd 002.00-✅-dev-foundation
cd 002.01-✅-schedule-k1-form-series   # written retroactively; see below
```

## Files Allowed to Exist in These Folders:

|      Expected     |    Allowed    |
| :----------------:| :-----------: |
|     `spec.md`      | `blocked.md`  |
|     `plan.md`      | `rejected.md` |
| `pull-requests.md` | `delayed.md`  |

## The Short Map & File Requirements

| Symbol |           Meaning           |   Files Required   | Description                                                                                                                                                                                                                                                    |
| :----: | :-------------------------: | :----------------: | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|   ⚪️   |           **new**           |     `spec.md`      | a new feature or spec that has not been planned NOR implemented yet.                                                                                                                                                                                           |
|   ⭐️   |          **ready**          |     `plan.md`      | the feature or spec is ready to be implemented.                                                                                                                                                                                                                |
|   🟡   |  **work in<br> progress**   | `pull-requests.md` | the feature or spec is being implemented.                                                                                                                                                                                                                      |
|   ✅   |          **done**           | `pull-requests.md` | the feature or spec has been implemented.                                                                                                                                                                                                                      |
|   🅱️   |  **product<br> blockages**  |    `blocked.md`    | Product Specification Block: we *cannot* proceed; a PM must decide something first.                                                                                                                                                                            |
|   ⭕️   | **implementation blockage** |    `blocked.md`    | we *cannot* proceed; an engineer/CTO must decide something first.                                                                                                                                                                                              |
|   ⛔️   |        **rejected**         |   `rejected.md`    | it never going to be implemented.                                                                                                                                                                                                                              |
|   ☢️   |        **deferred**         |    `delayed.md`    | this is a deferred time bomb. Deferral with no trigger is indistinguishable from rot, and this status exists precisely so that deferrals stay honest instead of quietly becoming ✅. Record the decision, the date, and who made it so that we can spank them. |

## Detailed Breakdown

- The [status] in the folder name is a single emoji.

1. For specifications created (eg, `spec.md` exists) but not yet planned, the `[status]` is ⚪️ (new)

1. For specifications that have just `spec.md` and `plan.md` the [status] is ⭐️ (ready)

1. For specifications are in progress, the `[status]` is 🟡 (work in progress)

1. For specifications that are done, i.e. all open PRs within have been merged, the `[status]` becomes ✅ (done)

1. For specifications that are blocked due to ambiguity, contradiction to previous assumption, or any other reason in such a way that the plan can not be produced without breaking some past product decision, the `[status]` becomes 🅱️ and the agent must surface the blocking situation to the user and wait for human's decisions on how to proceed. The file `blocked.md` must be created in such a folder that describes in detail the reason this can not proceed forward without human's (typically Product Manager's) decision or approval. It's meant for humans and should be broken down into questions B1, B2, etc.

1. Another type of block that may occur is for technical reasons. For such cases, the `[status]` becomes ⭕️ (implementation constrained) and the agent must surface the blocking situation to the engineer or a CTO and wait for human's decisions on how to proceed. The file `blocked.md` must be created in such a folder that describes in detail the reason this can not proceed forward without human's (typically CTO's) decision or approval. It's meant for humans and should be broken down into questions B1, B2, etc.

1. For specifications that are intentionally delayed where the remaining work is **deliberately deferred** — not blocked, not declined, simply not now — the `[status]` is ☢️ ("revisit later").

1. For specifications that have been written, possibly planned, possibly part-implemented, but ultimately rejected on the product grounds, or it was decided not to implement this feature because some other feature is either contradictory or in conflict with this one. The file `rejected.md` should be created with explanations and links and references to any related specs ⛔️. This is a terminal state.

______________________________________________________________________

## The Number

A plan's number is its identity. It is set once, when the folder is created, and never changes: branch names, pull request titles and `pull-requests.md` all join on it, and renumbering breaks every one of those links silently.

### Pull request titles carry it

A pull request that implements a plan says so in its title:

```
[003] Make the core deterministic and require as_of
```

`pull-requests.md` in each plan folder is generated from these titles, so the prefix is the join key between a pull request and a plan, not decoration. Name branches `NNN-slug` (or `<user>/NNN-slug`) and the number carries itself from branch creation through to a merged, squashed pull request with nobody having to remember it.

Resolve it with `plan-number --title "<title>"` (`~/.agents/scripts/plan-number`), which reads the branch name first and falls back to the diff only when that touches exactly one plan folder. **It refuses rather than guessing.** A wrong number does not announce itself: it files the work under a plan that did not do it and leaves the plan that did looking untouched.

### `[XXX]` when there is no plan

Not every pull request implements a feature. Dependency bumps, CI configuration, hotfixes and documentation typos implement no plan, and forcing a number onto them produces a number chosen to satisfy the rule. Those are titled:

```
[XXX] Bump json from 2.21.1 to 2.21.2
```

`XXX` means **"this deliberately belongs to no specification"**, and it exists so that "no plan" is *asserted* rather than merely absent. A title with no prefix at all is ambiguous between "no plan applies" and "nobody looked"; `[XXX]` is the author saying which.

Two rules keep it from becoming the lazy default:

- **`plan-number` will never emit `XXX` on its own.** Only `--none` produces it. Emitting it on a failed lookup would launder "I could not tell" into "there is definitely none", which is the same lie as guessing a number, told in the other direction.
- **CI rejects `[XXX]` on a pull request that edits any plan's `spec.md` or `plan.md`.** That is the one case where the assertion can be checked against evidence, and a pull request writing a plan's specification is that plan's work however its title reads.

### `NNN.MM` for a plan written after the fact

Sometimes a substantial feature ships with no specification at all, and the gap is only noticed later. Writing a `spec.md` dated today and filing it as an ordinary plan would be **fabricated provenance**: the document's form claims the work was specified in advance when it was not, which is the same defect as a sign-off nobody gave.

So retroactive documentation gets its own number shape. Find the two plans the work landed between and take a decimal slot in that gap:

```
018-✅-yaml-round-trip-editing
018.01-✅-verify-against-filed-returns    <- shipped between 018 and 019, specced afterwards
019-⚪️-tax-law-tuning-service
```

`NNN.MM` is a **sibling of NNN that arrived later, not a part of NNN**. The dot reads as containment in almost every other numbering scheme and here it does not; say so wherever the scheme is documented, because the containment reading is what a new reader will bring.

Rules:

1. **The decimal is always exactly two digits**, `.01` through `.99`. One digit sorts into the middle of the two-digit range — `018.09` < `018.1` < `018.10` — so a single mixed-width folder silently reorders the index, and it reads as a typo whichever way you meet it. Two digits also retire the question of running out: 99 slots per gap, against a gap that closes the moment the next plan is created, since nothing merging today can land between 018 and 019.

1. **The decimal is the retroactivity marker.** There is no separate status emoji for "documented after the fact" and there should not be: the number already carries it, and a fact carried by the identifier cannot be lost when somebody edits the front matter. The status emoji keeps meaning exactly what it means for every other plan.

1. **Every retroactive `spec.md` opens with a dated line saying so**, naming the pull requests it describes. It documents what exists; it does not pretend to have decided anything.

1. **Anchor by when the work merged, not by what it is about.** Mechanical and auditable: compare the pull request's merge date against the creation date of each plan folder (`git log --diff-filter=A`). Anchoring by topic invites an argument nobody can settle, and the number is a slot, not a claim about subject matter.

1. **`000.MM` is legitimate** and means "before the plan discipline existed". Early foundational work usually lands here, and it sorts first, which is where it belongs.

1. **Reserve the decimal for retroactive backfill only.** The moment it is also used to split a live plan into parts, the notation means two things and neither is readable from the number alone. Forward subdivision needs a different device.

1. **Do not pad ordinary plans to `NNN.00`.** The asymmetry between `018` and `018.01` is the signal: one was specified before it was built and the other was not, and you can see which without opening either. A uniform `.00` buys column alignment and pays for it by hiding the distinction the notation exists to draw.

### If Linear arrives, this scheme retires

This numbering is homegrown because there is nothing else to join on. If the work moves to Linear, **the Linear issue key replaces it**: `[EQL-142] <title>` in pull request titles, `EQL-142-<status>-<slug>` for the folder, and the issue itself becomes the thing `pull-requests.md` is generated against.

Recording that here matters more than it looks. A numbering scheme with no stated exit becomes permanent by default: it accretes tooling, the tooling accretes rules, and by the time a real issue tracker shows up, migrating is a project rather than a decision. The exit is cheap only while it is written down and unbuilt.

Two things to hold to when that day comes:

- **Existing numbers do not get rewritten.** A plan's number is its identity and merged pull request titles are immutable history; `001` stays `001` forever and new plans start taking issue keys. A mixed index is ugly for a while and honest permanently, which beats a renumbering that breaks every link that ever pointed at a plan.
- **Do not teach the tooling to accept issue keys before Linear exists.** A validator that accepts `[EQL-142]` while there is no Linear to check it against is a guard that passes anything shaped like an answer, which is worse than one that fails loudly on the first real use.

### What does not deserve a retroactive plan

Most unmatched pull requests. The test is whether **somebody would need to read it** — a capability with behaviour, an interface, or invariants that are not obvious from the code. "Fix a typo", "remove dead code" and "bump a dependency" are `[XXX]` and always were. Backfilling those produces an index that is longer without being more informative, which makes the real plans harder to find.
