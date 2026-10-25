#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Telegram uploader for build artifacts.
#
# Prefers a local Telegram Bot API server (limit 2000 MiB). Falls back to the
# cloud API (limit 50 MiB) when the local server is not running, and skips the
# file with a clear warning when it is too large for the cloud API.
#
# Credentials are read from .telegram.env (gitignored) or the environment:
#   TELEGRAM_BOT_TOKEN   required
#   TELEGRAM_CHAT_ID     required
#
# Usage:
#   scripts/tg-upload.sh <file> [more files...]
#   scripts/tg-upload.sh --caption "text" <file>...
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_PORT="${TG_BOT_API_PORT:-8081}"
CLOUD_LIMIT=$((50 * 1024 * 1024))
LOCAL_LIMIT=$((2000 * 1024 * 1024))

if [[ -f "$ROOT/.telegram.env" ]]; then
  set -a; . "$ROOT/.telegram.env"; set +a
fi

CAPTION=""
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --caption) CAPTION="${2:?}"; shift 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

c_info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }

fmt_size() {
  local b="$1"
  awk -v b="$b" 'BEGIN{ if (b>=1048576) printf "%.1f MiB", b/1048576; else printf "%.0f KiB", b/1024 }'
}

[[ ${#FILES[@]} -gt 0 ]] || { c_err "no files given"; exit 2; }
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || { c_err "TELEGRAM_BOT_TOKEN not set"; exit 2; }
[[ -n "${TELEGRAM_CHAT_ID:-}" ]] || { c_err "TELEGRAM_CHAT_ID not set"; exit 2; }

# pick API base: local server if healthy, else cloud
API="https://api.telegram.org"
LIMIT=$CLOUD_LIMIT
if curl -fsS --max-time 2 "http://127.0.0.1:$LOCAL_PORT/bot${TELEGRAM_BOT_TOKEN}/getMe" >/dev/null 2>&1; then
  API="http://127.0.0.1:$LOCAL_PORT"
  LIMIT=$LOCAL_LIMIT
  c_info "using local Bot API server on port $LOCAL_PORT (limit $((LIMIT / 1024 / 1024)) MiB)"
else
  c_info "using cloud Bot API (limit $((LIMIT / 1024 / 1024)) MiB)"
fi

send_one() {
  local f="$1" size name
  [[ -f "$f" ]] || { c_warn "missing: $f"; return 0; }
  size="$(stat -c%s "$f")"
  name="$(basename "$f")"

  if (( size > LIMIT )); then
    c_err "$name is $(fmt_size "$size"), over the $((LIMIT / 1024 / 1024)) MiB limit of this endpoint -> skipped"
    return 1
  fi

  # --form-string keeps curl from treating a leading '<' or '@' in the
  # caption (HTML markup) as a file-read directive.
  local -a args=(-sS --max-time 1800
    --form-string "chat_id=$TELEGRAM_CHAT_ID"
    --form-string "parse_mode=HTML"
    -F "document=@$f")
  if [[ -n "$CAPTION" ]]; then
    args+=(--form-string "caption=$CAPTION")
  fi

  local resp
  resp="$(curl "${args[@]}" "$API/bot$TELEGRAM_BOT_TOKEN/sendDocument")" || {
    c_err "upload failed for $name (curl error)"; return 1;
  }

  if grep -q '"ok":true' <<<"$resp"; then
    local mid
    mid="$(grep -o '"message_id":[0-9]*' <<<"$resp" | head -1 | cut -d: -f2)"
    c_ok "sent $name ($(fmt_size "$size")) as message $mid"
    return 0
  fi

  local desc
  desc="$(grep -o '"description":"[^"]*"' <<<"$resp" | head -1 | cut -d: -f2- | tr -d '"')"
  c_err "upload failed for $name: ${desc:-unknown error}"
  return 1
}

rc=0
for f in "${FILES[@]}"; do
  send_one "$f" || rc=1
done
exit $rc
