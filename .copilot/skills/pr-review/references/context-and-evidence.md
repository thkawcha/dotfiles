# PR Review Context and Evidence

Load this reference when a review needs PR metadata, requirement traceability,
related history, or cross-repository evidence.

## PR and revision identity

- Prefer the PR's check/status and GitHub metadata for the remote head rather than
  assuming the current checkout is identical.
- Record base and head SHAs before analysis. Generated merge SHAs are useful for
  CI association but do not replace the author head when locating a regression.
- If the head changes during a review, mark the existing analysis stale and
  reassess changed findings before publication.
- Keep local working-tree changes out of a remote PR review unless the user
  explicitly asks for a combined review.

## What, Why, and How

Treat the headings as useful only when their contents are substantive:

- **What** states observable behavior, contract, or scope rather than repeating
  the title or listing files.
- **Why** identifies the user, operational, reliability, or maintenance problem
  and links supporting work when available.
- **How** explains the design, important alternatives or constraints, rollout,
  compatibility, and validation approach at the level needed to review risk.

Report missing or contradictory content as a traceability or reviewability gap.
Do not invent intent from the implementation when the author has not stated it.

## Linked issues and work items

Look for explicit GitHub issue URLs and closing keywords, Azure DevOps work-item
URLs, and unambiguous `AB#<id>` references in the PR body and commit messages.

For each accessible item:

1. Confirm it is the intended repository, project, and item rather than relying
   on a bare number.
2. Extract the problem statement, acceptance criteria, explicit non-goals, rollout
   constraints, and dependencies.
3. Map each requirement to implementation and test evidence.
4. Report requirements that are absent, contradicted, or untestable.

Use `gh` for GitHub reads. For Azure work items, use `azure-auth` before the
configured Azure DevOps tool or CLI. Do not create, edit, link, or transition a
work item during review. Authentication or authorization failure means
**unverified**, not **missing** or **satisfied**.

## Related PR search

Build the repository set from:

1. The current repository's canonical GitHub remote.
2. Every top-level submodule declared in its root `.gitmodules`, resolving relative
   URLs against the parent remote.

If the checkout has no usable parent remote, use the repository identity from the
PR metadata to resolve relative submodule URLs. If neither source is available,
report the reduced repository search scope rather than guessing an organization.

Do not recursively add nested submodules. Do not assume that only Meru-owned
repositories are relevant; use semantic relevance to filter external dependency
results.

Search open PRs and PRs updated, merged, or closed in the previous 90 days. Use a
small set of strong terms:

- linked issue or work-item identifiers
- changed public type, RPC, metric, configuration, or feature names
- component and service names
- distinctive error, state-transition, or behavior terms

Read the candidate PR's diff or changed-file list before calling it related.
Classify reported results:

- **Precedent** - established a pattern or compatibility approach this PR should follow.
- **Overlap** - changes the same behavior or ownership surface.
- **Conflict** - makes incompatible assumptions or is likely to collide.
- **Duplicate** - implements materially the same outcome.

Do not report title-only matches or long lists of weak search results.

For source-level reuse searches, inspect an initialized local submodule when
available. Otherwise use GitHub code search against the resolved repository. Do
not initialize or fetch a submodule only to complete a review; state the limitation
if neither local nor remote code search is available.

## Evidence quality

A review finding needs all of:

- a specific changed or affected location
- a reachable triggering condition
- an observable incorrect or unsafe result
- evidence from code, contract, test, trace, documentation, or linked requirement

If one is missing, investigate further or move the point to advisory/unknown.
Historical code is not automatically correct, and a prior PR is not proof that a
pattern should be copied.
