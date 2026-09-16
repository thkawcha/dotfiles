---
name: pr-ci-monitor
description: >-
  Monitor and diagnose microsoft/meru-core PR CI for a native workflow or as an
  independent personal watch.
  Distinguish known flakes from regressions and assess retry eligibility.
  Read-only by default; explicit opt-in allows rationale comments and at most
  two automatic core-ci retries per PR head through the repository's pr-actions
  skill.
---

# PR CI Monitor

Load the current checkout's repository-owned `pr-actions` skill for PR identity,
permissions, shared safeguards, check discovery, and every PR write or CI trigger.
If it is unavailable, monitoring and diagnosis must remain read-only. Use existing
service skills, not a new API client or daemon.

## Consent and scope

| Request | Allowed effects |
| --- | --- |
| Check/watch/investigate CI | Read evidence and report in the session. |
| Post the diagnosis | Publish that diagnosis; no rerun. |
| Monitor and retry known flakes | Post rationale and perform eligible automatic retries for the resolved head. |
| Run core-ci again | One explicit trigger through `pr-actions`, not ongoing retry consent. |

The automatic limit is **two retries per PR head**, or the user's smaller limit.
Initial/manual runs are not automatic retries. Resumption, mode changes, another
agent, a different failure, or base movement never resets the budget. A new head or
retargeted PR requires fresh consent; base/merge changes require reassociation and consent review.
Automatic retries support **core-ci only**; other pipelines may be observed, not substituted.

## Execution modes

Choose one observation owner before starting work:

| Mode | When to use it | Responsibility |
| --- | --- | --- |
| **Caller-managed** | A native PR workflow, session automation, or another monitor already owns the loop. | Consume its context, perform one observation/diagnosis pass, and return. Do not sleep, schedule another pass, or start the SDK watcher. |
| **Standalone** | The user requests an independent ongoing watch and no other monitor owns it. | Run the existing bounded SDK helper, then apply the same diagnosis and retry policy. |

A one-time check or investigation is one pass, not permission to start monitoring.
Ask if ownership is ambiguous. Switching modes requires an explicit handoff of
identity, deadline, consent, and retry state; never run competing watchers.
Native automatic repair or merge features are not read-only observers, and must
not be enabled merely to implement a watch.

In caller-managed mode, return retry eligibility by default. Execute a retry only
if the caller explicitly delegates it with recorded user consent and a shared
journal, making this skill the sole retry owner for that attempt. Otherwise the
caller owns subsequent actions under the same policy.

## Existing tools

- Use `azure-auth` before Azure calls and `azure-devops` for build metadata,
  timelines, logs, and artifacts, honoring their organization/project configuration.
- Use `identify-build-commits` for tested source/submodule revisions and baselines.
- Use `pr_ci_monitor_cli.py watch` only for a [standalone watch](references/standalone-watch.md).
  Caller-managed diagnosis does not require its SDK credentials just to consume
  supplied context. Authenticate only for APIs actually needed to fill evidence gaps.
- For integration/E2E failures, use `classify-e2e-infra-issue` and
  `investigate-pipeline-failure`; do not apply E2E heuristics to every core-ci failure.
- Local reproduction needs separate authorization: use `debug-unit-test` or
  `debug-fabrictest-script` as appropriate and follow repository test restrictions.

Monitoring does not authorize fixes, commits, pushes, issue writes, or
cancellations. If a separately authorized fix workflow creates a commit, preserve
the personal GPG-signing requirement: when the sandbox blocks signing, retry the
signed command through the outside-sandbox approval prompt; never use an unsigned
commit. Avoid helpers with hidden writes: `scripts/check_pipelines.py investigate`
can create issues.

## Bind and observe

1. Resolve PR/head/base and the requested pipeline (default: `core-ci` for meru-core
   PR CI). Start with caller-supplied context when available, but refresh PR state
   and validate organization/project, pipeline, repository, PR, and tested revision.
   Prefer the check/status build URL. Otherwise search a bounded time window for
   that pipeline/ref, not the latest build globally. Use `az pipelines build show`
   via `azure-devops` when normalized metadata omits repository/PR details.
2. Establish actual checkout and submodule SHAs, including generated merge commits,
   with `identify-build-commits`. Record intended head and tested revision separately;
   ambiguous association or inaccessible evidence disables automatic retries.
3. In caller-managed mode, perform one pass using available evidence and targeted
   reads, then return control to the caller. Keep its recorded deadline; missing
   consent or an unbounded retry scope prevents automatic retries.
   In standalone mode, follow the linked helper procedure and confirm its first
   observation. Do not replace missing prerequisites with an improvised watcher.
4. Persist outside the repository: mode, observation/retry owners, PR/pipeline/head/base/merge,
   consent and failure classes, deadline, initial/current builds, retry limit/count,
   evidence, comment IDs/times, trigger delivery, replacement builds, and watch handle/state.
   The caller and skill must share one retry journal, including across new sessions;
   a new session's empty store is not a fresh budget. Reconcile with comments/checks
   on resumption or handoff. If ownership, budget, or delivery is uncertain, stay
   read-only; comment markers do not establish consent.
5. Re-read PR state/revision on every observation and before writes:

| Result | Action |
| --- | --- |
| Queued/running | Return running to the caller, or continue the standalone watch until its deadline. |
| Succeeded | Report this pipeline/revision's success and stop; do not claim overall PR readiness. |
| Failed/partially succeeded | Diagnose all independent failures. |
| Missing/skipped/neutral/action-required | Report CI unconfirmed or awaiting action; do not auto-start it. |
| Canceled, closed/merged, changed head/base/merge, deadline expired, or consent revoked | Stop mutations, preserve state, and return the stop reason to the caller. Stop only an owned standalone watcher. |
| Access failure or uncertain association | Report the limitation; no automatic retry. |

## Diagnose failures

1. Inspect the full timeline and every failed job's causal task. Capture test/error,
   phase, build flavor, and relevant logs/artifacts; distinguish independent causes
   from cleanup noise and retrieve earlier context when a log tail is insufficient.
2. Search `microsoft/meru-core` issues by distinctive failure signature; use
   `microsoft/meru-release` for infrastructure tracking under on-call conventions.
   Read issue bodies, comments, status, and fix history; match phase/configuration,
   not just a test name or label. Inaccessible evidence is not a negative result.
3. Compare actual built source/submodules and relevant PR changes with a suitable
   baseline of the same configuration. Report gaps and PR-causality evidence;
   historical recurrence or a passing retry does not prove the PR is unrelated.
4. Classify each independent cause:

| Classification | Automatic retry eligibility |
| --- | --- |
| Known flake | High-confidence match to an open issue documenting intermittent behavior, with no unresolved evidence implicating the PR. |
| Known infrastructure failure | Concrete evidence, an open issue documenting a transient failure, and explicit consent covering it. |
| Likely PR regression | None; explain relevant changes and evidence. |
| New/inconclusive failure or closed/fixed issue match | None; explain uncertainty and request user review. |

## Retry comments

Every rerun governed by this policy, in either mode and including a directly
authorized one-off rerun, uses **two separate top-level comments**:

1. Post and capture a PR-monitor rationale with the failed build/head, failing
   job/test/flavor, classification and confidence, concise evidence, issue links,
   retry accounting, and replacement status.
2. Hand off to `pr-actions`, which posts a second comment whose entire body is
   exactly `/azp run core-ci`.

Never decorate the trigger comment: extra text or a hidden marker can prevent the
AzP bot from recognizing it. The rationale must explicitly say that the separate
trigger was posted by the PR CI monitor, then link both the trigger comment and
confirmed replacement build. Use the canonical body and update rules in
[references/retry-comments.md](references/retry-comments.md).

## Authorized known-flake retry

1. The designated retry owner rechecks consent, deadline, issue status, revision, and budget.
   **All independent failures must qualify.** Reuse a matching queued/running build
   instead of duplicating it. Reassess eligibility for every retry.
2. Reserve and consume the retry ordinal in durable state before triggering.
   Uncertain delivery still consumes that attempt; reconcile rather than repeat it.
3. Post the separate rationale defined above. Deduplicate by its hidden
   PR/head/failed-build/attempt marker and capture its comment ID. If publication
   is uncertain, reconcile and stop until confirmed.
4. Hand consent, head, failed build, evidence, ordinal, and budget to `pr-actions`
   **Run core-ci**. Include the rationale comment ID in the handoff. Record the
   separate trigger outcome and confirmed replacement build.
5. Update only the captured, agent-authored rationale comment by ID, preserving
   concurrent edits; never use `--edit-last`. Add the exact trigger-comment and
   replacement-build links. Report update failures. If the head changed, mark the
   rationale superseded and do not trigger for the new revision.
6. Carry the same budget to the replacement build. In caller-managed mode, return
   its association and journal to the caller without starting another loop; in
   standalone mode, continue the owned watch. At the retry limit, report and stop.
   Further runs need individual user requests, not a renewed automatic budget.
   Never cancel another session's automation or a CI build.

Return the mode/owner, PR/head, actual tested revision, build links, failing job/test,
classification/confidence, issue/evidence, retry eligibility and budget, and any stop
reason or next action. A caller-managed pass returns control; do not claim this
skill started a watcher in that mode.
Publish only with authorization. Issue writes need separate consent; use host tools
and repository templates, search for duplicates, and add only actionable information.

For flaky unit-test issues, use **Unit Test Failure** in `microsoft/meru-core`
(`.github/ISSUE_TEMPLATE/unit-test-failure.yml`).
