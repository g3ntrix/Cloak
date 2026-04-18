Release builds look for zips in **`macos-app/assets/`** first (see `macos-app/assets/README.md`).

You can still drop zips here if you prefer:

- `Xray-macos-arm64-v8a.zip`
- `Xray-macos-64.zip`

Both are required so `fetch-xray-vendor.sh` can `lipo` a single universal `xray` binary that runs on Apple Silicon and Intel Macs.

Release index: https://github.com/XTLS/Xray-core/releases
