#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker compose down --remove-orphans 2>/dev/null || true
  echo "Server 已停止"
else
  echo "Docker 未运行，跳过"
fi
