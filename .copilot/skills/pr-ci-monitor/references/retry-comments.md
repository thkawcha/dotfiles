# PR CI Monitor Rerun Comments

The Azure Pipelines bot requires the trigger comment body to be exactly:

```text
/azp run core-ci
```

Never add attribution, evidence, or a hidden marker to that comment. Every
rerun governed by the personal `pr-ci-monitor` policy, whether caller-managed
or standalone, instead uses two separate top-level comments:

1. A PR-monitor rationale comment.
2. The exact `/azp run core-ci` trigger comment posted through `pr-actions`.

Post the rationale first and capture its ID. Use this shape:

```markdown
<!-- pr-ci-monitor core-ci-rerun pr=<pr> head=<head> failed-build=<id> attempt=<kind-or-ordinal> -->
**PR CI monitor: core-ci rerun**

- **Failed build:** [<id>](<build-url>) on head `<short-head>` (tested merge `<short-merge>`)
- **Failure:** `<job / test / flavor>` - <short redacted symptom>
- **Assessment:** <classification> (<confidence> confidence)
- **Evidence:** <why it is intermittent and why the PR is not implicated>
- **Tracking:** [<issue>](<issue-url>)
- **Retry:** <ordinal>/<limit>; replacement build pending
- **Trigger:** The PR CI monitor will post a separate exact-body `/azp run core-ci` comment.
```

For a directly user-authorized one-off rerun that has no matching open issue,
replace **Tracking** and **Retry** with:

```markdown
- **Tracking:** No matching open issue found.
- **Retry:** User-authorized one-off; automatic retry budget unchanged.
```

After posting the exact trigger, update only the captured rationale comment by
ID. Preserve its marker and evidence, and replace the final fields with links:

```markdown
- **Trigger:** [`/azp run core-ci`](<trigger-comment-url>) - posted separately by the PR CI monitor because the command must be the entire comment body.
- **Replacement build:** [<id>](<build-url>) - <queued|running|completed>
```

For an automatic retry, every independent failure still needs its own matching
open issue. Include all issue links and concise evidence in the one rationale
comment; do not post one rationale per failed job.
