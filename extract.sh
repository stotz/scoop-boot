#!/usr/bin/env bash

set -e

DOWNLOAD_DIR="/c/data/Downloads"
TARGET_DIR="/c/devl"

extract() {
  local pkg="$1"
  local pattern="${DOWNLOAD_DIR}/${pkg}_v[0-9][0-9][0-9][0-9].tar.bz2"
  local download

  # Find matching file (glob expansion)
  download=$(ls -1 $pattern 2>/dev/null | tail -1)

  if [ -z "$download" ]; then
    echo "[SKIP] No archive found for ${pkg}"
    return 0
  fi

  local tarbz2=$(basename "$download")

  echo "[EXTRACT] ${tarbz2}"
  mv -v "$download" "${TARGET_DIR}/"
  cd "${TARGET_DIR}"
  tar xjpf "$tarbz2"
  sha256sum "$tarbz2"
  echo ""
}

extract scoop-boot