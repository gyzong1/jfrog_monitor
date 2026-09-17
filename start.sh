#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# .env 可选（仅高级项如 JF_MONITOR_PORT）；Artifactory 在启动后于 UI 设置页配置
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
if [[ -z "${JF_MONITOR_IMAGE:-}" && -f VERSION ]]; then
  export JF_MONITOR_IMAGE="jf-monitor:$(tr -d '[:space:]' < VERSION)"
fi

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "请先安装并启动 Docker" >&2
  exit 1
fi

mkdir -p "$ROOT/data" "$ROOT/config"

FORCE_LOAD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --load|--force-load) FORCE_LOAD=1; shift ;;
    -h|--help)
      cat <<EOF
用法: ./start.sh [--load]

  （默认）只启动容器。本机已有镜像时绝不 docker load，避免用安装目录里
         过期的 images/*.tar.gz 覆盖「升级时刚导入的好镜像」。
  --load   强制从本目录 images/ 重新导入后再启动。

首次安装（本机还没有镜像）会自动从 images/ 导入一次。
版本升级请用: ./update-server.sh --from <新包目录>
EOF
      exit 0
      ;;
    *) echo "未知参数: $1（支持 --load）" >&2; exit 1 ;;
  esac
done

host_arch_suffix() {
  case "$(uname -m)" in
    x86_64|amd64) echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    *) echo "linux-amd64" ;;
  esac
}

pick_offline_image() {
  local dir="$1"
  local ver
  ver="$(tr -d '[:space:]' < "$dir/VERSION" 2>/dev/null || echo "")"
  local suffix
  suffix="$(host_arch_suffix)"
  if [[ -z "$ver" ]]; then
    return 1
  fi
  if [[ -f "$dir/images/jf-monitor-${ver}-${suffix}.tar.gz" ]]; then
    echo "$dir/images/jf-monitor-${ver}-${suffix}.tar.gz"
    return 0
  fi
  if [[ -f "$dir/images/jf-monitor-${ver}-local.tar.gz" ]]; then
    echo "$dir/images/jf-monitor-${ver}-local.tar.gz"
    return 0
  fi
  echo "未找到与 VERSION=${ver} 匹配的离线镜像（需要 images/jf-monitor-${ver}-${suffix}.tar.gz）。" >&2
  echo "当前 images/ 内容:" >&2
  ls -la "$dir/images/" >&2 || true
  return 1
}

IMAGE="${JF_MONITOR_IMAGE:-jf-monitor:latest}"

if [[ "$FORCE_LOAD" -eq 1 ]]; then
  if img="$(pick_offline_image "$ROOT")"; then
    echo "==> 强制导入离线镜像 ($(host_arch_suffix)): $img"
    docker load < "$img"
  else
    exit 1
  fi
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if img="$(pick_offline_image "$ROOT")"; then
    echo "==> 首次导入离线镜像 ($(host_arch_suffix)): $img"
    docker load < "$img"
  else
    echo "未找到本地镜像 $IMAGE，且 images/ 下无可用离线包" >&2
    echo "升级请用: ./update-server.sh --from <新版本目录>" >&2
    exit 1
  fi
fi

docker compose up -d
echo ""
echo "JF Monitor → http://localhost:${JF_MONITOR_PORT:-8080}"
echo "Artifactory 节点请在浏览器「设置」页配置"
echo "停止: ./stop.sh"
