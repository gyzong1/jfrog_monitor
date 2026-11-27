#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SERVER_VER="$(cat VERSION 2>/dev/null || echo unknown)"
AGENT_VER="$(cat agent/VERSION 2>/dev/null || echo "$SERVER_VER")"

echo "JF Monitor 发布包版本"
echo "  Server:  $SERVER_VER  (镜像: ${JF_MONITOR_IMAGE:-jf-monitor:${SERVER_VER}})"
echo "  Agent:   $AGENT_VER"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  running="$(docker inspect -f '{{.Config.Image}}' jf-monitor 2>/dev/null || true)"
  [[ -n "$running" ]] && echo "  运行中:  $running"
fi

if [[ -f agent/run/jf-agent.pid ]] && kill -0 "$(cat agent/run/jf-agent.pid)" 2>/dev/null; then
  echo "  Agent:   运行中 (pid $(cat agent/run/jf-agent.pid))"
fi
