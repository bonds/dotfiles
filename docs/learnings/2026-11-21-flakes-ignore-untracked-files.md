# A git-backed flake ignores files git does not know about

**Symptom.** Building the accismus system from the edit checkout right after
adding a new module failed, even though the file was right there:

```
$ cd ~/.local/share/dotfiles/worktree/.config/nix
$ nix build .#darwinConfigurations.accismus.system
error: getting status of '/nix/store/fx2jjl1ki0ywkczkwk6gx5j2pgy06rmx-source/.config/nix/modules/home/omp.nix':
       No such file or directory
```

The path in the error is the **store copy** of the flake (`-source`), not the
worktree, and `ls` confirmed the file existed in the worktree.

**Cause.** A flake in a git repository is evaluated from a copy of the tree that
nix makes from `git ls-files` — tracked **and staged** files only. A brand-new
file that has never been `git add`ed is not in that copy, so the flake
references a path that does not exist in its own source. `git status` hides
this: the repo sets `status.showUntrackedFiles=no`, so the new file is invisible
and the tree looks clean.

**Fix.** `git add` the new files before the first build — staging is enough, no
commit required:

```bash
cd ~/.local/share/dotfiles/worktree
git add .config/nix/modules/home/omp.nix .config/nix/pkgs/omp/
git status --porcelain --untracked-files=normal   # confirm they are staged
cd .config/nix && nix build .#darwinConfigurations.accismus.system
```

Related: a `nix build .` from a *dirty* tree still works — the store copy just
carries the modified files — which is why this only bites on new files. And
`nr` is unaffected: it applies `main` to `$HOME` and builds the committed tree.
