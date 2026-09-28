# Dotfiles

Collection of scripts to set up across repositories. Taken from: https://www.bowmanjd.com/dotfiles/dotfiles-1-simple-no-bare-repo/

## Installation

Clone the repository anywhere and run:

```bash
./install.sh
```

GitHub Codespaces runs `install.sh` automatically when this repository is
configured as the dotfiles repository. The installer links tracked top-level
dotfiles into `$HOME`. For tracked files under directories such as `.config`,
`.copilot`, and `.gnupg`, it creates the required directory structure and links
each file individually. As with Codespaces' default dotfile linking, conflicting
top-level files are replaced. Existing directories and unrelated nested files
are preserved; conflicting managed paths inside those directories produce a
warning and are left unchanged.

The installer is safe to run repeatedly. If this repository is already checked
out directly in `$HOME`, files already in place are simply skipped.

## In-place checkout

The repository can alternatively be checked out directly in the home directory.

The following commands will clone into the home directory so these files can be at the proper location. There is some minimal git setup so that your other files don't get mixed up with these, because your git repo will be in your home directory.

Checkout the repo in your home directory

```
cd $HOME
git clone -n --separate-git-dir .git git@github.com:thkawcha/dotfiles.git throwaway
rm -r throwaway
```

Set files to be tracked only if explicitly added

```
git config --local status.showUntrackedFiles no

```

Then, checkout the files from the repo

```
git checkout
```

OR, maybe this if you are okay overwriting local files

```
git checkout -f
```

## Git Configuration and Codespaces

Git configuration is stored in `.config/git/config` (the XDG location) instead of `~/.gitconfig`. This avoids overwriting environment-specific settings in codespaces and other managed environments.

Git reads both files with `~/.gitconfig` taking higher priority, so:
- Your personal defaults (diff, rebase, fetch, etc.) are always available from `.config/git/config`
- Environment-specific settings in `~/.gitconfig` (e.g. credential helpers) take precedence when present
