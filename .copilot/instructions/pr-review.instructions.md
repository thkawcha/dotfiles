---
applyTo: "**"
description: >-
  Personal standards that apply only when reviewing a pull request or diff.
---

# Pull Request Review Standards

Apply these instructions only when the task is to review a pull request, branch,
commit, staged change, or diff. Do not turn them into implementation requirements
for unrelated coding tasks.

## Review boundary and evidence

- Keep reviews read-only. Draft findings in the session and publish comments,
  submit a review, or resolve threads only when explicitly requested.
- Bind the review to the exact repository, base, head, and PR revision. Do not mix
  unrelated working-tree changes into a remote PR review.
- Report only actionable, high-confidence correctness, reliability, security, or
  compatibility problems as findings. Cite the changed or affected code, explain
  the triggering scenario and impact, and do not present a hypothesis as fact.
- Put organization, reuse, documentation, test, and scope improvements that are
  not defects in a separate **Advisory improvements** section. Do not post these
  as inline findings by default.
- Read existing review threads and avoid duplicating feedback. State when evidence
  is inaccessible or the review is incomplete.

## Intent and related context

- Check that the PR has substantive **What**, **Why**, and **How** sections and
  that the diff matches them.
- Follow linked GitHub issues or Azure DevOps work items and map their requirements
  and acceptance criteria to implementation and tests. A missing, inaccessible, or
  underspecified link is a traceability warning, not automatically a code defect.
- Search for relevant open PRs and PRs active in the previous 90 days in the
  current repository and repositories declared as top-level submodules in
  `.gitmodules`. Report only concrete overlap, precedent, conflict, or duplication.

For a full review, use the personal `pr-review` skill. Its checklist covers code
organization and reuse, unit/integration/E2E tests, breaking APIs, documentation,
store and failover consistency, LNM/async safety, tracing and metrics,
configuration, and cognitive scope based on independent concerns rather than
changed-line count.
