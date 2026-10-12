#!/usr/bin/env bash
# 零向 ZeroVector：跟随上游 RuoJi6/ARTEX 的一键同步脚本。
#
# 分支约定
#   main   上游镜像分支，只做快进（跟踪 upstream/main），**不要在上面提交**
#   dev    自己的二开分支（跟踪 origin/dev），改动都提交在这里
#
# 用法
#   ./sync-upstream.sh         拉上游 → 快进 main → 把当前分支 rebase 到最新 main
#   ./sync-upstream.sh --push  上面做完后，再用 --force-with-lease 推当前分支到 origin
#
# 说明
#   * rebase 会改写本地提交哈希，推自己 fork 的分支用 --force-with-lease 是安全的；
#     上游 remote 的 push 已在本地配置为 DISABLED，误 push 会被 git 直接拒绝。
#   * 工作区有未提交改动时，靠 rebase.autoStash=true 自动 stash/恢复。
#   * 只想同步 GitHub 上 fork 的 main（本机 main 没分叉时）：gh repo sync kismetpro/ZeroVector
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

UPSTREAM="${ARTEX_UPSTREAM:-upstream}"
MAIN_BRANCH="${ARTEX_MAIN_BRANCH:-main}"
PUSH=0
[ "${1:-}" = "--push" ] && PUSH=1

info(){ printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok(){   printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }
die(){  printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || die "当前目录不是 git 仓库"
git remote get-url "$UPSTREAM" >/dev/null 2>&1 || die "缺少 remote '$UPSTREAM'，先执行：
  git remote add $UPSTREAM https://github.com/RuoJi6/ARTEX.git
  git remote set-url --push $UPSTREAM DISABLED"

current="$(git rev-parse --abbrev-ref HEAD)"
[ "$current" != "HEAD" ] || die "当前处于 detached HEAD，先切回分支再同步"

incoming="0"
if git show-ref --verify --quiet "refs/heads/$MAIN_BRANCH"; then
  incoming="$(git rev-list --count "$MAIN_BRANCH..$UPSTREAM/$MAIN_BRANCH" 2>/dev/null || echo 0)"
fi

info "拉取上游 $UPSTREAM（含标签、清理已删除分支）…"
git fetch --quiet "$UPSTREAM" --prune --tags

if git show-ref --verify --quiet "refs/heads/$MAIN_BRANCH"; then
  local_main="$(git rev-parse "$MAIN_BRANCH")"
  remote_main="$(git rev-parse "$UPSTREAM/$MAIN_BRANCH")"
  if [ "$local_main" = "$remote_main" ]; then
    info "$MAIN_BRANCH 已是最新：$(git log -1 --format='%h %s' "$local_main")"
  elif git merge-base --is-ancestor "$local_main" "$remote_main"; then
    if [ "$current" = "$MAIN_BRANCH" ]; then
      git merge --ff-only "$UPSTREAM/$MAIN_BRANCH" >/dev/null
    else
      git update-ref "refs/heads/$MAIN_BRANCH" "$remote_main"
    fi
    ok "$MAIN_BRANCH 快进 $incoming 个提交 → $(git log -1 --format='%h %s' "$remote_main")"
  elif git merge-base --is-ancestor "$remote_main" "$local_main"; then
    warn "$MAIN_BRANCH 领先上游（本地 $MAIN_BRANCH 上有提交）。约定是不在 $MAIN_BRANCH 上开发，请确认：
  git log --oneline $UPSTREAM/$MAIN_BRANCH..$MAIN_BRANCH"
  else
    die "$MAIN_BRANCH 与上游分叉，需要人工处理：
  git log --oneline --left-right $MAIN_BRANCH...$UPSTREAM/$MAIN_BRANCH"
  fi
else
  warn "本地没有 $MAIN_BRANCH 分支，跳过镜像更新"
fi

if [ "$current" != "$MAIN_BRANCH" ]; then
  info "把 $current rebase 到 $MAIN_BRANCH …"
  git rebase "$MAIN_BRANCH"
  ok "$current 现在基于 $(git log -1 --format='%h %s' "$MAIN_BRANCH")"
fi

if [ "$PUSH" = 1 ]; then
  info "推送 $current → origin/$current（--force-with-lease）…"
  git push --force-with-lease origin "$current"
  ok "已推送 origin/$current"
else
  info "本地已完成。需要同步到 GitHub 时：git push --force-with-lease origin $current"
fi
