# aur-disktree

Keeps the AUR packages [`disktree`](https://aur.archlinux.org/packages/disktree)
and [`disktree-bin`](https://aur.archlinux.org/packages/disktree-bin) in sync
with [tobi/disktree](https://github.com/tobi/disktree) releases.

- **disktree** — builds from the upstream source tarball (`cargo`, `--locked`).
- **disktree-bin** — packages the official prebuilt Linux binaries
  (x86_64 + aarch64) from each GitHub release.

A scheduled GitHub Actions workflow (`.github/workflows/sync-aur.yml`) runs
hourly: it reads the latest upstream release, and when it is newer than the
`pkgver` in the PKGBUILDs it bumps the version, refreshes the SHA-256
checksums (reusing the `.sha256` assets upstream publishes), regenerates
`.SRCINFO`, and pushes both package repos on the AUR (`upgpkg: <pkg> <ver>-1`).
It can also be run manually from the Actions tab ("Sync AUR" → "Run
workflow").

A second workflow (`keepalive.yml`) pushes an empty commit once a month,
because GitHub disables scheduled workflows after 60 days of repository
inactivity.

## One-time setup

1. **AUR account** — register at <https://aur.archlinux.org/register>.
2. **Add the deploy key** — in your AUR profile, add this SSH public key
   (generated locally at `~/.ssh/aur_disktree_ed25519`):

   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ23ZlPG/In5e9MzNDONvmNYvzz74PjYFV3yycBsUmVR aur-disktree-automation (2026-09-25)
   ```

3. **Create the packages (first push only)** — push to a package URL that
   does not exist yet and the AUR creates it automatically. With the key on
   your agent, or run once from CI:

   ```
   git clone ssh://aur@aur.archlinux.org/disktree.git && cp pkgs/disktree/PKGBUILD pkgs/disktree/.SRCINFO disktree/ && (cd disktree && git add -A && git commit -m "upgpkg: disktree 0.10.0-1" && git push)
   git clone ssh://aur@aur.archlinux.org/disktree-bin.git && cp pkgs/disktree-bin/PKGBUILD pkgs/disktree-bin/.SRCINFO disktree-bin/ && (cd disktree-bin && git add -A && git commit -m "upgpkg: disktree-bin 0.10.0-1" && git push)
   ```

4. **GitHub secret** — in this repo: Settings → Secrets and variables →
   Actions → New repository secret:

   - Name: `AUR_SSH_KEY`
   - Value: contents of `~/.ssh/aur_disktree_ed25519` (the **private** key)

5. **Push this repo to GitHub** (public is fine — no secrets are stored in
   it), then trigger **Sync AUR** once manually to verify the whole path.

From then on everything is automatic: upstream release → hourly check →
both AUR packages updated within the hour.

## Layout

```
pkgs/disktree/PKGBUILD       source package
pkgs/disktree-bin/PKGBUILD   prebuilt-binary package
.github/workflows/sync-aur.yml   hourly release watcher + AUR pusher
.github/workflows/keepalive.yml  monthly empty commit to keep cron alive
```

## Local testing

```
cd pkgs/disktree      && makepkg -sf --noconfirm   # full source build (~10 min)
cd pkgs/disktree-bin  && makepkg -sf --noconfirm   # packages the release binary
makepkg --printsrcinfo > .SRCINFO                  # regenerate metadata
```

