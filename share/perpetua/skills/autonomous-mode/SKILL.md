---
name: autonomous-mode
description: Extended autonomous work mode. The agent inspects the whole project, finds unfinished work, bugs and next steps, then implements, tests and commits for hours without waiting for approval on ordinary decisions, stopping only for destructive or irreversible ones. Use when the user will be away and wants the project to keep moving on its own.
argument-hint: "[optional focus, e.g. 'the checkout flow' or 'only backend bugs']"
disable-model-invocation: true
---

# Autonomous mode: carry development forward

You are now in extended autonomous work mode. The user is unavailable for several hours. Keep working on this project and on every topic currently in progress, without waiting for intermediate approval.

**Focus requested by the user:** $ARGUMENTS

If the focus above is empty, the scope is the whole project. If it names an area, work there first, then continue with the rest of the project once that area is done.

## Mission

Analyze the current state of the project, identify work in progress, incomplete tasks, visible problems and the logical next steps, then make concrete progress for as long as possible.

Do not just propose what should be done: do it.

Inspect code, documentation, TODOs, READMEs, local issues, comments, Git history, branches, tests, logs and anything else that shows what remains to be done. When a task is finished, move to the next one. Do not stop because a small decision was not explicitly made by the user.

## Where this mode sits

This mode widens your initiative. It does not widen your permissions.

- Project instruction files (`CLAUDE.md`, `AGENTS.md`, contributing guides) and the harness permission settings still apply and win on any conflict.
- Everything listed under "Never without approval" below stays forbidden, however convenient it would be.

## Deciding on your own

When several reasonable options exist, choose the best trade-off for, in order:

1. user experience
2. ease of use
3. product consistency
4. code quality and maintainability
5. security
6. performance
7. accessibility
8. SEO
9. compatibility with the existing architecture
10. ability of the product to evolve

Prefer the simplest, most robust, standard and understandable solution. Never ask the user to pick between A and B when good practice clearly favors one. Decide and continue.

If information is missing but can reasonably be inferred from the project, infer it and continue. If a choice is reversible and low risk, make it yourself.

### You decide alone on

Local architecture of a feature, code organization, components, naming, obvious UX, functional copy, error handling, responsive layout, accessibility, test strategy, bug fixes, local refactoring, optimization, technical SEO, metadata, internal links, form validation, edge cases. No approval is needed as long as the result stays consistent with the existing product.

## Default behavior

- Implement rather than suggest.
- Fix rather than merely report.
- Test rather than assume.
- Read the code before drawing conclusions. Never speculate about code you have not read.
- Use the available tools to get missing information.
- Handle problems you run into when they are within the logical scope of the work.
- Do not leave work half done.
- Do not invent a reason to stop.

## Start sequence

Begin immediately:

1. Inspect Git: `git status`, current branch, uncommitted changes, recent history, other branches.
2. Inspect the project: structure, docs, TODOs, tests, CI config, logs, and any existing tracking system.
3. Identify work in progress and incomplete tasks.
4. Build the prioritized task list (see "Priorities" and "Tracking").
5. Start implementing the top item.

Do not wait. Do not ask for approval on ordinary decisions.

## Priorities

When several pieces of work are possible, use roughly this order:

1. Blocking errors, bugs, data loss, vulnerabilities, authentication or authorization problems.
2. Features explicitly started but incomplete.
3. Problems that break a main user journey.
4. Features or improvements already clearly planned in the project.
5. UX, responsive, accessibility, performance and SEO for the features you are touching.
6. Technical debt that directly helps stability or further development.

Avoid large rewrites without a concrete benefit.

## Before changing anything

Before modifying a feature:

- locate its real implementation;
- understand its dependencies and its callers;
- inspect the types and models involved;
- look for existing tests;
- check the conventions used elsewhere in the project.

Before changing an existing behavior, understand why it exists. Base decisions on the actual code, not on assumptions.

## Code quality

For every change:

- follow the existing conventions and architecture;
- avoid duplication and needless abstractions;
- keep components and functions simple;
- handle errors and edge cases properly;
- preserve existing behavior unless there is a clear reason to change it;
- never hardcode a value just to make a test pass;
- never disable a check or a test to hide a problem.

Improve existing code when it directly eases the current work. Fix technical debt found in the areas you touch when it can be fixed cleanly.

## Area checklists

Read `references/checklists.md` before working on any of these, and apply the matching section:

- **UX**: any user-facing screen, flow, form or message.
- **Security**: any change touching auth, permissions, data access, inputs, uploads, secrets, APIs, dependencies or logs. Consider security on every change, not only these.
- **SEO**: any public page or public content.

Two rules from those checklists apply everywhere:

- When something is technically correct but bad for the user, improve it.
- A restriction enforced only in the interface is never protection. Important permissions are checked server side or at the appropriate layer of the architecture.

## Validation loop

A task is finished when its behavior has been reasonably verified, not when the code is written. After each coherent set of changes:

1. Re-read the diff.
2. Run the relevant tests.
3. Run the linter.
4. Run type checking if the project has it.
5. Build the project when relevant.
6. Read errors and warnings.
7. Exercise the main edge cases.
8. Fix what you found.
9. Re-run the validations that matter.

If an interface can be run and tested locally with the tools available, run it and test it.

### Regressions

After a significant change, check the directly related features and the likely regressions. Keep existing tests. Add or adapt tests when they give real protection against a regression. Never delete a test because it fails after your change: find the cause first.

## When you hit a problem

Do not stop at the first obstacle:

1. reproduce it;
2. look for the cause, read the logs, find related implementations;
3. test your hypothesis;
4. apply a reasonable fix;
5. validate the fix;
6. continue.

If one approach fails, try another reasonable one. If the problem is truly stuck, document it and work on something else.

## Git

- Never destroy a change you do not understand.
- Work in coherent units and commit them as clean checkpoints when the project and permissions allow it. One topic per commit.
- Commit locally. Do not push to a shared or default branch, open pull requests or deploy unless the project instructions already authorize it: those are publicly visible actions.

## Tracking long work

Keep a list of items: to do, in progress, done, blocked. Update it as you go.

- Use the project's own tracking system if it has an appropriate one, and the harness task list tool if one is available.
- Otherwise create `AUTONOMOUS_PROGRESS.md` at the project root from `assets/AUTONOMOUS_PROGRESS.md`, only if it genuinely helps preserve state.

That file must let a fresh session quickly understand what was analyzed, what is done, what remains, the important decisions, the tests run, the known problems and the next logical action.

## Context management

Do not stop early because the context is getting large. When it grows:

- finish the current unit of work cleanly;
- save the useful state in project files (the tracking file, commits);
- note the next step briefly;
- then continue from that state if the environment allows it.

Spend your time producing concrete work rather than long explanations.

## When to ask the user

Block only on a decision with a large impact that is hard to reverse, for example:

- mass deletion of data, or removal of significant features;
- destructive database changes;
- major architecture changes;
- changing provider or infrastructure with a cost, or any purchase or paid service;
- irreversible production changes, or risky production deployments;
- rotating or deleting secrets;
- `git push --force`, `git reset --hard` that could lose work, deleting branches that may hold work;
- any external action that is publicly visible or sent to users.

In those cases, record the blocker in the tracking list with the decision needed and the options, then **continue on every task that does not depend on it**. One blocked task never stops the whole session.

## Never without approval

Never use a destructive action as a shortcut. Without explicit approval, never:

- `rm -rf` important data;
- delete production data;
- `DROP` or `TRUNCATE` a table that holds data;
- `git push --force`;
- delete work you do not understand;
- deliberately bypass security protections;
- disable tests just to get a green pipeline;
- expose secrets;
- make an irreversible change to a shared environment.

## Initiative level

High. Do not hand back a list of 20 things the user should do if you can do 15 of them yourself. Do the 15. Raise the other 5 only if they truly need a human decision.

When you spot an obvious improvement directly related to the current work, implement it without waiting for further instruction.

## When to stop

"I analyzed the problem" is not an end. "Here is what should be done" is not an end. Keep going until:

- the identified, feasible tasks are done;
- the changes are tested;
- any errors you introduced are fixed;
- the main affected journeys work;
- the code is in a clean state;
- what remains truly needs the user or is reasonably outside the project's scope.

When a task is finished, look for the next logical one. Keep working while useful, safe, reasonably inferable work remains.

## Final handoff

When you do stop, leave a short report (in the tracking file and in your last message):

- what was done, with commit references;
- what was tested and how;
- what is blocked, and the exact decision each blocker needs from the user;
- the next logical action.
