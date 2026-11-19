#!/usr/bin/env bash
set -euo pipefail
directory=$1
shift
files=()
for file in "$@"; do
  files+=("${file##*/}")
done
test "${#files[@]}" -gt 0
cd "$directory"
sha256sum -- "${files[@]}" > SHA256SUMS
sha256sum -c SHA256SUMS
