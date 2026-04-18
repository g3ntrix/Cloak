Xray-core binary and geo databases for embedding into Cloak.app.

build-app.sh does not download. Populate bundle/xray using either:

  A) Put the official zip at:

       native-mac/Xray-macos-arm64-v8a.zip   (Apple Silicon)
       native-mac/Xray-macos-64.zip          (Intel)

     then run:

       ./macos-app/scripts/fetch-xray-vendor.sh

     That unpacks into this folder with no curl.

  B) Or: ./macos-app/scripts/fetch-xray-vendor.sh with network (GitHub fallback).

  C) Or set LOCAL_XRAY_ZIP=/path/to/Xray-macos-arm64-v8a.zip once.
