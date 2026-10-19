# aur-disktree

Keeps the AUR packages [`disktree`](https://aur.archlinux.org/packages/disktree)
and [`disktree-bin`](https://aur.archlinux.org/packages/disktree-bin) in sync
with [tobi/disktree](https://github.com/tobi/disktree) releases.

- **disktree** — builds from the upstream source tarball (`cargo`, `--locked`).
- **disktree-bin** — packages the official prebuilt Linux binaries
  (x86_64 + aarch64) from each GitHub release.

`sync-aur.sh` keeps them current. It reads the latest upstream release and,
when it is newer than the `pkgver` in the PKGBUILDs, bumps the version,
refreshes the SHA-256 checksums (reusing the `.sha256` assets upstream
publishes), regenerates `.SRCINFO`, test-builds each changed package, pushes
both package repos on the AUR (`upgpkg: <pkg> <ver>-1`), clears the
out-of-date flag, and commits the bump to this repo. It is a no-op when
nothing is stale, and `--dry-run` only reports.

It runs hourly from a **user-level systemd timer on the maintainer's
machine** (`systemd/aur-disktree-sync.{service,timer}`), using the deploy
key at `~/.ssh/aur_disktree_ed25519`. Missed runs are caught up at the next
boot (`Persistent=true`).

> **Why not GitHub Actions?** It was tried first (Sept–Oct 2026). The AUR
> accepts this deploy key from a home connection but answers
> `Permission denied (publickey)` to the identical key offered from
> GitHub-hosted runners (Microsoft/Azure address space, AS8075), so an AUR
> push can never succeed from there.

## One-time setup

1. **AUR account** — register at <https://aur.archlinux.org/register> and add
   the public half of the deploy key (`~/.ssh/aur_disktree_ed25519.pub`) under
   *My Account → SSH Public Key*.
2. **Install the timer** on the machine that holds the key:

   ```
   cp systemd/aur-disktree-sync.* ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now aur-disktree-sync.timer
   ```

3. **Check it**:

   ```
   ./sync-aur.sh --dry-run                       # what would change
   systemctl --user list-timers aur-disktree-sync.timer
   journalctl --user -u aur-disktree-sync.service -n 20
   ```

## Layout

```
pkgs/disktree/PKGBUILD       source package
pkgs/disktree-bin/PKGBUILD   prebuilt-binary package
sync-aur.sh                  release watcher + AUR pusher
systemd/                     hourly user timer that runs it
```

## Local testing

```
cd pkgs/disktree      && makepkg -sf --noconfirm   # full source build (~10 min)
cd pkgs/disktree-bin  && makepkg -sf --noconfirm   # packages the release binary
makepkg --printsrcinfo > .SRCINFO                  # regenerate metadata
```

