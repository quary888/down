#!/usr/bin/env bash
set -euo pipefail

# codex_mgr.sh：在 tmux 中托管 codex，SSH 断开可重连继续
# 依赖：tmux、codex（@openai/codex）
#
# 用法：
#   ./codex_mgr.sh start        # 在当前目录启动/进入 codex 会话
#   ./codex_mgr.sh attach       # 进入当前目录的 codex 会话
#   ./codex_mgr.sh list         # 列出所有 codex tmux 会话
#   ./codex_mgr.sh stop         # 停止当前目录的 codex 会话
#
# 说明：
# - 会话名基于当前目录路径 hash，做到“一目录一会话”
# - start：不存在则创建并启动 codex；存在则直接 attach

get_mulu_hash() {
  # 中文备注：生成当前目录的稳定 hash，用于 tmux session 命名
  local dir
  dir="$(pwd -P)"
  # sha1sum 输出：hash + 空格 + "-"
  echo -n "${dir}" | sha1sum | awk '{print $1}'
}

get_huihua_name() {
  # 中文备注：构造 tmux 会话名
  local hash
  hash="$(get_mulu_hash)"
  echo "codex_${hash}"
}

check_yilai() {
  # 中文备注：检查依赖是否存在
  command -v tmux >/dev/null 2>&1 || { echo "缺少依赖：tmux"; exit 1; }
  command -v codex >/dev/null 2>&1 || { echo "缺少依赖：codex（请先安装 @openai/codex）"; exit 1; }
}

start_huihua() {
  # 中文备注：启动/进入当前目录的 codex tmux 会话
  local name
  name="$(get_huihua_name)"

  if tmux has-session -t "${name}" >/dev/null 2>&1; then
    tmux attach -t "${name}"
    return 0
  fi

  # -d：后台创建；-c：工作目录；exec bash 保证 codex 退出后窗口还在，便于看日志/重启
  tmux new-session -d -s "${name}" -c "$(pwd -P)" "codex; echo; echo '[codex 已退出]'; exec bash"
  tmux attach -t "${name}"
}

attach_huihua() {
  # 中文备注：进入当前目录的 codex tmux 会话（不存在则报错提示）
  local name
  name="$(get_huihua_name)"

  if ! tmux has-session -t "${name}" >/dev/null 2>&1; then
    echo "当前目录没有 codex 会话：${name}"
    echo "可先执行：./codex_mgr.sh start"
    exit 1
  fi

  tmux attach -t "${name}"
}

list_huihua() {
  # 中文备注：列出所有 codex_* tmux 会话
  tmux ls 2>/dev/null | grep -E '^codex_[0-9a-f]{40}:' || true
}

stop_huihua() {
  # 中文备注：停止当前目录的 codex tmux 会话
  local name
  name="$(get_huihua_name)"

  if ! tmux has-session -t "${name}" >/dev/null 2>&1; then
    echo "当前目录没有 codex 会话：${name}"
    exit 1
  fi

  tmux kill-session -t "${name}"
  echo "已停止：${name}"
}

main() {
  check_yilai

  local cmd="${1:-}"
  case "${cmd}" in
    start)  start_huihua ;;
    attach) attach_huihua ;;
    list)   list_huihua ;;
    stop)   stop_huihua ;;
    *)
      echo "用法：$0 {start|attach|list|stop}"
      exit 1
      ;;
  esac
}

main "$@"
