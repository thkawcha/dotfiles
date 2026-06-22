## Personal Copilot Instructions

## Environments

I develop on a few different configurations: (Linux Dev Machines, Codespaces, and WSL). Each of these will have slightly different configurations and supported capabilities.

### Linux Dev Machines

These support all development and testing, including access to remote build caches.

### Codespaces

These are running inside the build container for our project. They support most dev lifecycle activities, with the exception of some tests. Some unit tests like the space scheduler depend on access to the cgroup filesystem which is mounted as read-only in codespaces, for an example. Codespaces also do not support deploying a meru cluster and thus do not support running end to end tests.

These do not have access to the remote build cache, but they do cache builds locally and get up to 32 cores.

### WSL

These are the most constrained development environments. They do have access to the build cache, but do not have many cores and are somewhat limited in capabilities. They cannot deploy clusters and run end to end tests.

## Commit Signing

Commits are signed with GPG keys as per my git configuration. Depending on the environment, I have a GPG passphrase that needs to be entered by me. If you attempt to sign a commit and it is waiting for a gpg passphrase, please tell the user to run the commit commands in a new window. This will refresh the gpg ttl and you will be able to commit after that. DO NOT attempt to bypass commit signing. DO stop what you are doing and tell the user to sign the commit.

**DO NOT** ammend and automatically push commits when making changes that are part of a PR. Changes should always be pushed as part of a new commit when there is a remote branch. The exception is if I tell you to rebase a branch on main or similar.

## Azure Authentication

Never use `az login --use-device-code`. It is not supported for my account. Use the plain `az login` instead, which will pop up a window in my browser to sign in.

### Codespaces

Codespaces will force a device code flow by default even if that `--use-device-code` argument is not specified. You must force the browser to pop open a window for authentication.

## Repository Workspaces

- Do not clone a workspace into a new directory without asking, unless specifically instructed by the user. Instead, prefer working in the meru-\* directories that are under the home folder. This is so that any changes play nicely with the incremental build in the existing repositories.
- If there is unrelated work in the repository that you are instructed to work in, please ask the user what they would like to do with the existing work. Do not clean it up automatically.


