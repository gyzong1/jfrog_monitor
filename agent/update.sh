#!/usr/bin/env bash
# 升级 Node Agent 二进制（保留 agent.yaml）
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    *) echo "不支持的架构: $m" >&2; exit 1 ;;
  esac
}

usage() {
  cat <<EOF
用法: ./update.sh [--from PATH]

升级本机 Agent 二进制，保留 agent.yaml 与监听端口配置。

  --from PATH   从新版本 release/agent 目录复制 bin/（推荐）
  -h, --help    显示帮助

示例:
  ./update.sh --from /opt/jf-monitor-1.2.0-release/agent
  ./update.sh                    # 已手动替换 bin/ 后重启
EOF
}

FROM_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 1 ;;
  esac
done

ARCH="$(detect_arch)"
BIN="$DIR/bin/jf-agent-$ARCH"

if [[ -n "$FROM_DIR" ]]; then
  FROM_DIR="$(cd "$FROM_DIR" && pwd)"
  src="$FROM_DIR/bin/jf-agent-$ARCH"
  if [[ ! -f "$src" ]]; then
    echo "未找到: $src" >&2
    exit 1
  fi
  mkdir -p "$DIR/bin"
  echo "==> 复制 $(basename "$src")"
  cp "$src" "$BIN"
  chmod +x "$BIN"
  [[ -f "$FROM_DIR/VERSION" ]] && cp "$FROM_DIR/VERSION" "$DIR/VERSION"
fi

if [[ ! -x "$BIN" ]]; then
  echo "未找到可执行文件: $BIN" >&2
  exit 1
fi

echo "==> 停止旧 Agent …"
"$DIR/stop.sh" || true

echo "==> 启动新 Agent …"
"$DIR/start.sh"

ver="$(cat "$DIR/VERSION" 2>/dev/null || echo unknown)"
echo "Agent 升级完成，版本: $ver"
