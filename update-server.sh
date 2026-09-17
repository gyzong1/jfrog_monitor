#!/usr/bin/env bash
# 升级 Server（保留 config/ 与 data/，仅替换镜像）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${JF_MONITOR_IMAGE:-}" && -f VERSION ]]; then
  export JF_MONITOR_IMAGE="jf-monitor:$(tr -d '[:space:]' < VERSION)"
fi

VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo unknown)"
TARGET_IMAGE="${JF_MONITOR_IMAGE:-jf-monitor:${VERSION}}"

host_arch_suffix() {
  case "$(uname -m)" in
    x86_64|amd64) echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    *) echo "linux-amd64" ;;
  esac
}

# 只接受与 VERSION 匹配的离线包，禁止回落到旧版镜像。
pick_offline_image() {
  local dir="$1"
  local ver="${2:-}"
  local suffix
  suffix="$(host_arch_suffix)"
  if [[ -z "$ver" && -f "$dir/VERSION" ]]; then
    ver="$(tr -d '[:space:]' < "$dir/VERSION")"
  fi
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
  echo "当前 images/:" >&2
  ls -la "$dir/images/" >&2 || true
  return 1
}

# 包内 EDITION 文件首行：artifactory | internal（旧包可能为 xray）
read_edition_id() {
  local dir="$1"
  if [[ -f "$dir/EDITION" ]]; then
    head -n 1 "$dir/EDITION" | tr -d '[:space:]'
    return 0
  fi
  # 兼容旧包：无 EDITION 时按 VERSION 后缀推断
  local ver
  ver="$(tr -d '[:space:]' < "$dir/VERSION" 2>/dev/null || echo "")"
  case "$ver" in
    *-internal) echo "internal" ;;
    *-xray) echo "xray" ;;
    *) echo "artifactory" ;;
  esac
}

usage() {
  cat <<EOF
用法: ./update-server.sh [选项]

升级 JF Monitor Server 至 release/VERSION 对应版本（默认 ${VERSION}）。
config/ 与 data/ 会保留，节点配置、Dashboard、历史指标不受影响。
仅允许同档升级（artifactory / internal），防止功能档位被误换。

选项:
  --from PATH    从新版本目录导入（自动按本机架构 load 镜像并同步默认 Dashboard）
  -h, --help     显示帮助

示例:
  ./update-server.sh
  ./update-server.sh --from ../jf-monitor-1.2.0-release
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

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "请先安装并启动 Docker" >&2
  exit 1
fi

if [[ -n "$FROM_DIR" ]]; then
  FROM_DIR="$(cd "$FROM_DIR" && pwd)"
  cur_ed="$(read_edition_id "$ROOT")"
  new_ed="$(read_edition_id "$FROM_DIR")"
  if [[ -n "$cur_ed" && -n "$new_ed" && "$cur_ed" != "$new_ed" ]]; then
    echo "错误: 档位不一致，拒绝升级（当前=${cur_ed}，新包=${new_ed}）。" >&2
    echo "请使用同档安装包（artifactory / internal）。" >&2
    exit 1
  fi
  if [[ -f "$FROM_DIR/VERSION" ]]; then
    VERSION="$(tr -d '[:space:]' < "$FROM_DIR/VERSION")"
    cp "$FROM_DIR/VERSION" "$ROOT/VERSION"
  fi
  # 离线包升级：本地 jf-monitor:<VERSION> 跟包走；仅当 JF_MONITOR_IMAGE 含 registry 路径（带 /）时保留
  if [[ -z "${JF_MONITOR_IMAGE:-}" || "$JF_MONITOR_IMAGE" != *"/"* ]]; then
    TARGET_IMAGE="jf-monitor:${VERSION}"
  else
    TARGET_IMAGE="$JF_MONITOR_IMAGE"
  fi
  if img="$(pick_offline_image "$FROM_DIR" "$VERSION")"; then
    echo "==> 导入离线镜像 ($(host_arch_suffix)): $img"
    docker load < "$img"
  else
    echo "错误: 未在 $FROM_DIR/images/ 找到与 VERSION=$VERSION 匹配的离线镜像，拒绝升级" >&2
    exit 1
  fi
  # 必须把新包 images/ 同步进安装目录，否则下次 start.sh --load 或误 load 会装回旧 tar
  echo "==> 同步离线镜像文件 → $ROOT/images/"
  mkdir -p "$ROOT/images"
  shopt -s nullglob
  for f in "$FROM_DIR/images"/jf-monitor-*.tar.gz; do
    cp -f "$f" "$ROOT/images/"
  done
  shopt -u nullglob
  # 同步启停/升级脚本、compose、EDITION
  # 注意：不要在运行中覆盖本脚本自身，否则 bash 继续读文件会错位报 syntax error
  for s in start.sh stop.sh version.sh docker-compose.yml EDITION; do
    if [[ -f "$FROM_DIR/$s" ]]; then
      cp -f "$FROM_DIR/$s" "$ROOT/$s"
      [[ "$s" == *.sh ]] && chmod +x "$ROOT/$s"
    fi
  done
  if [[ -f "$FROM_DIR/update-server.sh" ]]; then
    cp -f "$FROM_DIR/update-server.sh" "$ROOT/update-server.sh.new"
    chmod +x "$ROOT/update-server.sh.new"
  fi
  if [[ -d "$FROM_DIR/config/dashboards" ]]; then
    echo "==> 同步默认 Dashboard（保留 custom-*.yaml）…"
    mkdir -p "$ROOT/config/dashboards"
    for f in "$FROM_DIR/config/dashboards/"*.yaml; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"
      [[ "$base" == custom-* ]] && continue
      cp "$f" "$ROOT/config/dashboards/$base"
    done
    # 新包没有的默认 Dashboard 删掉
    shopt -s nullglob
    for f in "$ROOT/config/dashboards/"*.yaml; do
      base="$(basename "$f")"
      [[ "$base" == custom-* ]] && continue
      [[ -f "$FROM_DIR/config/dashboards/$base" ]] || rm -f "$f"
    done
    shopt -u nullglob
  fi
fi

export JF_MONITOR_IMAGE="$TARGET_IMAGE"
echo "==> 升级 Server → $TARGET_IMAGE"

if [[ -z "$FROM_DIR" ]]; then
  if img="$(pick_offline_image "$ROOT" "$VERSION")"; then
    echo "==> 导入离线镜像 ($(host_arch_suffix)): $img"
    docker load < "$img"
  else
    echo "警告: 未找到离线镜像包，将使用已有镜像 $TARGET_IMAGE" >&2
  fi
fi

# 在线 Registry：显式设置 JF_MONITOR_IMAGE 时尝试 pull
if [[ "$JF_MONITOR_IMAGE" == *"/"* ]]; then
  echo "==> 拉取镜像 …"
  docker compose pull || true
fi

docker compose up -d --force-recreate --remove-orphans
echo ""
echo "升级完成 → http://localhost:${JF_MONITOR_PORT:-8080}"
echo "当前版本: $(tr -d '[:space:]' < VERSION 2>/dev/null || echo unknown)"
echo "使用镜像: $JF_MONITOR_IMAGE"
docker compose ps

# 最后再替换自身，供下次升级使用
if [[ -f "$ROOT/update-server.sh.new" ]]; then
  mv -f "$ROOT/update-server.sh.new" "$ROOT/update-server.sh"
fi
