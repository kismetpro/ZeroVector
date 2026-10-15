#!/usr/bin/env bash
# 本 fork（ZeroVector）本地构建 Docker 镜像。
#
# Dockerfile 不在镜像里编译代码，只接收预编译好的 dist/<arch>/artex，所以这里：
#   1) ./build.sh 产出内嵌前端的单二进制（dist/artex-<os>-<arch>/artex）
#   2) 复制成 Dockerfile 期望的路径 dist/<TARGETARCH>/artex
#   3) docker build 出 ${ARTEX_LOCAL_IMAGE:-zerovector:local}
#
# 依赖已在 node_modules 里时，可用 ARTEX_SKIP_NPM_CI=1 ./docker-build.sh 跳过 npm ci。
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

info(){ printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok(){   printf '\033[32m[+]\033[0m %s\n' "$*"; }
die(){  printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "不支持的架构：$(uname -m)（仅 amd64 / arm64）" ;;
esac

IMAGE="${ARTEX_LOCAL_IMAGE:-zerovector:local}"

info "构建内嵌前端的单二进制…"
./build.sh

src="dist/artex-linux-${ARCH}/artex"
[ -x "$src" ] || die "未找到构建产物 $src"
mkdir -p "dist/${ARCH}"
cp "$src" "dist/${ARCH}/artex"
ok "已就位：dist/${ARCH}/artex"

info "构建镜像 ${IMAGE} …"
docker build -t "$IMAGE" .
ok "镜像就绪：${IMAGE}"
info "启动：docker compose up -d（首次部署可跑 ./install.sh）"
