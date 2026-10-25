#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Local Telegram Bot API server manager
#
# The cloud Bot API caps uploads at 50 MiB. A self-hosted server in --local
# mode raises that to 2000 MiB, so the build script can post the APK as a
# normal document straight into the chat.
#
# Usage:
#   scripts/tg-bot-api.sh start     # start in background (idempotent)
#   scripts/tg-bot-api.sh stop
#   scripts/tg-bot-api.sh status
#   scripts/tg-bot-api.sh restart
#   scripts/tg-bot-api.sh logs
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${TG_BOT_API_PREFIX:-/root/tg-bot-api/install}"
BIN="$PREFIX/bin/telegram-bot-api"
DATA_DIR="${TG_BOT_API_DIR:-/root/tg-bot-api/data}"
PORT="${TG_BOT_API_PORT:-8081}"
LOG="${TG_BOT_API_LOG:-/tmp/telegram-bot-api.log}"
PIDFILE="${TG_BOT_API_PID:-/tmp/telegram-bot-api.pid}"

# credentials: .telegram.env (gitignored) then environment
if [[ -f "$ROOT/.telegram.env" ]]; then
  set -a; . "$ROOT/.telegram.env"; set +a
fi

c_info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }

running() {
  [[ -f "$PIDFILE" ]] || return 1
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# the server may be started by systemd instead of this script, so fall back
# to probing the port rather than trusting our own pid file
managed_by_systemd() {
  command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet telegram-bot-api 2>/dev/null
}

healthy() {
  curl -fsS --max-time 3 "http://127.0.0.1:$PORT/bot${TELEGRAM_BOT_TOKEN:-x}/getMe" >/dev/null 2>&1
}

do_start() {
  if running && healthy; then c_ok "bot api server already running (port $PORT)"; return 0; fi
  if managed_by_systemd && healthy; then
    c_ok "bot api server already running under systemd (port $PORT)"; return 0
  fi
  [[ -x "$BIN" ]] || { c_err "telegram-bot-api not built at $BIN (run scripts/tg-bot-api-build.sh)"; return 1; }

  local api_id="${TG_API_ID:-11535358}"
  local api_hash="${TG_API_HASH:-33d372962fadb01df47e6ceed4e33cd6}"
  mkdir -p "$DATA_DIR"

  c_info "starting local bot api server on port $PORT (local mode, 2000 MiB limit)"
  nohup "$BIN" \
    --api-id="$api_id" \
    --api-hash="$api_hash" \
    --local \
    --http-port="$PORT" \
    --dir="$DATA_DIR" \
    --log="$LOG" \
    --verbosity=1 \
    >/dev/null 2>&1 &
  echo $! > "$PIDFILE"

  for _ in $(seq 1 40); do
    sleep 0.5
    if healthy; then c_ok "bot api server ready on http://127.0.0.1:$PORT"; return 0; fi
    if ! running; then c_err "server exited during startup, see $LOG"; tail -n 20 "$LOG" 2>/dev/null; return 1; fi
  done
  c_err "server did not become healthy in 20s, see $LOG"; return 1
}

do_stop() {
  if managed_by_systemd; then
    c_warn "server is managed by systemd; use: systemctl stop telegram-bot-api"
    return 0
  fi
  if running; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    for _ in $(seq 1 20); do sleep 0.25; running || break; done
    rm -f "$PIDFILE"
    c_ok "bot api server stopped"
  else
    rm -f "$PIDFILE"
    c_ok "bot api server not running"
  fi
}

do_status() {
  if managed_by_systemd; then
    if healthy; then c_ok "running under systemd on port $PORT"; else
      printf '\033[1;33m[!]\033[0m systemd unit active but not responding on port %s\n' "$PORT"; fi
  elif running && healthy; then
    c_ok "running on port $PORT (pid $(cat "$PIDFILE"))"
  elif running; then
    printf '\033[1;33m[!]\033[0m process alive but not responding on port %s\n' "$PORT"
  else
    printf '\033[1;33m[!]\033[0m not running\n'
  fi
}

case "${1:-status}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; do_start ;;
  status)  do_status ;;
  logs)    tail -n 50 "$LOG" 2>/dev/null || echo "no log at $LOG" ;;
  *) echo "usage: $0 {start|stop|restart|status|logs}" >&2; exit 2 ;;
esac
