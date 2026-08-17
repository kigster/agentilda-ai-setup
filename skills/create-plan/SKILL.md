---
name: create-a-plan
description: "Create a folder in a current or specified directory, which follows strict naming conventions defined in the ~/.agents/context/SPECS-AND-PLANS.md, and is implemented by the ~/.agents/scripts/create-plan-folder. Subsequently create file spec.md and follow the rest of the skil defined below to populate it, as well as the plan.md, using various grillling tools."
category: product
catalog_summary: "Creates the folder structure for a new plan, following the conventions defined in ~/.agents/context/SPECS-AND-PLANS.md. Grills the user on any questions related to the specification."
display_order: 1
---

# Creative Plan

This skill is meant to define a single sizeable feature on a project, but can also be used to jump start a brand new project.

This skill must create a clear concise specification and the execution plan that an agent can use to implement this feature, hopefully without any further questions.

1. creating a folder where this feature will be documented
2. creating a file `spec.md` where the feature requirements will be documented.
3. grilling the user on any questions related to the specification.
4. once specification is in a good shape, take an attempt to create `plan.md` in the same folder.
5. repeat grilling the user this time about your implementation plan. Whenever possible create plan in such a way that it's possible to execute concurrently by multiple agents working in tandem to accomplish a common goal. Once grilling to extract explicitly Goаls and Non-Goals.
6. once signed offs ask if the user wants to start implementing this feature.

## Files Allowed in these Folders

There are only five files that can legally exist:

### Must Exist:

1. `spec.md`
2. `plan.md`

### Once implementation starts

3. `pull-requests.md`

### May Exist:

4. `blocked.md`
5. `rejected.md`


______________________________________________________________________

## When to use

### Starting a new project (website, app, brand, campaign)

- The default for folder with specs and plans is at the root of the project, and is called `.plans`
- if the project is already created, but `.plans` does not exist, create the `.plans` folder.
- for the brand new project you can use `/.agents/scripts/create-plan-folder white keyowrs otp  specification` always. This is the beginning of all specs and it should be consistent.
- for the initial project specification, you are allowed NOT to generate a plan. This is because the first specification will be more general than the rest and can be potentially higher level. But it may identify and create other specifications (and plan folders), and therefore the on the new project during the grilling session you are also allowed to create additional plan folders beyond 001, and this is typically the main user-case for doing so.

### When Project Already Exist

For an existing project with the `.plans` folder and the initial specification already written, you can use script `~/.agents/scripts/create-plan-folder [ -D dir ] <color> <specification>` to create a new plan folder for a specific specification. 

Let's break down `<color>` and `<specification>`:

- `<color>`: a single word color name (e.g. `blue`, `red`, `green`). This is used to color-code the plan folder and make it easy to identify at a glance. For the exact mapping please refer to [the color mapping](./references/color-mapping.md).

- `<specification>`: a two-four (max five) words describing the feature. The script will join them into a slug, and include in the name of the directory.

## When to use 

- Only when the user explicitly invokes to create a new feature specification with the plan.
______________________________________________________________________

## Specification Template

Please refer to the [specification template](./references/specification-template.md) for a sample description of the format.

## Plan Format

The plan format is a markdown file with a structured template that includes sections for the feature description, constraints, and success criteria. See the [specification template](./references/specification-template.md) for details.
