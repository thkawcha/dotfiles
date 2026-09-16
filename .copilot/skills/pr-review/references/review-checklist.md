# PR Review Checklist

Use applicable sections for every full review. Do not emit a comment for each
question; report only supported findings, advisories, and coverage gaps.

## 1. Intent and completeness

- Does the implementation match the stated What/Why/How and linked acceptance criteria?
- Are non-goals, rollout assumptions, and operational constraints respected?
- Are all user-visible and failure-path behaviors represented, or is the PR only a
  partial implementation presented as complete?

## 2. Correctness and failure behavior

- Trace success, validation, boundary, cancellation, timeout, retry, partial-open,
  partial-close, and rollback paths.
- Check ownership, lifetime, null/empty/invalid input, version and generation
  comparisons, stale callbacks, and concurrent state transitions.
- Distinguish the first causal failure from cleanup fallout.
- Ensure failures remain visible through returned errors, completion signals,
  tracing, and metrics rather than becoming success-shaped fallbacks.

## 3. Organization and reuse

- Does each type or function have one coherent responsibility and an appropriate
  owner/layer?
- Can complex conditionals, state machines, or orchestration be named and isolated
  without obscuring ordering or error handling?
- Search the current repository and every top-level submodule for the same concept,
  symbol, conversion, retry policy, validation, client wrapper, or state machine.
- Cite an existing API when recommending reuse. Do not make a generic "deduplicate"
  suggestion without showing the duplicate.
- Prefer `meru-common` for genuinely shared higher-level contracts and `meru-base`
  for low-level primitives only when there are concrete consumers and no circular
  or upward dependency. Avoid moving feature-specific policy into a shared layer.

## 4. API and compatibility

Inspect changes to:

- protobuf messages, enums, services, RPCs, field numbers, defaults, and generated clients
- public headers, exported symbols, constructors, interfaces, callbacks, and error semantics
- configuration keys, defaults, environment variables, command-line arguments, and file layouts
- persisted entities, stream/event formats, tags, identifiers, and serialization
- package contents, service names, endpoints, metrics, trace schemas, and dashboard labels

Identify current and submodule consumers. Check source and wire compatibility,
mixed-version behavior, rolling upgrade, downgrade/rollback, migration ordering,
default behavior for old data/configuration, and removal timing for compatibility
shims. Label breaking or behavior-changing contracts prominently.

## 5. Tests and E2E coverage

- Unit/component tests cover success, validation, boundaries, every changed failure
  branch, cancellation, retry exhaustion, duplicate requests, and partial lifecycle.
- Persistence/failover tests cover restart, role change, stale or replayed work,
  data loss, reconciliation, and idempotent recovery where applicable.
- Integration tests prove cross-component contracts rather than only mock call counts.
- E2E recommendations name the existing scenario entrypoint, workload/helper,
  topology, injected fault, and observable assertion to add or extend.
- Prefer extending the closest scenario over creating a near-duplicate. Check the
  current repository and test-infra submodule for reusable fixtures and clients.
- Do not claim coverage from a test name alone; verify assertions reach the changed behavior.
- Keep tests deterministic: observable completion instead of sleeps, controlled
  scheduling where available, and cleanup that does not mask the causal failure.

## 6. Store consistency and failover

- Identify the durable source of truth and every cache, projection, stream, or
  in-memory index derived from it.
- Verify transactional/atomic boundaries and write, publish, acknowledge, and
  externally visible ordering.
- Check idempotency for retries and repeated create/update/delete operations.
- Check duplicate, delayed, reordered, stale-generation, and replayed messages.
- Check partial persistence, partial publication, timeout-after-commit, and
  callback-after-role-change outcomes.
- Verify startup, restart, rebuild, data-loss, and primary/leadership-change
  reconciliation, including cleanup of orphaned or superseded state.
- Ensure retry policies are bounded, cancellable, observable, and safe after close.

## 7. LNM and asynchronous safety

- Every `lnm_task` has an intentional owner and lifetime; tasks are awaited, tracked,
  or deliberately detached through an established owner.
- Lifecycle-sensitive work obtains and retains the appropriate
  `async_meru_component::try_enter()` guard until it can no longer touch the component.
- Open/close and partial-open cleanup are ordered, cancellation-aware, and symmetric.
- Coroutine and callback captures cannot outlive referenced objects; stale callbacks
  cannot mutate a new generation or role.
- Errors propagate through the task/result contract, and completion events or
  promises are fulfilled on every terminal path exactly as their contract requires.
- Blocking waits, thread sleeps, lock retention across suspension, and unbounded
  retry loops are absent unless a documented component pattern makes them safe.
- Core/thread affinity, concurrent mutation, cancellation races, and shutdown
  interleavings are handled explicitly where relevant.

## 8. Tracing, metrics, and operability

- Important operations expose begin, success, failure, cancellation, retry, and
  state-transition evidence with useful identifiers and error details.
- Operator-actionable failures and state changes use the component's operational
  trace convention; routine high-volume paths avoid noisy operational events.
- Metrics cover new rates, failures, latency, backlog, capacity, or recovery state
  when traces alone cannot answer health or trend questions.
- New or renamed metrics preserve labels and dashboard/alert queries, or update the
  corresponding dashboards and documentation.
- Logs and traces avoid secrets, credentials, unbounded payloads, and misleading
  success messages.

## 9. Configuration and packaging

- Search service configs, one-node variants, environment maps, parameter files,
  schemas, templates, deployment manifests, package lists, CMake install rules,
  test configs, pipeline variables, and scenario overrides for required updates.
- Defaults preserve existing behavior unless the PR explicitly changes it.
- Producers, consumers, examples, validation, and documentation use the same key,
  type, units, precedence, and naming.
- Configuration changes have a rollout and rollback story and fail with actionable
  errors rather than silently using an unsafe fallback.

## 10. Documentation and comments

- Public or user-visible behavior, API/configuration contracts, operational
  procedures, test instructions, and known limitations are updated.
- Comments explain non-obvious invariants, ordering, lifetime, compatibility, and
  why a design is safe; they do not merely paraphrase code.
- Documentation examples and commands match the implementation and current file paths.
- Removed or renamed behavior is removed or clearly deprecated everywhere it appears.

## 11. Cognitive scope and split strategy

Assess independent dimensions rather than changed-line count:

- number of behaviors or user outcomes
- number of components, owners, or repositories
- feature work mixed with refactoring or mechanical migration
- API/schema/configuration migration mixed with implementation
- number of persistence, failover, concurrency, and rollout models
- ability to understand, validate, deploy, and revert each concern independently

Recommend a split when independent concerns obscure causality or prevent focused
validation. Propose a concrete order such as:

1. compatible API or shared primitive
2. behavior behind the existing/default path
3. consumer migration and focused tests
4. rollout/configuration enablement and E2E coverage
5. deprecated-path cleanup after consumers move

Every intermediate PR must remain buildable, testable, deployable, and backward
compatible. Do not suggest a split that creates knowingly broken intermediate states.
