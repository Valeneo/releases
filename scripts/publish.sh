#!/usr/bin/env bash
# Publish a release: GitHub Release (all artifacts) + signed apt index (for .deb files).
# Usage: publish.sh <product> <version> <stable|beta> <file>...
# Binaries live only on GitHub Releases. The apt index lives on the `repo` branch and is
# served by repository.valeneo.space (nginx proxies the index to GitHub, redirects pool/ to releases).
set -euo pipefail
[ $# -ge 4 ] || { sed -n '2,3p' "$0"; exit 1; }
product=$1 version=$2 channel=$3; shift 3
case $channel in stable|beta) ;; *) echo "channel must be stable|beta" >&2; exit 1;; esac

GH=Valeneo/releases
K=$HOME/.config/valeneo-release
C=$HOME/.cache/valeneo-release
tag="$product-v$version"
export GNUPGHOME=$K/gnupg
FPR=$(cat "$K/fingerprint")
gpgsign() { gpg --batch --yes --pinentry-mode loopback --passphrase-file "$K/passphrase" -u "$FPR" "$@"; }

# 1. GitHub release
flags=(); [ "$channel" = beta ] && flags+=(--prerelease)
if gh release view "$tag" --repo "$GH" >/dev/null 2>&1; then
  gh release upload "$tag" "$@" --repo "$GH" --clobber
else
  gh release create "$tag" "$@" --repo "$GH" --title "$product $version" --generate-notes "${flags[@]}"
fi

# 2. apt index (only if there are .debs)
debs=(); for f in "$@"; do [[ $f == *.deb ]] && debs+=("$f"); done
[ ${#debs[@]} -gt 0 ] || exit 0
mkdir -p "$C/pool/$channel/$product/$tag"; cp "${debs[@]}" "$C/pool/$channel/$product/$tag/"

if [ ! -d "$C/repo/.git" ]; then
  git clone -q --branch repo "https://github.com/$GH.git" "$C/repo" 2>/dev/null || {
    git clone -q "https://github.com/$GH.git" "$C/repo"; git -C "$C/repo" checkout -q --orphan repo; git -C "$C/repo" rm -rqf . || true; }
else git -C "$C/repo" pull -q --ff-only || true; fi

build_suite() { # suite channels...
  local suite=$1; shift; local t; t=$(mktemp -d)
  mkdir -p "$t/pool"
  for ch in "$@"; do [ -d "$C/pool/$ch" ] && cp -as "$C/pool/$ch/." "$t/pool/"; done
  for arch in amd64 arm64; do
    mkdir -p "$t/dists/$suite/main/binary-$arch"
    (cd "$t" && apt-ftparchive --arch "$arch" packages pool) > "$t/dists/$suite/main/binary-$arch/Packages"
    gzip -9kn "$t/dists/$suite/main/binary-$arch/Packages"
  done
  (cd "$t/dists/$suite" && apt-ftparchive -o APT::FTPArchive::Release::Origin=Valeneo \
     -o APT::FTPArchive::Release::Label=Valeneo -o APT::FTPArchive::Release::Suite="$suite" \
     -o APT::FTPArchive::Release::Codename="$suite" -o APT::FTPArchive::Release::Architectures="amd64 arm64" \
     -o APT::FTPArchive::Release::Components=main release .) > "$t/Release"
  mv "$t/Release" "$t/dists/$suite/Release"
  gpgsign --clearsign -o "$t/dists/$suite/InRelease" "$t/dists/$suite/Release"
  gpgsign -abs -o "$t/dists/$suite/Release.gpg" "$t/dists/$suite/Release"
  rm -rf "$C/repo/dists/$suite"; mkdir -p "$C/repo/dists"; mv "$t/dists/$suite" "$C/repo/dists/$suite"; rm -rf "$t"
}
build_suite stable stable
build_suite beta stable beta
cp "$K/valeneo.gpg" "$K/valeneo.asc" "$C/repo/"
git -C "$C/repo" add -A
git -C "$C/repo" -c user.name=Valeneo -c user.email=releases@valeneo.space commit -qm "apt index: $tag ($channel)" || true
git -C "$C/repo" push -q origin repo
echo "published $tag"
