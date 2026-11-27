#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$DIR/run/jf-agent.pid"

if [[ -f "$PIDFILE" ]]; then
  pid="$(cat "$PIDFILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 0.5
    kill -9 "$pid" 2>/dev/null || true
    echo "已停止 Agent (pid $pid)"
  else
    echo "Agent 未在运行"
  fi
  rm -f "$PIDFILE"
else
  # 尝试按进程名停止
  pkill -f "jf-agent-linux" 2>/dev/null && echo "已停止 Agent" || echo "无运行中的 Agent"
fi
