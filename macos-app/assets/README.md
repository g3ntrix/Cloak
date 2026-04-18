# Release build inputs (local files)

DMG / release builds expect these files here so nothing is fetched at build time:

| File | Purpose |
|------|---------|
| `Xray-macos-arm64-v8a.zip` | ARM64 Xray from [Xray-core releases](https://github.com/XTLS/Xray-core/releases) |
| `Xray-macos-64.zip` | x86_64 Xray (same release tag) |
| `scapy-*.whl` | Python wheel for [scapy](https://pypi.org/project/scapy/) (offline install in the app) |

Populate or refresh everything:

```bash
./macos-app/scripts/fetch-release-assets.sh
```

Override Xray version:

```bash
XRAY_VERSION=v26.3.27 ./macos-app/scripts/fetch-release-assets.sh
```

Then from the repo root:

```bash
VERSION=1.0.0 ./scripts/build-release.sh
```
