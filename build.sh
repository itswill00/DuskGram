#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DuskGram smart incremental build
#
# Never cleans. Only rebuilds what actually changed:
#   * native (.so)  -> only if jni sources / submodules / patches changed
#   * gradle APK    -> gradle's own incremental build (tasks stay UP-TO-DATE)
#
# Usage:
#   ./build.sh                     # native (if needed) + APK for default ABIs
#   ./build.sh -a arm64-v8a        # single ABI
#   ./build.sh --apk-only          # skip native entirely
#   ./build.sh --native-only       # only rebuild native libs
#   ./build.sh --force-native      # force native rebuild (no clean)
#   ./build.sh --debug             # assembleDebug instead of assembleRelease
#   ./build.sh --status            # show state, build nothing
#   ./build.sh --send              # after building, post APKs to Telegram
#   ./build.sh --send-only         # post existing APKs, build nothing
#   ./build.sh --release           # also publish APKs as a GitHub Release
#   ./build.sh --release-only      # publish existing APKs, build nothing
#   ./build.sh --bump [patch|minor|major]
#                                  # bump version first, then build
#
# Telegram: credentials come from .telegram.env (gitignored) or the
# environment (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID). A local Bot API server
# raises the upload limit from 50 MiB to 2000 MiB; see scripts/tg-bot-api.sh.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$(pwd)"

# ----------------------------- config --------------------------------------
SDK="${ANDROID_HOME:-/opt/android-sdk}"
NDK_VERSION="27.2.12479018"
NDK_DIR="$SDK/ndk/$NDK_VERSION"
DEFAULT_ABIS=(arm64-v8a armeabi-v7a)
CACHE_DIR="$ROOT/.build-cache"
OUT_DIR="$ROOT/TMessagesProj/build/outputs/apk"
LIBS_DIR="$ROOT/TMessagesProj/src/main/libs"
KEYSTORE="$ROOT/TMessagesProj/release.keystore"
GRADLE_TASK_RELEASE="TMessagesProj:assembleRelease"
GRADLE_TASK_DEBUG="TMessagesProj:assembleDebug"

# ----------------------------- args ----------------------------------------
ABIS=()
DO_NATIVE=1
DO_APK=1
FORCE_NATIVE=0
DEBUG_BUILD=0
STATUS_ONLY=0
DO_SEND=0
DO_RELEASE=0
BUMP=""

usage() { sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--abi)        IFS=',' read -r -a ABIS <<< "${2:?missing ABI}"; shift 2 ;;
    --apk-only)      DO_NATIVE=0; shift ;;
    --native-only)   DO_APK=0; shift ;;
    --force-native)  FORCE_NATIVE=1; shift ;;
    --debug)         DEBUG_BUILD=1; shift ;;
    --status)        STATUS_ONLY=1; shift ;;
    --send)          DO_SEND=1; shift ;;
    --send-only)     DO_SEND=1; DO_NATIVE=0; DO_APK=0; shift ;;
    --release)       DO_RELEASE=1; shift ;;
    --release-only)  DO_RELEASE=1; DO_NATIVE=0; DO_APK=0; shift ;;
    --bump)          BUMP="${2:-patch}"; shift 2 ;;
    -h|--help)       usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done
[[ ${#ABIS[@]} -eq 0 ]] && ABIS=("${DEFAULT_ABIS[@]}")

# ----------------------------- helpers -------------------------------------
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# ----------------------------- env -----------------------------------------
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export ANDROID_NDK_HOME="$NDK_DIR"
export NDK="$NDK_DIR"
export PATH="$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$NDK_DIR:$PATH"
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"

# ----------------------------- preflight -----------------------------------
[[ -d "$SDK" ]]          || die "Android SDK not found at $SDK (set ANDROID_HOME)"
[[ -f "$NDK_DIR/source.properties" ]] || die "NDK $NDK_VERSION not found at $NDK_DIR"
[[ -x "$ROOT/gradlew" ]] || die "gradlew missing"

# local.properties (only create if absent)
if [[ ! -f "$ROOT/local.properties" ]]; then
  c_warn "local.properties missing -> creating"
  cat > "$ROOT/local.properties" <<EOF
sdk.dir=$SDK
ndk.dir=$NDK_DIR
KEYSTORE_PASS=123456
ALIAS_NAME=key0
ALIAS_PASS=123456
EOF
fi

# keystore (only create if absent)
if [[ ! -f "$KEYSTORE" ]]; then
  c_warn "release.keystore missing -> generating test keystore"
  keytool -genkeypair -v -keystore "$KEYSTORE" -alias key0 -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass 123456 -keypass 123456 \
    -dname "CN=Nagram Test, OU=Dev, O=Test, L=Jakarta, S=DKI, C=ID" >/dev/null
fi

# signature check must stay disabled for a self-signed build (idempotent)
JNI_C="$ROOT/TMessagesProj/jni/jni.c"
if grep -q 'if (verifySign(env) != JNI_OK)' "$JNI_C" 2>/dev/null; then
  c_warn "re-disabling native signature check in jni.c"
  perl -0pi -e 's/if \(verifySign\(env\) != JNI_OK\) \{\s*return JNI_ERR;\s*\}/\/\/ signature verification removed for local test build/' "$JNI_C"
fi

mkdir -p "$CACHE_DIR"

# ----------------------------- fingerprints --------------------------------
# Content-based hash of everything that can change the native output.
native_fingerprint() {
  {
    echo "HEAD:$(git rev-parse HEAD 2>/dev/null || echo none)"
    echo "JNI-TREE:$(git rev-parse HEAD:TMessagesProj/jni 2>/dev/null || echo none)"
    echo "SUB:$(git submodule status -- TMessagesProj/jni 2>/dev/null | tr -d ' ')"
    echo "DIRTY:$(git status --porcelain --ignore-submodules=all -- TMessagesProj/jni 2>/dev/null)"
    echo "DIFF:$(git diff HEAD -- TMessagesProj/jni 2>/dev/null | sha256sum | cut -d' ' -f1)"
    echo "UNTRACKED:$(git ls-files -o --exclude-standard -- TMessagesProj/jni 2>/dev/null \
        | while read -r f; do sha256sum "$f"; done | sha256sum | cut -d' ' -f1)"
    echo "NDK:$(cat "$NDK_DIR/source.properties" 2>/dev/null | sha256sum | cut -d' ' -f1)"
  } | sha256sum | cut -d' ' -f1
}

fp_file() { echo "$CACHE_DIR/native-$1.fp"; }
so_file() { echo "$LIBS_DIR/$1/libtmessages.49.so"; }

needs_native() {
  local abi="$1" fp="$2"
  local so fp_f
  so="$(so_file "$abi")"; fp_f="$(fp_file "$abi")"
  [[ -f "$so" ]] || { echo "missing-lib"; return 0; }
  if [[ -f "$fp_f" ]] && [[ "$(cat "$fp_f")" == "$fp" ]]; then
    echo "up-to-date"; return 1
  fi
  # Adopt an existing .so that is newer than every native source: it was built
  # from the current tree, so record the fingerprint instead of rebuilding.
  if [[ ! -f "$fp_f" ]] && so_is_fresh "$so"; then
    echo "$fp" > "$fp_f"
    echo "adopted"; return 1
  fi
  [[ -f "$fp_f" ]] || { echo "no-fingerprint"; return 0; }
  echo "sources-changed"; return 0
}

# True when $1 is newer than the newest file that can influence native output.
so_is_fresh() {
  local so="$1" newest
  newest="$(find "$ROOT/TMessagesProj/jni" \
              "$ROOT/TMessagesProj/build.gradle" "$ROOT/gradle.properties" \
              -type f -newer "$so" -print -quit 2>/dev/null)"
  [[ -z "$newest" ]]
}

# ----------------------------- status --------------------------------------
show_status() {
  local fp; fp="$(native_fingerprint)"
  c_info "repo: $(git rev-parse --short HEAD 2>/dev/null) ($(git rev-parse --abbrev-ref HEAD 2>/dev/null))"
  printf '    native fingerprint: %s\n' "${fp:0:16}..."
  for abi in "${ABIS[@]}"; do
    local reason so
    so="$(so_file "$abi")"
    if reason="$(needs_native "$abi" "$fp")"; then
      printf '    %-14s native: %s\n' "$abi" "REBUILD ($reason)"
    else
      printf '    %-14s native: ok (%s)\n' "$abi" "$(du -h "$so" | cut -f1)"
    fi
  done
  printf '    apk dir: %s\n' "$OUT_DIR"
  if compgen -G "$OUT_DIR/*/*.apk" >/dev/null; then
    find "$OUT_DIR" -name '*.apk' -printf '      %f (%s bytes)\n' 2>/dev/null || true
  else
    printf '      (no apk yet)\n'
  fi
}

if [[ $STATUS_ONLY -eq 1 ]]; then show_status; exit 0; fi

# ----------------------------- lock ----------------------------------------
exec 9>"$CACHE_DIR/.lock"
flock -n 9 || die "another build.sh is already running"

# ----------------------------- version bump --------------------------------
bump_version() {
  local kind="${1:-patch}"
  local props="$ROOT/gradle.properties"
  local name code
  name="$(grep -m1 '^APP_VERSION_NAME=' "$props" | cut -d= -f2)"
  code="$(grep -m1 '^APP_VERSION_CODE=' "$props" | cut -d= -f2)"

  IFS=. read -r major minor patch <<< "$name"
  case "$kind" in
    major) major=$((major+1)); minor=0; patch=0 ;;
    minor) minor=$((minor+1)); patch=0 ;;
    patch) patch=$((patch+1)) ;;
    *) die "unknown bump kind: $kind (use patch|minor|major)" ;;
  esac
  local newname="${major}.${minor}.${patch}"
  local newcode=$((code+1))

  sed -i "s/^APP_VERSION_NAME=.*/APP_VERSION_NAME=$newname/" "$props"
  sed -i "s/^APP_VERSION_CODE=.*/APP_VERSION_CODE=$newcode/" "$props"
  # BuildConfig.BUILD_TIMESTAMP feeds the in-app updater, so it has to move
  # with every release or two builds of the same version look identical.
  sed -i "s/^APP_BUILD_TIMESTAMP=.*/APP_BUILD_TIMESTAMP=$(date +%s000)/" "$props"
  c_ok "version bumped: $name ($code) -> $newname ($newcode)"
}

if [[ -n "$BUMP" ]]; then
  bump_version "$BUMP"
fi

# ----------------------------- native --------------------------------------
if [[ $DO_NATIVE -eq 1 ]]; then
  FP="$(native_fingerprint)"
  TODO=()
  for abi in "${ABIS[@]}"; do
    if [[ $FORCE_NATIVE -eq 1 ]]; then TODO+=("$abi"); c_info "native $abi: forced rebuild"; continue; fi
    if reason="$(needs_native "$abi" "$FP")"; then
      TODO+=("$abi")
      c_info "native $abi: rebuild needed ($reason)"
    else
      c_ok  "native $abi: $reason, skipped"
    fi
  done

  if [[ ${#TODO[@]} -gt 0 ]]; then
    for abi in "${TODO[@]}"; do
      c_info "building native for $abi (incremental, no clean)"
      NATIVE_TARGET="$abi" ./run libs native
      [[ -f "$(so_file "$abi")" ]] || die "native build produced no lib for $abi"
      echo "$FP" > "$(fp_file "$abi")"
      c_ok "native $abi done: $(du -h "$(so_file "$abi")" | cut -f1)"
    done
  else
    c_ok "native: nothing to do"
  fi
fi

# ----------------------------- apk -----------------------------------------
if [[ $DO_APK -eq 1 ]]; then
  TASK="$GRADLE_TASK_RELEASE"
  [[ $DEBUG_BUILD -eq 1 ]] && TASK="$GRADLE_TASK_DEBUG"

  c_info "gradle $TASK (incremental, build-cache on)"
  ./gradlew "$TASK" \
      --build-cache \
      --no-configuration-cache \
      --warning-mode=none \
      --console=plain

  touch "$CACHE_DIR/.last-apk"

  c_info "APKs"
  # shellcheck disable=SC2012
  ls -1t "$OUT_DIR"/*/*.apk 2>/dev/null | while read -r f; do
    printf '    %s  (%s)\n' "$f" "$(du -h "$f" | cut -f1)"
  done
  c_ok "build finished"
fi

# ----------------------------- telegram ------------------------------------
if [[ $DO_SEND -eq 1 ]]; then
  APKS=()
  while IFS= read -r f; do APKS+=("$f"); done < <(find "$OUT_DIR" -name '*.apk' -type f 2>/dev/null | sort)

  if [[ ${#APKS[@]} -eq 0 ]]; then
    c_warn "no APK found in $OUT_DIR, nothing to send"
  else
    # Keep the caption short: version, what changed, where to get it.
    VERSION="$(grep -m1 '^APP_VERSION_NAME=' "$ROOT/gradle.properties" 2>/dev/null | cut -d= -f2)"
    CODE="$(grep -m1 '^APP_VERSION_CODE=' "$ROOT/gradle.properties" 2>/dev/null | cut -d= -f2)"
    TAG="v${VERSION:-?}-${CODE:-?}"

    CAPTION="$(printf '<b>DuskGram %s</b>' "${VERSION:-?}")"
    # Bullets come from the commits made since the previous release tag, so the
    # caption stays accurate even when the last commit is only a version bump.
    PREV_TAG="$(git describe --tags --abbrev=0 'HEAD^' 2>/dev/null || echo fork-start)"
    BULLETS="$(git log "${PREV_TAG}..HEAD" --pretty=%s 2>/dev/null \
      | grep -viE '^(bump version|merge |revert )' \
      | head -5 || true)"
    if [[ -n "$BULLETS" ]]; then
      while IFS= read -r line; do
        CAPTION+="$(printf '\n• %s' "$line")"
      done <<<"$BULLETS"
    fi
    CAPTION+="$(printf '\n\n<a href="https://github.com/itswill00/DuskGram/releases/tag/%s">GitHub release</a>' "$TAG")"

    c_info "posting ${#APKS[@]} APK(s) to Telegram"
    if [[ ! -x "$ROOT/scripts/tg-upload.sh" ]]; then
      c_err "scripts/tg-upload.sh missing"
    elif ! "$ROOT/scripts/tg-upload.sh" --caption "$CAPTION" "${APKS[@]}"; then
      c_warn "some uploads failed (see above); build output is still valid"
    fi
  fi
fi

# ----------------------------- github release ------------------------------
if [[ $DO_RELEASE -eq 1 ]]; then
  APKS=()
  while IFS= read -r f; do APKS+=("$f"); done < <(find "$OUT_DIR" -name '*.apk' -type f 2>/dev/null | sort)

  if [[ ${#APKS[@]} -eq 0 ]]; then
    c_warn "no APK found in $OUT_DIR, nothing to publish"
  elif ! command -v gh >/dev/null 2>&1; then
    c_err "gh CLI not found, cannot publish a release"
  else
    VERSION="$(grep -m1 '^APP_VERSION_NAME=' "$ROOT/gradle.properties" | cut -d= -f2)"
    CODE="$(grep -m1 '^APP_VERSION_CODE=' "$ROOT/gradle.properties" | cut -d= -f2)"
    TAG="v${VERSION}-${CODE}"

    NOTES_FILE="$(mktemp)"
    if [[ -x "$ROOT/scripts/release-notes.sh" ]]; then
      "$ROOT/scripts/release-notes.sh" "${APKS[@]}" > "$NOTES_FILE" 2>/dev/null || true
    fi
    if [[ ! -s "$NOTES_FILE" ]]; then
      printf 'DuskGram %s (build %s)\n' "${VERSION:-?}" "${CODE:-?}" > "$NOTES_FILE"
    fi

    c_info "publishing GitHub release $TAG"
    if gh release view "$TAG" >/dev/null 2>&1; then
      c_info "release $TAG exists, uploading assets (clobber)"
      gh release edit "$TAG" --title "DuskGram $VERSION ($CODE)" --notes-file "$NOTES_FILE" >/dev/null 2>&1 || true
      if gh release upload "$TAG" "${APKS[@]}" --clobber; then
        c_ok "assets updated on release $TAG"
      else
        c_warn "uploading assets failed"
      fi
    elif gh release create "$TAG" "${APKS[@]}" --title "DuskGram $VERSION ($CODE)" --notes-file "$NOTES_FILE"; then
      c_ok "release $TAG published"
    else
      c_warn "creating release $TAG failed"
    fi
    rm -f "$NOTES_FILE"
  fi
fi
