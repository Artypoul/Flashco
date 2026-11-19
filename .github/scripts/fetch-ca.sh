#!/usr/bin/env bash
set -euo pipefail
bundle=core/Clash.Meta/component/ca/ca-certificates.crt
tmp="${bundle}.download"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp" https://curl.se/ca/cacert-2026-09-25.pem
expected=a41b5d356aea97a529fe27e0f7316d2f9d946d75927476cf9cf1b90637d00505
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s  %s\n' "$expected" "$tmp" | sha256sum -c -
else
  printf '%s  %s\n' "$expected" "$tmp" | shasum -a 256 -c -
fi
mv "$tmp" "$bundle"
