# ZeroVector（本 fork）：与原版 ARTEX 同机并存说明

本 fork 的默认值全部与原版 ARTEX 错开，**同一台电脑上可以同时运行原版和本 fork**，端口、容器、数据互不干扰。

## 与原版的对照

| 项目 | 原版 ARTEX | 本 fork（ZeroVector） |
| --- | --- | --- |
| Web / API 端口 | `8787` | `9787` |
| 流量录制代理端口 | `8788` | `9788` |
| 前端 dev 端口（next dev） | `3000` | `5173` |
| 启动默认值 | `-addr :8787 -proxy 127.0.0.1:8788` | `-addr :9787 -proxy 127.0.0.1:9788` |
| Docker Compose 项目名 | 目录名推导（`artex`） | 固定 `zerovector` |
| Docker 数据卷 | `artex_pgdata` | `zerovector_pgdata` |
| Docker 镜像 | `ruoji6/artex`（远端拉取） | `zerovector:local`（本地构建） |
| 本地 Docker 数据库容器 | `artex-pg` / 5432 | `zerovector-pg` / 5433 |
| JWT 签名密钥 | 安装目录 `jwt.key` | 安装目录 `jwt.key`，或 `ARTEX_KEY_DIR`（Docker 部署用 `./state`） |
| 自更新（一键更新）源 | `RuoJi6/ARTEX` 的 Releases | `kismetpro/ZeroVector` 的 Releases |

> 自更新源必须指向本 fork：若沿用上游，页面上的「一键更新」会把上游发布包装进本 fork 的安装目录，等于直接覆盖二开代码。

## 运行方式

```bash
# 开发（热更新）：后端 :9787 / 代理 :9788 / 前端 http://localhost:5173
./dev.sh

# Docker：本地构建镜像 + 起 compose 项目 zerovector
cp .env.example .env && ${EDITOR:-vi} .env   # 至少填 POSTGRES_PASSWORD
./docker-build.sh                            # build.sh（前端 + 单二进制）+ 镜像 zerovector:local
docker compose up -d                         # → http://localhost:9787

# 更新到最新代码
git pull --ff-only && ./update.sh            # 或 ./docker-build.sh && docker compose up -d --build

# 跟随上游（详见 sync-upstream.sh 头部注释）
./sync-upstream.sh [--push]
```

## 状态文件（各自目录内，互不影响）

- `data/`：流量录制、报表等工作区数据；Docker 部署时挂进容器 `/app/data`
- `state/`：仅 Docker 部署使用的 JWT 密钥目录，挂进 `/app/state`；容器重建/升级不再踢登录（已 gitignore）
- `jwt.key`、`config.json`、`scheduler_state.json`：源码/单二进制运行时的本地状态（已 gitignore）
- PostgreSQL 数据：Docker 卷 `zerovector_pgdata`（原版为 `artex_pgdata`）

## 同步上游后需要复查的地方

这些是本 fork 刻意偏离上游的部分，也是 rebase 冲突高发区：

- `cmd/artex/main.go`：默认端口 `9787` / `9788`，`config.KeyDir()`
- `Dockerfile`：`EXPOSE 9787 9788`、`CMD`、`ARTEX_KEY_DIR=/app/state`、`VOLUME ["/app/state"]`
- `docker-compose.yml`：`name: zerovector`、`image: ${ARTEX_IMAGE:-zerovector:local}` + `build`、宿主端口、`./state` 挂载
- `dev.sh`、`install.sh`、`update.sh`、`docker-build.sh`：端口与「本地构建镜像」流程
- `web/next.config.mjs`、`web/src/proxy.ts`、`web/src/lib/api.ts`：dev 反代/SSE 默认端口
- 品牌相关：`web/src/config/app-config.ts`、`web/src/app/(auth)/{login,setup}/page.tsx`、
  `web/src/app/(main)/_components/sidebar/app-sidebar.tsx`、`web/public/logo.png`、
  `web/src/app/{icon.png,favicon.ico}`、`server/auth.go`（登录用户名）、
  `server/basic_auth.go`、`guard/guard.go`、`cmd/artex/main.go`（banner 与启动日志）
- `selfupdate/github.go`：发布源 `kismetpro/ZeroVector`
- `.env.example`、`.gitignore`：镜像变量说明、`/state/` 与 `docker-compose.override.yml`
- `.github/workflows/release.yml`：镜像/demo 作业的可选化（见下节）

## 发布与「一键更新」

- **发版就是打 tag**：`git tag -a v0.3.23 -m "..." && git push origin v0.3.23`。
  GitHub Actions（`.github/workflows/release.yml`）会构建 Linux/macOS/Windows 五个平台的
  zip + `SHA256SUMS` 并创建 Release；本 fork 未配置镜像变量时自动跳过 Docker Hub 推送。
- **页面「一键更新」指向本仓库 Releases**（`selfupdate.Repo = kismetpro/ZeroVector`）：
  下载对应平台 zip → 校验 SHA256SUMS → 暂存新二进制 → 进程以退出码 75 退出，
  由 `start.sh` / `start.bat` 换装并重新拉起（回滚也走这套）。
- **版本号必须是 `vX.Y.Z`**（工作流会校验）。本地 `git describe` 带 `-dirty` / `-N-gxxxx`
  的开发构建会被判为「不可比较」，因此不会触发更新——这是开发构建的预期行为；
  想验证更新链路就用发布包的二进制（版本号干净）。
- **可选**：连 Docker 镜像一起发 → 仓库变量 `ARTEX_DOCKER_IMAGE=DockerHub用户名/镜像名`
  + secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`，docker 作业会自动启用；
  Vercel demo 默认关闭，需要时设仓库变量 `ARTEX_VERCEL_DEMO=true` 并配置 `VERCEL_TOKEN`。
- 已发布版本：`v0.3.22`（首个 fork 版本，含零向品牌、端口错开、总览固定新版账本等改动）。

## 并行运行的注意点

- 原版用 8787/8788、本 fork 用 9787/9788，两个管理台可同时打开；登录态按端口（origin）隔离。
- 不要共用 `.env`、`data/`、`state/` 或 PostgreSQL 数据卷；需要迁移数据请走备份/恢复，不要直接拷目录。
- 只在本地跑一份时，用原版或本 fork 都行——错开端口不影响单独使用。

## 品牌（界面显示名）

界面上的产品名已全部替换为 **ZeroVector**：登录/初始化页、侧边栏、网页标题（`<title>`）、
设置页各卡片、Basic Auth 提示、拦截提示、通知测试文案、启动日志行、终端 banner，
以及 logo（`web/public/logo.png`、`web/src/app/icon.png`、`web/src/app/favicon.ico`）。

- **登录用户名固定为 `ZeroVector`**（后端 `server/auth.go` 校验；`reset-password.sh` 的提示已同步）
- 以下保留 `artex` 字样，都是功能性标识，改名会破坏兼容，**不要跟着改**：
  环境变量 `ARTEX_*`、Go module 路径 `github.com/Autumn-27/artex`、可执行文件名 `artex`、
  Cookie/localStorage `artex_token`、自更新中间文件 `artex.new` / `artex.old`、
  worker 聊天标记 `ARTEX_WORKER_CHAT`
- README/CHANGELOG 等上游文档仍写 ARTEX，随上游合并，不做改动
