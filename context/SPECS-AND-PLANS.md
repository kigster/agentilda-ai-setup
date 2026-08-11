# Custom System for Building Multi-Step Software

Each software project is to have a root folder named `.plans`

You can place this document as a README.md into that folder, so that this information lives next to the plans themselves.

For each medium to large sized feature, you are to create a folder under `.plans/` that starts with a numeric number that's monotonically increasing with each new feature. The naming convention of these directories serves both as the status of the feature as the documentation about how and why things were implemented the way they were.

Each directory is allowed to one the following files:

1. `spec.md` is the first file created there.

1. `plan.md` is the second file created there.

1. `blockers.md` is the third file that can be created there, if the agent finds that building this feature is blocked on something or is blocked by something.

1. `pull-requests.md` is a file described down below, containing the list of all pull requests related to this feature and their status.

   ### Directory Naming Conventions

   Each directory is to be named as follows:

- `.plans/NNN-slug` — are folders containing spec, plans, and PR links for medium to large chunk of features. Inside of each folder is at least:

  - `spec.md` — specification, then

  - `plan.md`, after `spec.md` was analyzed and verified and turned into a TODO list of items.

  - when the feature is being worked on, one or more PR files is created inside (see below).

- Each `plan.md` can be implemented in several coincise pull requests. For each pull request a small file is to be created in the same folder, of the following name and contents

  - Plan folders go through four states, and are renamed accordingly. The base name is NNN-slug where NNN is a three digit number, and slug is a "kebab" name, eg: `001-[status]-initial-spec`

  - The [status] in the folder name is a singl emoji.

    1. For specifications created (eg, `spec.md` exists) but not yet planned, the `[status]` is ⚪️
    1. For specifications that have juset `spec.md` and `plan.md` the [status] is 🔵
    1. For specifications that have at least pull request created, but not yet merged, the `[status]` is 🟡
    1. For specifications that are done, i.e. all open PRs within have been merged, the `[status]` becomes 🟢
    1. For specifications that are blocked due to ambiguity, contradiction to previous assumption, or any other reason in such a way that the plan \*\*can not be produced without breaking some past decision \*\*, the `[status]` becomes ⭕️ and the agent must surface the blocking situation to the user and wait for human's decisions on how to proceed. The file `blockers.md` must be created in such a folder that describes in detail the reason this can not proceed forward without human's decision or approval.
    1. For specifications that have been created, but it was decided not to implement, the status is 🔴

  #### For Folders that Are Being Implemented or Have Been Implemented

  These folders will have the green circle, and in addition, for each pull request that was part of this feature, create a file `pull-requests.md` containing a table:

  - Column 1 (right aligned): **Pull Request Number**
  - Column 2 (left aligned): **Pull Request Name (which is also a link to Github)**
  - Column 3 (right aligned): **Status: Merged 🟣 | Closed Unmerged 🔴 | Open 🟡**

## Note on Pull Request File

> [!IMPORTANT]
> NOTE: some of the previous projects were instructed to create one \*.html file per pull request. This practice proved unweidly and not particularly helpful, so the single file `pull-requests.md` represents an evolution of that practice and superceeds any previous or local instructions.
