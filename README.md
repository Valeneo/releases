# Valeneo releases

Public home for every Valeneo release. **All binaries live in [GitHub Releases](../../releases)**
(one tag per product release, `<product>-v<version>`; betas are marked pre-release).
Package-manager repos only index or point at those assets, nothing is stored on the server.

| Platform | Channel |
|---|---|
| Debian / Ubuntu | apt, `https://repository.valeneo.space` (live) |
| Fedora / openSUSE | rpm repo (planned) |
| Windows | winget / Scoop (planned) |
| macOS | Homebrew cask (planned) |

## apt

```sh
sudo install -d /etc/apt/keyrings
curl -fsSL https://repository.valeneo.space/valeneo.gpg | sudo tee /etc/apt/keyrings/valeneo.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/valeneo.gpg] https://repository.valeneo.space stable main" | sudo tee /etc/apt/sources.list.d/valeneo.list
sudo apt update
```

Use `beta` instead of `stable` to get pre-releases (the beta suite also includes stable builds).
Key fingerprint: `AAF4 FBB3 4FC9 444A 94A9  65B3 E069 B7DF D907 46C1`

## How it works

`scripts/publish.sh <product> <version> <stable|beta> <files...>` creates the GitHub release, and
for `.deb` files rebuilds the signed apt index on the `repo` branch. nginx on
repository.valeneo.space proxies the index from that branch and 302-redirects `pool/` downloads
to the release assets.
