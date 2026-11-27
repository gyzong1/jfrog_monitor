#!/usr/bin/env bash
# 一键启动 Node Agent（自动选择 amd64 / arm64 二进制，默认后台运行）
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    *)
      echo "不支持的架构: $m（仅 linux/amd64、linux/arm64）" >&2
      exit 1
      ;;
  esac
}

ARCH="$(detect_arch)"
BIN="$DIR/bin/jf-agent-$ARCH"
PIDFILE="$DIR/run/jf-agent.pid"
LOG="$DIR/run/jf-agent.log"
CONFIG="${JF_AGENT_CONFIG:-$DIR/agent.yaml}"

if [[ ! -x "$BIN" ]]; then
  echo "未找到二进制: $BIN" >&2
  echo "请先在发布目录执行: VERSION=<版本> ./build.sh  （本目录上一级）" >&2
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  if [[ -f agent.yaml.example ]]; then
    cp agent.yaml.example "$CONFIG"
    echo "已从 agent.yaml.example 创建 $CONFIG，请按需修改后重启"
  else
    echo "缺少配置文件: $CONFIG" >&2
    exit 1
  fi
fi

mkdir -p run/tmp
# PyInstaller onefile 会解压到 TMPDIR；CentOS 上 /tmp 常带 noexec，导致:
#   libz.so.1: failed to map segment from shared object
export TMPDIR="$DIR/run/tmp"
export TEMP="$TMPDIR"
export TMP="$TMPDIR"
export JF_AGENT_CONFIG="$CONFIG"

# 前台运行（调试用）
if [[ "${1:-}" == "--foreground" ]] || [[ "${1:-}" == "-f" ]]; then
  exec "$BIN"
fi

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Agent 已在运行 (pid $(cat "$PIDFILE"))"
  exit 0
fi

nohup env TMPDIR="$TMPDIR" TEMP="$TMPDIR" TMP="$TMPDIR" JF_AGENT_CONFIG="$CONFIG" \
  "$BIN" >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"
echo "Agent 已后台启动 pid=$(cat "$PIDFILE")"
echo "日志: $LOG"
echo "指标: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 127.0.0.1):$(grep -E '^port:' "$CONFIG" | awk '{print $2}' || echo 9105)/metrics"
echo "停止: ./stop.sh"
