#!/usr/bin/env bash
# 在本目录构建安装产物（Server 离线镜像 + Agent 二进制 + dist/ 安装包）
# 需完整源码仓库（本目录为仓库中的 release/）。
#
# 用法:
#   VERSION=1.0.0 ./build.sh
#   PLATFORMS=linux/amd64 VERSION=1.0.0 ./build.sh
#   DOCKER_REGISTRY_MIRROR=https://docker.m.daocloud.io VERSION=1.0.0 ./build.sh
#
# 归档输出: ./dist/jf-monitor-<VERSION>-release.tar.gz
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

find_source_root() {
  if [[ -n "${JF_MONITOR_SOURCE:-}" && -x "${JF_MONITOR_SOURCE}/scripts/build-release.sh" ]]; then
    echo "$JF_MONITOR_SOURCE"
    return 0
  fi
  # 开发仓库：release/ 的上一级
  if [[ -x "$HERE/../scripts/build-release.sh" ]]; then
    echo "$(cd "$HERE/.." && pwd)"
    return 0
  fi
  return 1
}

if ! ROOT="$(find_source_root)"; then
  echo "未找到源码，无法构建。" >&2
  echo "" >&2
  echo "  本脚本需要完整仓库（含 Dockerfile、backend/、frontend/、agent/、scripts/）。" >&2
  echo "  若已解压官方安装包（含 images/ 与 agent/bin/），直接执行 ./start.sh 即可，无需构建。" >&2
  echo "  从源码构建：在仓库的 release/ 目录执行本脚本，或设置：" >&2
  echo "    JF_MONITOR_SOURCE=/path/to/jfrog_monitor VERSION=1.0.0 ./build.sh" >&2
  exit 1
fi

if [[ -z "${VERSION:-}" && -f "$HERE/VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"
fi
VERSION="${VERSION:-$(date +%Y%m%d)}"
export VERSION

# 公开目录仅构建标准安装包
export EDITIONS="${EDITIONS:-release}"

# 本层构建的 tar.gz / RELEASES.md 写到 release/dist/
export DIST="${DIST:-$HERE/dist}"
mkdir -p "$DIST"

echo "==> 源码根目录: $ROOT"
echo "==> VERSION=$VERSION"
echo "==> PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64}"
echo "==> 归档目录: $DIST"
exec "$ROOT/scripts/build-release.sh"
