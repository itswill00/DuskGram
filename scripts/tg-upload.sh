#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Telegram uploader for build artifacts.
#
# Multiple files are posted as a single album (one bubble, one caption) via
# sendMediaGroup. A single file is posted with sendDocument.
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
#   scripts/tg-upload.sh --separate --caption "text" <file>...
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_PORT="${TG_BOT_API_PORT:-8081}"
CLOUD_LIMIT=$((50 * 1024 * 1024))
LOCAL_LIMIT=$((2000 * 1024 * 1024))
ALBUM_MAX=10

if [[ -f "$ROOT/.telegram.env" ]]; then
  set -a; . "$ROOT/.telegram.env"; set +a
fi

CAPTION=""
CHAT_OVERRIDE=""
SEPARATE=0
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --caption)  CAPTION="${2:?}"; shift 2 ;;
    --chat)     CHAT_OVERRIDE="${2:?}"; shift 2 ;;
    --separate) SEPARATE=1; shift ;;
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
if [[ -n "$CHAT_OVERRIDE" ]]; then
  TELEGRAM_CHAT_ID="$CHAT_OVERRIDE"
fi
[[ -n "${TELEGRAM_CHAT_ID:-}" ]] || { c_err "TELEGRAM_CHAT_ID not set"; exit 2; }

# Release posts are meant to stay minimal: one album, one short caption.
# Flag anything that looks like the old wall-of-text post.
if [[ -n "$CAPTION" ]]; then
  CAP_LINES=$(printf '%s\n' "$CAPTION" | wc -l)
  CAP_CHARS=${#CAPTION}
  if (( CAP_LINES > 10 || CAP_CHARS > 400 )); then
    c_warn "caption is ${CAP_LINES} lines / ${CAP_CHARS} chars; release posts should stay minimal (see AGENTS.md)"
  fi
fi

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

# drop files that are missing or too large; fills SEND with usable paths
SEND=()
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { c_warn "missing: $f"; continue; }
  size="$(stat -c%s "$f")"
  if (( size > LIMIT )); then
    c_err "$(basename "$f") is $(fmt_size "$size"), over the $((LIMIT / 1024 / 1024)) MiB limit of this endpoint -> skipped"
    continue
  fi
  SEND+=("$f")
done

[[ ${#SEND[@]} -gt 0 ]] || { c_err "nothing to upload"; exit 1; }


# json_escape: minimal escaping for the caption inside the media JSON
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

describe() {
  local name
  name="$(basename "$1")"
  c_ok "sent $name ($(fmt_size "$(stat -c%s "$1")")) as message $2"
}

# send_album <files...> — all files in one bubble, caption on the first item
send_album() {
  local -a batch=("$@")
  local media="[" first=1 i=0 f resp desc mid
  for f in "${batch[@]}"; do
    [[ $first -eq 1 ]] || media+=","
    media+="{\"type\":\"document\",\"media\":\"attach://file$i\""
    if [[ $first -eq 1 && -n "$CAPTION" ]]; then
      media+=",\"caption\":\"$(json_escape "$CAPTION")\",\"parse_mode\":\"HTML\""
    fi
    media+="}"
    first=0
    i=$((i + 1))
  done
  media+="]"

  local -a args=(-sS --max-time 1800
    --form-string "chat_id=$TELEGRAM_CHAT_ID"
    --form-string "media=$media")
  i=0
  for f in "${batch[@]}"; do
    args+=(-F "file$i=@$f")
    i=$((i + 1))
  done

  resp="$(curl "${args[@]}" "$API/bot$TELEGRAM_BOT_TOKEN/sendMediaGroup")" || {
    c_err "album upload failed (curl error)"; return 1;
  }

  if grep -q '"ok":true' <<<"$resp"; then
    mid="$(grep -o '"message_id":[0-9]*' <<<"$resp" | head -1 | cut -d: -f2)"
    c_ok "sent ${#batch[@]} file(s) as one album (message ${mid:-?})"
    return 0
  fi

  desc="$(grep -o '"description":"[^"]*"' <<<"$resp" | head -1 | cut -d: -f2- | tr -d '"')"
  c_warn "album upload failed: ${desc:-unknown error}; falling back to separate messages"
  return 1
}

send_one() {
  local f="$1" name size resp desc mid
  name="$(basename "$f")"
  size="$(stat -c%s "$f")"

  # --form-string keeps curl from treating a leading '<' or '@' in the
  # caption (HTML markup) as a file-read directive.
  local -a args=(-sS --max-time 1800
    --form-string "chat_id=$TELEGRAM_CHAT_ID"
    --form-string "parse_mode=HTML"
    -F "document=@$f")
  if [[ -n "$CAPTION" ]]; then
    args+=(--form-string "caption=$CAPTION")
  fi

  resp="$(curl "${args[@]}" "$API/bot$TELEGRAM_BOT_TOKEN/sendDocument")" || {
    c_err "upload failed for $name (curl error)"; return 1;
  }

  if grep -q '"ok":true' <<<"$resp"; then
    mid="$(grep -o '"message_id":[0-9]*' <<<"$resp" | head -1 | cut -d: -f2)"
    describe "$f" "${mid:-?}"
    return 0
  fi

  desc="$(grep -o '"description":"[^"]*"' <<<"$resp" | head -1 | cut -d: -f2- | tr -d '"')"
  c_err "upload failed for $name: ${desc:-unknown error}"
  return 1
}

rc=0

if [[ $SEPARATE -eq 0 && ${#SEND[@]} -gt 1 && ${#SEND[@]} -le $ALBUM_MAX ]]; then
  send_album "${SEND[@]}" || { for f in "${SEND[@]}"; do send_one "$f" || rc=1; done; }
else
  for f in "${SEND[@]}"; do
    send_one "$f" || rc=1
  done
fi

exit $rc
