# Valeneo releases

Public download page for Valeneo software. Binaries (`.deb`, installers) are attached to
[GitHub Releases](../../releases). Pre-releases are beta builds.

## Install on Debian / Ubuntu (apt)

Signed apt repository: https://repository.valeneo.space

```sh
curl -fsSL https://repository.valeneo.space/valeneo.gpg | sudo tee /etc/apt/keyrings/valeneo.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/valeneo.gpg] https://repository.valeneo.space stable main" | sudo tee /etc/apt/sources.list.d/valeneo.list
sudo apt update
```

Beta builds use the `beta` suite instead of `stable`.
