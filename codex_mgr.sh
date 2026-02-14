#!/usr/bin/env bash
set -euo pipefail

# codex_mgr.sh：tmux 托管 codex（不按目录过滤），用独特前缀 codexmgr__ 管理任务
# 交互提示全部走 stderr；read 从 /dev/tty；避免 stdout 被命令替换污染
#
# 用法：
#   bash codex_mgr.sh start
#   bash codex_mgr.sh attach
#   bash codex_mgr.sh list
#   bash codex_mgr.sh stop

PREFIX="codexmgr__"

check_yilai() {
  # 中文备注：检查依赖是否存在
  command -v tmux >/dev/null 2>&1 || { echo "缺少依赖：tmux" >&2; exit 1; }
  command -v codex >/dev/null 2>&1 || { echo "缺少依赖：codex（请先安装 @openai/codex）" >&2; exit 1; }
  command -v date >/dev/null 2>&1 || { echo "缺少依赖：date" >&2; exit 1; }
  command -v awk >/dev/null 2>&1 || { echo "缺少依赖：awk" >&2; exit 1; }
  command -v tr >/dev/null 2>&1 || { echo "缺少依赖：tr" >&2; exit 1; }
  command -v sed >/dev/null 2>&1 || { echo "缺少依赖：sed" >&2; exit 1; }
}

sanitize_renwu_ming() {
  # 中文备注：清洗任务名为 tmux 安全字符（把非 [A-Za-z0-9._-] 统一替换为 '_'）
  local s="${1:-}"
  echo "${s}" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_//;s/_$//'
}

get_shijian_stamp() {
  # 中文备注：生成时间戳，精确到秒
  date +"%Y%m%d_%H%M%S"
}

get_suiji_short() {
  # 中文备注：生成短随机标识（无需额外依赖）
  printf "%04x%04x" $((RANDOM & 0xffff)) $((RANDOM & 0xffff))
}

build_session_name() {
  # 中文备注：构造 session 名：codexmgr__<任务名>__<时间戳>__<短随机>
  local renwu_raw="${1:-}"
  local renwu
  renwu="$(sanitize_renwu_ming "${renwu_raw}")"
  if [[ -z "${renwu}" ]]; then
    echo "任务名字无效：清洗后为空。请包含字母/数字。" >&2
    exit 1
  fi
  echo "${PREFIX}${renwu}__$(get_shijian_stamp)__$(get_suiji_short)"
}

parse_renwu_from_session() {
  # 中文备注：从 session 名解析任务名（只对 codexmgr__ 前缀生效）
  local name="${1:-}"
  local rest
  rest="${name#${PREFIX}}"
  echo "${rest}" | awk -F'__' '{print $1}'
}

format_shijian_renlei() {
  # 中文备注：把 epoch 秒转换为可读时间
  local epoch="$1"
  date -d "@${epoch}" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "${epoch}"
}

collect_sessions() {
  # 中文备注：收集所有 codexmgr__ 会话
  # 输出：name\tcreated\twindows\tattached\trenwu
  local fmt lines
  fmt="#{session_name}\t#{session_created}\t#{session_windows}\t#{session_attached}"

  tmux list-sessions >/dev/null 2>&1 || return 0

  lines="$(tmux list-sessions -F "${fmt}" 2>/dev/null | awk -F'\t' -v pfx="${PREFIX}" '$1 ~ ("^" pfx) {print}')"
  if [[ -n "${lines}" ]]; then
    while IFS=$'\t' read -r name created windows attached; do
      local renwu
      renwu="$(parse_renwu_from_session "${name}")"
      echo -e "${name}\t${created}\t${windows}\t${attached}\t${renwu}"
    done <<< "${lines}"
  fi
}

print_list() {
  # 中文备注：打印任务列表（带序号）
  local lines=("$@")
  local i=1
  echo "序号 | 任务名 | 会话名 | 创建时间 | 窗口数 | 已连接"
  echo "-----|--------|--------|----------|--------|--------"
  for line in "${lines[@]}"; do
    IFS=$'\t' read -r name created windows attached renwu <<< "${line}"
    local created_h attached_txt
    created_h="$(format_shijian_renlei "${created}")"
    attached_txt="否"
    [[ "${attached}" == "1" ]] && attached_txt="是"
    echo "${i} | ${renwu} | ${name} | ${created_h} | ${windows} | ${attached_txt}"
    i=$((i+1))
  done
}

select_xuhao() {
  # 中文备注：从 1..N 选择一个序号
  # 重要：提示输出到 stderr；stdout 只输出纯数字（给命令替换捕获）
  local n="$1"
  local input=""
  while true; do
    echo -n "请输入序号(1-${n})：" >&2
    IFS= read -r input </dev/tty
    if [[ "${input}" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= n )); then
      echo "${input}"
      return 0
    fi
    echo "无效输入：${input}" >&2
  done
}

read_renwu_name_from_tty() {
  # 中文备注：从 /dev/tty 读取任务名，避免 stdin 被占用导致交互异常
  local renwu_raw=""
  echo -n "请输入任务名字：" >&2
  IFS= read -r renwu_raw </dev/tty
  echo "${renwu_raw}"
}

start_task() {
  # 中文备注：交互式输入任务名后创建并进入
  local renwu_raw
  renwu_raw="$(read_renwu_name_from_tty)"

  if [[ -z "${renwu_raw}" ]]; then
    echo "任务名字不能为空。" >&2
    exit 1
  fi

  local session_name renwu
  session_name="$(build_session_name "${renwu_raw}")"
  renwu="$(parse_renwu_from_session "${session_name}")"

  tmux new-session -d -s "${session_name}" "codex; echo; echo '[codex 已退出]'; exec bash"

  echo "已创建任务：${renwu}" >&2
  tmux attach -t "${session_name}"
}

attach_task() {
  # 中文备注：进入任务：1 个则直接进；多个则选序号
  mapfile -t items < <(collect_sessions)
  local cnt="${#items[@]}"

  if (( cnt == 0 )); then
    echo "未找到 ${PREFIX} 前缀的 codex 会话。可先执行：bash codex_mgr.sh start" >&2
    exit 1
  fi

  local name renwu
  if (( cnt == 1 )); then
    IFS=$'\t' read -r name _created _windows _attached renwu <<< "${items[0]}"
    echo "进入任务：${renwu}" >&2
    tmux attach -t "${name}"
    return 0
  fi

  print_list "${items[@]}"
  local xuhao idx
  xuhao="$(select_xuhao "${cnt}")"
  idx=$((xuhao-1))
  IFS=$'\t' read -r name _created _windows _attached renwu <<< "${items[${idx}]}"
  echo "进入任务：${renwu}" >&2
  tmux attach -t "${name}"
}

list_task() {
  # 中文备注：列出全部任务
  mapfile -t items < <(collect_sessions)
  local cnt="${#items[@]}"
  if (( cnt == 0 )); then
    echo "未找到 ${PREFIX} 前缀的 codex 会话。" >&2
    return 0
  fi
  print_list "${items[@]}"
}

stop_task() {
  # 中文备注：停止任务：1 个则直接停；多个则选序号
  mapfile -t items < <(collect_sessions)
  local cnt="${#items[@]}"

  if (( cnt == 0 )); then
    echo "未找到 ${PREFIX} 前缀的 codex 会话。" >&2
    exit 1
  fi

  local name renwu
  if (( cnt == 1 )); then
    IFS=$'\t' read -r name _created _windows _attached renwu <<< "${items[0]}"
  else
    print_list "${items[@]}"
    local xuhao idx
    xuhao="$(select_xuhao "${cnt}")"
    idx=$((xuhao-1))
    IFS=$'\t' read -r name _created _windows _attached renwu <<< "${items[${idx}]}"
  fi

  tmux kill-session -t "${name}"
  echo "已停止任务：${renwu}" >&2
}

main() {
  check_yilai

  case "${1:-}" in
    start)  start_task ;;
    attach) attach_task ;;
    list)   list_task ;;
    stop)   stop_task ;;
    *)
      echo "用法：bash codex_mgr.sh {start|attach|list|stop}" >&2
      exit 1
      ;;
  esac
}

main "$@"
