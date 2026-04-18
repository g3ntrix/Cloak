# SNI-Spoofing-GUI

Companion repository: Python DPI-bypass listener (`main.py`, etc.) plus a **macOS Swift app** (“Cloak”) that runs the listener and an embedded **Xray** client with local SOCKS.

## macOS app (recommended)

- Build a universal **Cloak.app** (Apple Silicon + Intel) and embed a universal **xray** binary:

  ```bash
  chmod +x scripts/build-release.sh macos-app/scripts/*.sh
  ./scripts/build-release.sh
  ```

- **Offline / restricted network:** put official release zips into `macos-app/third_party/xray-zips/` (see that folder’s README), then run `macos-app/scripts/fetch-xray-vendor.sh` (or the release script above).

- Default listener `config.json` keys are shipped empty except bind address/port so you can fill in **CONNECT_** / **FAKE_SNI** in-app or in JSON.

**Apple Silicon vs Intel:** an **arm64-only** `xray` does **not** run on Intel Macs. The release script builds **three** app bundles: `Cloak-arm64.app`, `Cloak-x86_64.app`, and **`Cloak.app`** (universal Swift + universal `xray` — the usual artifact to ship). Single-arch apps embed a thinned `xray` slice where possible.

If `curl` from GitHub fails on your network, drop the official release zips into `macos-app/third_party/xray-zips/` (see that folder’s README) and run the fetch script again.

Details: [`macos-app/README.md`](macos-app/README.md)

## Python engine (reference / same layout as typical SNI-Spoofing)

- Install deps: `pip install -r requirements.txt`
- Configure `config.json` beside `main.py`
- Run with the privileges your OS requires for raw capture/injection

## Donations

If this project helps you, you can support development:

- TON: `UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx`
- USDT (BEP20): `0x71F41696c60C4693305e67eE3Baa650a4E3dA796`
- TRX (TRON): `TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV`

## License

See [LICENSE](LICENSE).
