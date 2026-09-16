# Standalone watch

Use the existing helper only for an independently requested ongoing watch with no
other observation owner. For caller-managed diagnosis, return one pass to the
native workflow instead of launching this helper.

## Prerequisites and invocation

The helper uses PyGithub and the Azure DevOps SDK, with `uv` and Python 3.10+.
It requires `GH_TOKEN` or `GITHUB_TOKEN` and a usable Azure CLI credential;
use `azure-auth` before Azure operations. Missing prerequisites stop standalone
monitoring, not trigger a CLI fallback or a second watcher.

Resolve the script from the personal skill directory:

```bash
PR_CI_MONITOR="$HOME/.copilot/skills/pr-ci-monitor/pr_ci_monitor_cli.py"
uv run --script "$PR_CI_MONITOR" watch \
  --pr-number <pr> --build-id <build> --head-sha <head> \
  --base-ref <base-ref> --base-sha <base-sha> \
  --merge-sha <merge> [--deadline <ISO8601>]
```

The default cadence is two minutes, with a one-minute minimum override; the default
deadline is two hours from start unless the user provides one. Use `--once` for one
SDK observation without an ongoing watch. Other options are documented by `watch --help`.

## Ownership and outcomes

Run an ongoing watch as an attached background process and confirm its first JSON
observation. Record its handle and deadline; do not install a daemon. The helper
observes one already-associated `microsoft/meru-core` `core-ci` build and stops on
completion, deadline, cancellation, association errors, or head/base/merge drift.

Build discovery, diagnosis, comments, retry decisions, and durable state remain
with the skill. Feed failures into the shared diagnosis policy; a helper result
does not itself authorize a retry. After an authorized retry, bind the replacement
build and keep the same consent and consumed budget.

Stop only this workflow's helper. Transfer the journal and stop the helper before
handing observation to another owner.
