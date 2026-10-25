#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build the Telegram Bot API server (local mode).
#
# Only needed once. Produces $PREFIX/bin/telegram-bot-api, which lets the
# uploader send files up to 2000 MiB instead of the cloud API's 50 MiB.
#
# Usage:
#   scripts/tg-bot-api-build.sh            # build if missing (incremental)
#   scripts/tg-bot-api-build.sh --force    # wipe build dir first
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${TG_BOT_API_SRC:-/root/tg-bot-api/telegram-bot-api}"
PREFIX="${TG_BOT_API_PREFIX:-/root/tg-bot-api/install}"
JOBS="${TG_BOT_API_JOBS:-$(nproc)}"

c_info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }

[[ "${1:-}" == "--force" ]] && { c_info "removing $SRC/build"; rm -rf "$SRC/build"; }

if [[ -x "$PREFIX/bin/telegram-bot-api" && "${1:-}" != "--force" ]]; then
  c_ok "already built: $PREFIX/bin/telegram-bot-api"
  exit 0
fi

[[ -d "$SRC" ]] || { c_err "source not found at $SRC"; echo "  git clone --depth 1 --recursive https://github.com/tdlib/telegram-bot-api.git $SRC" >&2; exit 1; }

# build deps (Debian/Ubuntu)
missing=()
for p in libssl-dev zlib1g-dev gperf; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  c_info "installing build deps: ${missing[*]}"
  apt-get install -y -qq "${missing[@]}"
fi

c_info "configuring (Release, $JOBS jobs)"
mkdir -p "$SRC/build"
cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null

c_info "compiling (this takes a while)"
cmake --build "$SRC/build" --target install -j "$JOBS"

[[ -x "$PREFIX/bin/telegram-bot-api" ]] || { c_err "build finished but binary missing"; exit 1; }
c_ok "installed $PREFIX/bin/telegram-bot-api"
