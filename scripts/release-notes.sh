#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Generate release notes (Markdown) for a DuskGram build.
#
# Usage:
#   scripts/release-notes.sh <apk> [more apks...]
#
# Reads the version from gradle.properties, derives the ABI from each APK's
# file name, and prints a self-contained release description to stdout.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APKS=("$@")
[[ ${#APKS[@]} -gt 0 ]] || { echo "usage: $0 <apk> [...]" >&2; exit 2; }

prop() { grep -m1 "^$1=" gradle.properties 2>/dev/null | cut -d= -f2; }

VERSION="$(prop APP_VERSION_NAME)"
CODE="$(prop APP_VERSION_CODE)"
UP_VERSION="$(prop UPSTREAM_VERSION_NAME)"
UP_CODE="$(prop UPSTREAM_VERSION_CODE)"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHA_FULL="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
BUILT="$(date -u '+%Y-%m-%d %H:%M UTC')"

human() {
  awk -v b="$1" 'BEGIN{
    if (b>=1073741824) printf "%.1f GiB", b/1073741824;
    else if (b>=1048576) printf "%.1f MiB", b/1048576;
    else printf "%.0f KiB", b/1024 }'
}

abi_of() {
  case "$(basename "$1")" in
    *arm64-v8a*)   echo "arm64-v8a" ;;
    *armeabi-v7a*) echo "armeabi-v7a" ;;
    *x86_64*)      echo "x86_64" ;;
    *x86*)         echo "x86" ;;
    *)             echo "universal" ;;
  esac
}

abi_note() {
  case "$1" in
    arm64-v8a)   echo "64-bit ARM — nearly all phones since ~2015" ;;
    armeabi-v7a) echo "32-bit ARM — older or low-end devices" ;;
    x86_64)      echo "64-bit x86 — emulators" ;;
    x86)         echo "32-bit x86 — emulators" ;;
    *)           echo "all architectures" ;;
  esac
}

# signing certificate, if apksigner is available
APKSIGNER="$(command -v apksigner 2>/dev/null || true)"
if [[ -z "$APKSIGNER" ]]; then
  for base in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /opt/android-sdk "$HOME/Android/Sdk"; do
    [[ -n "$base" && -d "$base/build-tools" ]] || continue
    APKSIGNER="$(ls -1 "$base"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
    [[ -n "$APKSIGNER" ]] && break
  done
fi
CERT_SHA=""
CERT_DN=""
if [[ -n "$APKSIGNER" && -x "$APKSIGNER" ]]; then
  CERT_OUT="$("$APKSIGNER" verify --print-certs "${APKS[0]}" 2>/dev/null || true)"
  # output format differs across build-tools versions:
  #   "Signer #1 certificate SHA-256 digest: ..."  (<= 36)
  #   "V3.0 Signer: certificate SHA-256 digest: ..." (37+)
  CERT_SHA="$(sed -n 's/.*certificate SHA-256 digest: //p' <<<"$CERT_OUT" | head -1)"
  CERT_DN="$(sed -n 's/.*certificate DN: //p' <<<"$CERT_OUT" | head -1)"
fi

# Changelog: only this fork's own work, never upstream Telegram/Nagram history.
# A "fork-start" tag marks the last upstream commit; fall back to path filtering
# when the tag is missing.
FORK_TAG="fork-start"
CHANGELOG=""
if git rev-parse -q --verify "refs/tags/$FORK_TAG" >/dev/null 2>&1; then
  CHANGELOG="$(git log --no-merges --pretty='- %s (`%h`)' "$FORK_TAG"..HEAD 2>/dev/null | head -40 || true)"
else
  CHANGELOG="$(git log --no-merges --pretty='- %s (`%h`)' HEAD -- \
    build.sh scripts/ gradle.properties TMessagesProj/build.gradle \
    TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java \
    TMessagesProj/src/main/java/org/telegram/ui/LauncherIconController.java \
    TMessagesProj/src/main/AndroidManifest.xml \
    TMessagesProj/src/main/res 2>/dev/null | head -40 || true)"
fi
if [[ -z "$CHANGELOG" ]]; then
  CHANGELOG="- Initial DuskGram release: rebranded from Nagram, new launcher icons,
  reset versioning and build tooling."
fi

cat <<EOF
An independent Telegram client for Android, built from the Nagram codebase.

**Version** \`$VERSION\` · **Build** \`$CODE\` · **Upstream** Telegram \`$UP_VERSION\` ($UP_CODE)
**Commit** [\`$SHA\`](https://github.com/itswill00/DuskGram/commit/$SHA_FULL) on \`$BRANCH\`

## Downloads

| File | ABI | Size | SHA-256 |
|---|---|---|---|
EOF

for f in "${APKS[@]}"; do
  [[ -f "$f" ]] || continue
  abi="$(abi_of "$f")"
  size="$(human "$(stat -c%s "$f")")"
  sum="$(sha256sum "$f" | cut -d' ' -f1)"
  printf '| `%s` | %s | %s | `%s` |\n' "$(basename "$f")" "$abi" "$size" "$sum"
done

cat <<EOF

Choose the ABI that matches your device:

EOF

for f in "${APKS[@]}"; do
  [[ -f "$f" ]] || continue
  abi="$(abi_of "$f")"
  printf -- '- **%s** — %s\n' "$abi" "$(abi_note "$abi")"
done

cat <<EOF

## Installation

1. Download the APK that matches your device (see the table above).
2. Open it and allow installation from unknown sources when Android asks.
3. DuskGram installs **alongside** Telegram and Nagram: it uses its own
   package name, \`app.duskgram.messenger\`, so it will not replace or update
   an existing client.

Requires Android 6.0 (API 23) or newer. Target SDK is 36.

## Changes

$CHANGELOG

## Verification

EOF

if [[ -n "$CERT_SHA" ]]; then
  cat <<EOF
Signed with a self-signed certificate.

**Subject:** \`$CERT_DN\`

**SHA-256 fingerprint:**

\`\`\`
$CERT_SHA
\`\`\`

Check a download with:

\`\`\`bash
apksigner verify --print-certs DuskGram-*.apk
\`\`\`
EOF
else
  echo "apksigner was not available while generating these notes, so the certificate fingerprint is not listed."
fi

cat <<EOF

## About

DuskGram is a fork of [Nagram](https://github.com/NextAlone/Nagram), which is
itself based on NekoX and the official Telegram for Android client. The source
is licensed under GPLv3. DuskGram is not affiliated with, endorsed by, or an
official release of Telegram or the Nagram project.

---

Built on $BUILT
EOF
