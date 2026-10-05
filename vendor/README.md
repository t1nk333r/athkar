# Vendored libraries

Third-party files used by «نقل التقدّم» (spec/transfer/transfer-v1.md). They are copied unchanged from the npm
tarballs: no build step and no CDN. `index.html` loads them only when a QR view opens, and `sw.js` caches them in
`APP_SHELL`, so the QR flow works offline.

| File | Package | Version | Licence | SHA-256 |
| --- | --- | --- | --- | --- |
| `qrcode.js` | [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (`dist/qrcode.js`) | 2.0.4 | MIT, [`LICENSE-qrcode-generator.txt`](LICENSE-qrcode-generator.txt) | `79ec86f82856005b1c887905cfccfcfbec3821ca61c7fd5a952faa5f778f791c` |
| `qr-scanner.min.js` | [qr-scanner](https://github.com/nimiq/qr-scanner) | 1.4.2 | MIT, [`LICENSE-qr-scanner.txt`](LICENSE-qr-scanner.txt) | `0564e4cf84b94cac80213b4f779bd215bb0876a91c19df28baf97766f4fd5484` |
| `qr-scanner-worker.min.js` | qr-scanner | 1.4.2 | MIT, as above | `f4d8445f5a15c4e5f71a8c8c062c6443f09db370b8d3fe1fbdc7fe7889630d14` |

npm integrity: qrcode-generator@2.0.4
`sha512-mZSiP6RnbHl4xL2Ap5HfkjLnmxfKcPWpWe/c+5XxCuetEenqmNFf1FH/ftXPCtFG5/TDobjsjz6sSNL0Sr8Z9g==`;
qr-scanner@1.4.2 `sha512-kV1yQUe2FENvn59tMZW6mOVfpq9mGxGf8l6+EGaXUOd4RBOLg7tRC83OrirM5AtDvZRpdjdlXURsHreAOSPOUw==`.

- `qrcode.js` draws the send side's QR frames (alphanumeric mode, level M). It defines the global `qrcode`.
- `qr-scanner.min.js` is an ES module, loaded with `import()` only where the browser has no native `BarcodeDetector`
  for QR codes (iOS Safari and the Home Screen app, desktop Firefox). It imports `./qr-scanner-worker.min.js` itself,
  which starts the decoder in a Blob worker. The source maps are not vendored.

To update: `npm pack <package>@<version>`, copy the same files, update this table and the `APP_SHELL` entries in
`sw.js`, and bump `CACHE_NAME`.
