#!/usr/bin/env bash
set -euo pipefail

MANAGER_TYPE="${1:?Usage: fetch-manager-apk.sh <KSUN|KSU|SUKISU> [output-dir]}"
OUTPUT_DIR="${2:-manager-apk}"
mkdir -p "$OUTPUT_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

download_release_apk() {
  local api_url="$1"
  local name_pattern="$2"
  local output_name="$3"

  local metadata download_url expected_digest
  metadata="$(curl -fsSL --retry 3 --retry-delay 2 "$api_url")"
  download_url="$(jq -r --arg pattern "$name_pattern" '
    [.assets[] | select(.name | test($pattern; "i"))][0].browser_download_url // empty
  ' <<< "$metadata")"
  expected_digest="$(jq -r --arg pattern "$name_pattern" '
    [.assets[] | select(.name | test($pattern; "i"))][0].digest // empty
  ' <<< "$metadata")"

  if [[ -z "$download_url" ]]; then
    echo "::error::No manager APK matched $name_pattern at $api_url"
    exit 1
  fi

  echo "Downloading manager APK: $download_url"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 \
    "$download_url" -o "$OUTPUT_DIR/$output_name"

  test -s "$OUTPUT_DIR/$output_name"
  if [[ -n "$expected_digest" && "$expected_digest" == sha256:* ]]; then
    expected_digest="${expected_digest#sha256:}"
    echo "$expected_digest  $OUTPUT_DIR/$output_name" | sha256sum --check -
  fi
}

case "$MANAGER_TYPE" in
  KSUN)
    # Official KernelSU-Next Build Manager CI publishes the normal manager
    # as the "manager" artifact on the dev branch.
    ZIP="$TMP_DIR/ksun-manager.zip"
    URL="https://nightly.link/KernelSU-Next/KernelSU-Next/workflows/build-manager-ci/dev/manager.zip"
    echo "Fetching the latest successful KernelSU-Next manager CI artifact..."
    curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 "$URL" -o "$ZIP"
    mapfile -t APK_ENTRIES < <(unzip -Z1 "$ZIP" | grep -E '\\.apk$' || true)
    if [[ "${#APK_ENTRIES[@]}" -ne 1 ]]; then
      printf 'Unexpected APK count in KernelSU-Next artifact: %s\n' "${#APK_ENTRIES[@]}"
      unzip -Z1 "$ZIP"
      exit 1
    fi
    unzip -p "$ZIP" "${APK_ENTRIES[0]}" > "$OUTPUT_DIR/KernelSU-Next-Manager.apk"
    ;;
  KSU)
    download_release_apk \
      "https://api.github.com/repos/tiann/KernelSU/releases/latest" \
      'KernelSU_.*release\\.apk$' \
      "KernelSU-Manager.apk"
    ;;
  SUKISU)
    download_release_apk \
      "https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/releases/tags/manager-ci" \
      'arm64-v8a-release\\.apk$' \
      "SukiSU-Ultra-Manager.apk"
    ;;
  *)
    echo "::error::Unsupported manager type: $MANAGER_TYPE"
    exit 1
    ;;
esac

APK="$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.apk' -print -quit)"
test -n "$APK"
unzip -tq "$APK" >/dev/null
echo "Manager APK: $APK"
echo "Size: $(du -h "$APK" | cut -f1)"
echo "SHA256: $(sha256sum "$APK" | awk '{print $1}')"
