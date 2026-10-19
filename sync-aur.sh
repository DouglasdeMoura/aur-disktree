#!/usr/bin/env bash
# Keep the AUR packages disktree and disktree-bin in sync with
# https://github.com/tobi/disktree releases.
#
# Reads the latest upstream release; if it is newer than pkgver in either
# PKGBUILD, bumps the version, refreshes the checksums, regenerates .SRCINFO,
# test-builds each package locally, pushes to the AUR, and commits the bump
# to this repo. Safe to run repeatedly: a no-op when nothing is stale.
#
#   ./sync-aur.sh            # sync
#   ./sync-aur.sh --dry-run  # report what would change, touch nothing
set -euo pipefail

UPSTREAM=tobi/disktree
PACKAGES=(disktree disktree-bin)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${AUR_SSH_KEY_FILE:-$HOME/.ssh/aur_disktree_ed25519}"
GIT_ID=(-c user.name="Douglas de Moura" -c user.email="douglasdemoura@users.noreply.github.com")
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes"
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

[[ -r "$KEY" ]] || die "deploy key $KEY not found"

tag="$(curl -fsSL "https://api.github.com/repos/$UPSTREAM/releases/latest" \
  | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
[[ -n "$tag" ]] || die "could not read latest release tag"
version="${tag#v}"

stale=()
for pkg in "${PACKAGES[@]}"; do
  cur="$(sed -n 's/^pkgver=\(.*\)$/\1/p' "$REPO/pkgs/$pkg/PKGBUILD")"
  if [[ "$cur" != "$version" ]]; then
    stale+=("$pkg")
    log "$pkg is stale: $cur -> $version"
  fi
done
if ((${#stale[@]} == 0)); then
  log "up to date: $version"
  exit 0
fi
if ((DRY_RUN)); then
  log "dry run: would update ${stale[*]} to $version"
  exit 0
fi

# Bump version and refresh checksums.
for pkg in "${stale[@]}"; do
  sed -i "s/^pkgver=.*/pkgver=$version/; s/^pkgrel=.*/pkgrel=1/" "$REPO/pkgs/$pkg/PKGBUILD"
done
if [[ " ${stale[*]} " == *" disktree "* ]]; then
  srchash="$(curl -fsSL "https://codeload.github.com/$UPSTREAM/tar.gz/refs/tags/v$version" | sha256sum | cut -d' ' -f1)"
  sed -i "s/^sha256sums=.*/sha256sums=('$srchash')/" "$REPO/pkgs/disktree/PKGBUILD"
fi
if [[ " ${stale[*]} " == *" disktree-bin "* ]]; then
  base="https://github.com/$UPSTREAM/releases/download/v$version"
  x86="$(curl -fsSL "$base/disktree-$version-x86_64-linux.tar.gz.sha256" | cut -d' ' -f1)"
  a64="$(curl -fsSL "$base/disktree-$version-aarch64-linux.tar.gz.sha256" | cut -d' ' -f1)"
  [[ -n "$x86" && -n "$a64" ]] || die "release assets for v$version missing"
  sed -i "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('$x86')/" "$REPO/pkgs/disktree-bin/PKGBUILD"
  sed -i "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('$a64')/" "$REPO/pkgs/disktree-bin/PKGBUILD"
fi

# Regenerate metadata and prove each package still builds before publishing.
for pkg in "${stale[@]}"; do
  (
    cd "$REPO/pkgs/$pkg"
    makepkg --printsrcinfo > .SRCINFO
    log "$pkg: test build"
    rm -rf src pkg
    makepkg -f --noconfirm > "build-$version.log" 2>&1 \
      || die "$pkg: build failed, see $REPO/pkgs/$pkg/build-$version.log"
    rm -rf src pkg
  )
done

# Publish to the AUR.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for pkg in "${stale[@]}"; do
  git clone -q --depth 1 "ssh://aur@aur.archlinux.org/$pkg.git" "$work/$pkg"
  cp "$REPO/pkgs/$pkg/PKGBUILD" "$REPO/pkgs/$pkg/.SRCINFO" "$work/$pkg/"
  (
    cd "$work/$pkg"
    if git diff --quiet; then
      log "$pkg: AUR already at $version"
    else
      git add PKGBUILD .SRCINFO
      git "${GIT_ID[@]}" commit -q -m "upgpkg: $pkg $version-1"
      git push -q
      log "$pkg: pushed $version-1 to AUR"
    fi
  )
  ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes aur@aur.archlinux.org unflag "$pkg" >/dev/null 2>&1 || true
done

# Record the bump in this repo.
(
  cd "$REPO"
  git add pkgs/*/PKGBUILD pkgs/*/.SRCINFO
  git "${GIT_ID[@]}" commit -q -m "upgpkg: ${stale[*]} $version-1"
  git push -q origin HEAD || log "WARNING: could not push to origin (commit is local)"
)
log "done: ${stale[*]} -> $version"
