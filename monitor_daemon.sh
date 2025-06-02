#!/bin/bash

# Server Health Check Daemon
# Companion script for continuous monitoring

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/InfoRaport.sh"
PID_FILE="${SCRIPT_DIR}/monitor.pid"
LOG_FILE="${SCRIPT_DIR}/monitor.log"

start_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Monitor daemon is already running (PID: $pid)"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    echo "Starting server monitor daemon..."
    nohup bash "$MAIN_SCRIPT" --monitor > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "Monitor daemon started (PID: $!)"
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            echo "Monitor daemon stopped"
        else
            echo "Monitor daemon is not running"
            rm -f "$PID_FILE"
        fi
    else
        echo "Monitor daemon is not running"
    fi
}

status_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Monitor daemon is running (PID: $pid)"
            return 0
        else
            echo "Monitor daemon is not running (stale PID file)"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "Monitor daemon is not running"
        return 1
    fi
}

case "$1" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon
        ;;
    status)
        status_daemon
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
