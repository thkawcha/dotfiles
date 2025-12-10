# Dotfiles

Collection of scripts to set up across repositories. Taken from: https://www.bowmanjd.com/dotfiles/dotfiles-1-simple-no-bare-repo/

## How to clone to Home Directory

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

