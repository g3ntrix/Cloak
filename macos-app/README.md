# Cloak — macOS app

SwiftUI front-end for the Python **SNI-Spoofing** listener plus a bundled **Xray-core** client (local SOCKS, profiles as share URLs).

See the [root README](../README.md) for the full repo.

## Build (universal app + universal `xray`)

From the repository root:

```bash
chmod +x scripts/build-release.sh macos-app/scripts/*.sh
./scripts/build-release.sh
```

This script:

1. Runs `macos-app/scripts/fetch-xray-vendor.sh` — downloads or uses local release zips for **arm64** and **x64**, then **`lipo`**s a single universal `xray` into `bundle/xray/`.
2. Runs `macos-app/scripts/build-app.sh` — **`swift build`** for **arm64** and **x86_64**, **`lipo`**s the Swift binary, embeds `xray` + `geoip.dat` + `geosite.dat`, ad-hoc signs.

Output (default `BUILD_VARIANT=all`):  
`macos-app/dist/Cloak-arm64.app`, `Cloak-x86_64.app`, `Cloak.app` (universal — usual choice for a single download).

Single variant:  
`BUILD_VARIANT=arm64|x86_64|universal ./macos-app/scripts/build-app.sh`

### Offline / no GitHub access

Place official release archives (same filenames as upstream) under `third_party/xray-zips/` (see `third_party/xray-zips/README.md`), then run `fetch-xray-vendor.sh` or `build-release.sh`.

### Faster incremental Swift builds

```bash
SKIP_SPM_CLEAN=1 ./macos-app/scripts/build-app.sh
```

## Layout

- `Sources/SNISpoofing/` — Swift source
- `scripts/` — `fetch-xray-vendor.sh`, `build-app.sh`
- `bundle/xray/` — generated vendored `xray` + geo data (not committed; see root `.gitignore`)
- `logo/` — brand assets
