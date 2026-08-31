# Personal Copilot Instructions

## Preferences

- Always use scripts to build and test when they are available (ex: build.sh and test.sh). Do not roll your own commands to use.
- Use skills wherever available instead of attempting to carry out actions on your own. (Ex: Do not attempt to download or parse traces on your own.)
- Provide hard evidence from traces when investigating issues. Do not present
  hypotheses as facts without evidence.
- For each conclusion, link code locations, traces from the logs, and runtime symptoms.

## Build Preflight

- Before running any build command or build task in a Meru repository, check whether a local Meru cluster is running. Check `meru_machine_init.service` and fall back to looking for processes under `/opt/microsoft/meru` so a missing or stale service registration does not hide a running cluster.
- If a cluster is running, stop before starting the build and prompt me to choose whether to clean up the cluster or leave it running during the build. Do not infer a choice and do not clean up the cluster automatically.
- If I choose cleanup, use the `deploy-meru-cluster` skill and verify the cluster has stopped before building. If I choose to leave it running, continue the build without modifying the cluster.
- Apply this preflight to all build variants, including normal, clean, package, tidy, ASAN, IWYU, component-specific, CMake, C++, and Rust builds.

## Environments

I develop on a few different configurations: (Linux Dev Machines, Codespaces, and WSL). Each of these will have slightly different configurations and supported capabilities.

### Linux Dev Machines

These support all development and testing, including access to remote build caches.

### Codespaces

These are running inside the build container for our project. They support most dev lifecycle activities, with the exception of some tests. Some unit tests like the space scheduler depend on access to the cgroup filesystem which is mounted as read-only in codespaces, for an example. Codespaces also do not support deploying a meru cluster and thus do not support running end to end tests.

These do not have access to the remote build cache, but they do cache builds locally and get up to 32 cores.

### WSL

These are the most constrained development environments. They do have access to the build cache, but do not have many cores and are somewhat limited in capabilities. They cannot deploy clusters and run end to end tests.

When in WSL, do not attempt to start docker. Prompt the user to start it instead.

Meru clusters cannot run in WSL so you do not need to check for existence before running builds and other commands. You also will not be able to deploy clusters there right now.

## Commit Signing

Commits are signed with GPG keys as per my git configuration. Depending on the environment, I have a GPG passphrase that needs to be entered by me. If you attempt to sign a commit and it is waiting for a gpg passphrase, please tell the user to run the commit commands in a new window. This will refresh the gpg ttl and you will be able to commit after that. DO NOT attempt to bypass commit signing. DO stop what you are doing and tell the user to sign the commit.

**DO NOT** ammend and automatically push commits when making changes that are part of a PR. Changes should always be pushed as part of a new commit when there is a remote branch. The exception is if I tell you to rebase a branch on main or similar.

If commit signing is disabled or unavailable inside a sandbox, stop before creating or pushing a commit. Prompt me to sign the commit or retry the command outside the sandbox so I can approve signing. Never create or push an unsigned commit.

## Azure Authentication

Never use `az login --use-device-code`. It is not supported for my account. Outside Codespaces, use plain `az login`, which will pop up a browser window to sign in.

### Codespaces

Azure CLI detects `CODESPACES=true` and forces device code flow even when the VS Code browser bridge is available. Run `CODESPACES=false az login` to force browser authorization. This override must apply only to the login command; do not unset `CODESPACES` globally.

## Repository Workspaces

- Do not clone a workspace into a new directory without asking, unless specifically instructed by the user. Instead, prefer working in the meru-\* directories that are under the home folder. This is so that any changes play nicely with the incremental build in the existing repositories.
- If there is unrelated work in the repository that you are instructed to work in, please ask the user what they would like to do with the existing work. Do not clean it up automatically.

## Meru Submodules

- Treat each repository's `.gitmodules` as the source of truth for its top-level
  dependencies.
- Never initialize Meru submodules recursively. Recursive checkout creates
  redundant nested Meru worktrees and pulls unnecessary dependency trees.
- Initialize top-level submodules from the repository root with
  `git submodule update --init`.
- The only supported nested checkout is the networking dependency set:
  `git -C ext/net/deps submodule update --init`.
- Alternatively, after `ext/build-infra` is available, run
  `bash ext/build-infra/devcontainer-features/meru-devcontainer-ubuntu/scripts/checkout-submodules.sh`.
  It initializes the top level and only `ext/net/deps`.

