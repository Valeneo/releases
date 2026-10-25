#!/usr/bin/env bash
# Publish a release: GitHub Release (all artifacts) + signed apt index (.deb) + signed rpm repo (.rpm).
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

# 0. sign .rpm files (copies, originals untouched) with the RSA rpm key
RF=$(cat "$K/rpm-fingerprint")
rpmtool() { docker run --rm -v "$K/gnupg:/gnupg:ro" -v "$K/passphrase:/pw:ro" "$@"; }
if printf '%s\n' "$@" | grep -q '\.rpm$'; then
  SIGNDIR=$(mktemp -d); args=()
  for f in "$@"; do
    if [[ $f == *.rpm ]]; then cp "$f" "$SIGNDIR/"; args+=("$SIGNDIR/$(basename "$f")"); else args+=("$f"); fi
  done
  docker run --rm -v "$SIGNDIR:/rpms" -v "$K/gnupg:/gnupg-ro:ro" -v "$K/passphrase:/pw:ro" valeneo-rpmtools bash -c '
    cp -r /gnupg-ro /root/gnupg && export GNUPGHOME=/root/gnupg && chmod 700 /root/gnupg
    cat > /root/.rpmmacros <<M
%_gpg_name '"$RF"'
%__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor --pinentry-mode loopback --passphrase-file /pw --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}
M
    rpmsign --addsign /rpms/*.rpm'
  set -- "${args[@]}"
fi

# 1. GitHub release
flags=(); [ "$channel" = beta ] && flags+=(--prerelease)
if gh release view "$tag" --repo "$GH" >/dev/null 2>&1; then
  gh release upload "$tag" "$@" --repo "$GH" --clobber
else
  gh release create "$tag" "$@" --repo "$GH" --title "$product $version" --generate-notes "${flags[@]}"
fi

# 2. apt index (only if there are .debs)
debs=(); rpms=()
for f in "$@"; do [[ $f == *.deb ]] && debs+=("$f"); [[ $f == *.rpm ]] && rpms+=("$f"); done
[ ${#debs[@]} -gt 0 ] || [ ${#rpms[@]} -gt 0 ] || exit 0
if [ ${#debs[@]} -gt 0 ]; then mkdir -p "$C/pool/$channel/$product/$tag"; cp "${debs[@]}" "$C/pool/$channel/$product/$tag/"; fi
if [ ${#rpms[@]} -gt 0 ]; then mkdir -p "$C/rpmpool/$channel/$product/$tag"; cp "${rpms[@]}" "$C/rpmpool/$channel/$product/$tag/"; fi

if [ ! -d "$C/repo/.git" ]; then
  git clone -q --branch repo "https://github.com/$GH.git" "$C/repo" 2>/dev/null || {
    git clone -q "https://github.com/$GH.git" "$C/repo"; git -C "$C/repo" checkout -q --orphan repo; git -C "$C/repo" rm -rqf . || true; }
else git -C "$C/repo" pull -q --ff-only origin repo; fi

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
if [ ${#debs[@]} -gt 0 ]; then
build_suite stable stable
build_suite beta stable beta
fi

build_rpm() { # channel channels...
  local ch=$1; shift; local t; t=$(mktemp -d); mkdir -p "$t/pool"
  for c in "$@"; do [ -d "$C/rpmpool/$c" ] && cp -a "$C/rpmpool/$c/." "$t/pool/"; done
  docker run --rm -v "$t:/r" -v "$K/gnupg:/gnupg-ro:ro" -v "$K/passphrase:/pw:ro" valeneo-rpmtools bash -c '
    cp -r /gnupg-ro /root/gnupg && export GNUPGHOME=/root/gnupg && chmod 700 /root/gnupg
    cd /r && createrepo_c -q --no-database .
    gpg --batch --yes --pinentry-mode loopback --passphrase-file /pw -u '"$RF"' --detach-sign --armor repodata/repomd.xml
    chown -R '"$(id -u):$(id -g)"' /r' 2>&1 | grep -v 'not a symlink' || true
  rm -rf "$C/repo/rpm/$ch"; mkdir -p "$C/repo/rpm/$ch"; mv "$t/repodata" "$C/repo/rpm/$ch/repodata"
  find "$t" -mindepth 1 -delete 2>/dev/null; rm -rf "$t"
}
if [ ${#rpms[@]} -gt 0 ]; then
build_rpm stable stable
build_rpm beta stable beta
fi
cp "$K/valeneo-rpm.asc" "$C/repo/"
"$(dirname "$0")/render-index.py" "$(dirname "$0")/index.tmpl.html" "$C/repo/index.html"
cp "$K/valeneo.gpg" "$K/valeneo.asc" "$C/repo/"
git -C "$C/repo" add -A
git -C "$C/repo" -c user.name=Valeneo -c user.email=releases@valeneo.space commit -qm "apt index: $tag ($channel)" || true
git -C "$C/repo" push -q origin repo
echo "published $tag"
