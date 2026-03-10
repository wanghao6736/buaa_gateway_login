#!/usr/bin/env bash
#
# BUAA Gateway auto-reconnect script for Linux.
#
# Usage:
#   ./auto_reconnect.sh                  # one-shot check
#   ./auto_reconnect.sh --loop [SECS]    # loop mode (default interval: 600s)
#
# Credentials are read from environment variables:
#   export BUAA_USERNAME="by1234567"
#   export BUAA_PASSWORD="your_password"
# If not set, the Python script will prompt interactively.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/buaa_gateway_login.py"
DEFAULT_INTERVAL=600

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

needs_login() {
    # When not logged in, HTTP requests to external sites are redirected to gw.buaa.edu.cn.
    curl -s -m 5 http://baidu.com 2>/dev/null | grep -q "gw.buaa.edu.cn"
}

do_login() {
    log "Network disconnected — attempting login..."
    if python3 "$PYTHON_SCRIPT"; then
        sleep 2
        if ! needs_login; then
            log "Login successful."
            return 0
        fi
    fi
    log "Login failed, still disconnected."
    return 1
}

run_once() {
    if needs_login; then
        do_login
    else
        log "Network is connected."
    fi
}

run_loop() {
    local interval="${1:-$DEFAULT_INTERVAL}"
    log "Starting auto-reconnect loop (interval: ${interval}s)..."
    while true; do
        run_once || true
        sleep "$interval"
    done
}

case "${1:-}" in
    --loop)
        run_loop "${2:-}"
        ;;
    *)
        run_once
        ;;
esac
