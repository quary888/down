#!/usr/bin/env bash
set -euo pipefail

# =========================
# Debian: codexcli 安装 + 菜单脚本
# - 启动后默认检查/安装依赖
# - 菜单 1：设置 API KEY + 强制 codex 走自定义 provider
# - 菜单 2：清除菜单 1 写入的配置，恢复为可官方登录的初始状态
# =========================

# 中文备注：统一输出
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_err()  { echo "[ERR ] $*" >&2; }

# 中文备注：统一删除指定 marker 区块，保证幂等更新
delete_marker_qukuai_wenjian() {
  local file_lujing="$1"
  local begin_biaoji="$2"
  local end_biaoji="$3"

  if [[ ! -f "${file_lujing}" ]]; then
    return 0
  fi

  local tmp_wenjian
  tmp_wenjian="$(mktemp)"

  awk -v begin_biaoji="${begin_biaoji}" -v end_biaoji="${end_biaoji}" '
    BEGIN { skip_zhuangtai = 0 }
    index($0, begin_biaoji) { skip_zhuangtai = 1; next }
    index($0, end_biaoji) { skip_zhuangtai = 0; next }
    skip_zhuangtai == 0 { print }
  ' "${file_lujing}" > "${tmp_wenjian}"

  mv "${tmp_wenjian}" "${file_lujing}"
}

# 中文备注：按正则删除匹配行，兼容清理没有 marker 的历史残留配置
delete_regex_hang_wenjian() {
  local file_lujing="$1"
  local hang_zhengze="$2"

  if [[ ! -f "${file_lujing}" ]]; then
    return 0
  fi

  local tmp_wenjian
  tmp_wenjian="$(mktemp)"

  awk -v hang_zhengze="${hang_zhengze}" '
    $0 !~ hang_zhengze { print }
  ' "${file_lujing}" > "${tmp_wenjian}"

  mv "${tmp_wenjian}" "${file_lujing}"
}

# 中文备注：按 TOML 表头删除整个区块，直到下一个表头或文件结束
delete_toml_biao_qukuai_wenjian() {
  local file_lujing="$1"
  local biao_tou_zhengze="$2"

  if [[ ! -f "${file_lujing}" ]]; then
    return 0
  fi

  local tmp_wenjian
  tmp_wenjian="$(mktemp)"

  awk -v biao_tou_zhengze="${biao_tou_zhengze}" '
    BEGIN { skip_zhuangtai = 0 }
    skip_zhuangtai == 0 && $0 ~ biao_tou_zhengze { skip_zhuangtai = 1; next }
    skip_zhuangtai == 1 && $0 ~ /^\[/ { skip_zhuangtai = 0 }
    skip_zhuangtai == 0 { print }
  ' "${file_lujing}" > "${tmp_wenjian}"

  mv "${tmp_wenjian}" "${file_lujing}"
}

# 中文备注：若文件只剩空白，则直接删除，恢复更接近初始状态
cleanup_kong_wenjian() {
  local file_lujing="$1"

  if [[ ! -f "${file_lujing}" ]]; then
    return 0
  fi

  if [[ -z "$(tr -d '[:space:]' < "${file_lujing}")" ]]; then
    rm -f "${file_lujing}"
  fi
}

# 中文备注：转义 TOML 基本字符串
escape_toml_jiben_zifuchuan() {
  local raw_neirong="$1"
  local escaped_neirong

  escaped_neirong="${raw_neirong//\\/\\\\}"
  escaped_neirong="${escaped_neirong//\"/\\\"}"

  echo "${escaped_neirong}"
}

# 中文备注：检查是否为 Debian/Ubuntu 体系（此脚本按 Debian 写）
check_debian_xitong() {
  if [[ ! -r /etc/os-release ]]; then
    log_err "无法读取 /etc/os-release，无法判断系统类型。"
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "debian" && "${ID_LIKE:-}" != *"debian"* ]]; then
    log_warn "检测到系统可能不是 Debian 系（ID=${ID:-unknown}，ID_LIKE=${ID_LIKE:-unknown}），仍继续尝试。"
  else
    log_info "系统检测：${PRETTY_NAME:-Debian系}"
  fi
}

# 中文备注：检查 sudo/root 权限
need_sudo_quanxian() {
  if [[ "${EUID}" -eq 0 ]]; then
    echo ""
  else
    if command -v sudo >/dev/null 2>&1; then
      echo "sudo"
    else
      log_err "当前非 root 且未安装 sudo，无法自动安装依赖。请先安装 sudo 或用 root 运行。"
      exit 1
    fi
  fi
}

# 中文备注：安装 apt 依赖
install_apt_yilai() {
  local sudo_cmd
  sudo_cmd="$(need_sudo_quanxian)"

  # 中文备注：基础依赖 + NodeSource 需要的证书/gnupg
  local pkgs=(
    ca-certificates
    curl
    gnupg
    git
    unzip
  )
  local missing_pkgs=()
  local pkg

  for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
      missing_pkgs+=("${pkg}")
    fi
  done

  if [[ "${#missing_pkgs[@]}" -eq 0 ]]; then
    log_info "系统依赖已齐全，跳过 apt 安装。"
    return 0
  fi

  log_info "仅安装缺失依赖：${missing_pkgs[*]}"
  log_info "更新 apt 索引..."
  ${sudo_cmd} apt-get update -y
  ${sudo_cmd} apt-get install -y "${missing_pkgs[@]}"
}

# 中文备注：检查命令是否存在
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# 中文备注：获取 codex 实际二进制路径，避免被 shell function/alias 干扰
get_codex_real_bin_lujing() {
  local real_bin
  local local_wrapper_lujing="${HOME}/.local/bin/codex"
  local houxuan_bin

  real_bin="$(command -v codex 2>/dev/null || true)"
  # 中文备注：若当前命中的是本脚本生成的本地包装，则继续向下查找真实二进制，避免递归包装
  if [[ -n "${real_bin}" && "${real_bin}" != "${local_wrapper_lujing}" && -x "${real_bin}" ]]; then
    echo "${real_bin}"
    return 0
  fi

  local npm_bin_dir
  npm_bin_dir="$(get_npm_quanju_bin_mulu)"
  if [[ -n "${npm_bin_dir}" && -x "${npm_bin_dir}/codex" ]]; then
    echo "${npm_bin_dir}/codex"
    return 0
  fi

  for houxuan_bin in /usr/local/bin/codex /usr/bin/codex /bin/codex; do
    if [[ "${houxuan_bin}" != "${local_wrapper_lujing}" && -x "${houxuan_bin}" ]]; then
      echo "${houxuan_bin}"
      return 0
    fi
  done

  echo ""
}

# 中文备注：安装 Node.js LTS（使用 NodeSource）
install_node_lts() {
  local sudo_cmd
  sudo_cmd="$(need_sudo_quanxian)"

  if has_cmd node && has_cmd npm; then
    log_info "检测到 Node.js 已安装：node=$(node -v 2>/dev/null || true)，npm=$(npm -v 2>/dev/null || true)"
    return 0
  fi

  log_info "安装 Node.js LTS（NodeSource setup_lts.x）..."

  # 中文备注：root 场景下 sudo_cmd 为空，不能拼出 “-E bash -”
  if [[ -n "${sudo_cmd}" ]]; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | ${sudo_cmd} -E bash -
    ${sudo_cmd} apt-get install -y nodejs
  else
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
  fi

  log_info "Node.js 安装完成：node=$(node -v)，npm=$(npm -v)"
}

# 中文备注：获取 npm 全局 bin 目录（兼容 npm 11：没有 npm bin）
get_npm_quanju_bin_mulu() {
  # npm prefix -g 通常返回 /usr 或 /usr/local，bin 在其下
  local prefix
  prefix="$(npm prefix -g 2>/dev/null || true)"
  if [[ -n "${prefix}" && -d "${prefix}/bin" ]]; then
    echo "${prefix}/bin"
    return 0
  fi

  # 兜底：常见路径
  if [[ -d "/usr/local/bin" ]]; then
    echo "/usr/local/bin"
    return 0
  fi
  if [[ -d "/usr/bin" ]]; then
    echo "/usr/bin"
    return 0
  fi

  # 最后兜底：输出空
  echo ""
}
# 中文备注：智能规范化 API Base URL
# 支持输入：域名 / https://域名 / https://域名/v1 / https://域名/v1/chat/completions 等
# 输出：标准 base url，形如 https://api.openai.com/v1
normalize_api_base_url() {
  local raw="$1"
  local s

  # 中文备注：去掉首尾空白
  s="$(echo -n "$raw" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

  # 中文备注：去掉包裹引号（"..." 或 '...'）
  s="$(echo -n "$s" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"

  if [[ -z "$s" ]]; then
    echo ""
    return 0
  fi

  # 中文备注：若没有 scheme，则默认补 https://
  if [[ "$s" != http://* && "$s" != https://* ]]; then
    s="https://${s}"
  fi

  # 中文备注：去掉末尾的 /
  s="$(echo -n "$s" | sed -e 's#/*$##')"

  # 中文备注：如果包含 /v1 之后的路径（例如 /v1/chat/completions），裁剪为 .../v1
  # 匹配 .../v1 或 .../v1/xxx
  if echo -n "$s" | grep -qE '/v1(/|$)'; then
    # 保留到第一个 /v1
    s="$(echo -n "$s" | sed -E 's#^(https?://[^/]+)(/v1)(/.*)?$#\1\2#')"
  else
    # 中文备注：不包含 /v1，则自动补 /v1
    s="${s}/v1"
  fi

  # 中文备注：防御性处理：去重 /v1/v1...
  while echo -n "$s" | grep -qE '/v1/v1'; do
    s="$(echo -n "$s" | sed -e 's#/v1/v1#/v1#g')"
  done

  # 中文备注：最终再去一次末尾 /
  s="$(echo -n "$s" | sed -e 's#/*$##')"

  echo "$s"
}

# 中文备注：安装 codexcli（npm 全局安装）
install_codexcli_npm() {
  local sudo_cmd
  sudo_cmd="$(need_sudo_quanxian)"

  # 中文备注：默认改为官方包名；仍支持用 CODEXCLI_PKG 覆盖
  local pkg_name="${CODEXCLI_PKG:-@openai/codex}"

  if npm list -g --depth=0 "${pkg_name}" >/dev/null 2>&1; then
    log_info "检测到 CLI 包已安装，跳过重复安装：${pkg_name}"
    return 0
  fi

  log_info "准备安装 CLI 包：${pkg_name}"
  log_info "执行：npm install -g ${pkg_name}"

  ${sudo_cmd} npm install -g "${pkg_name}"

  # 中文备注：@openai/codex 的可执行文件名是 codex
  local cli_bin="codex"
  if [[ "${pkg_name}" != "@openai/codex" ]]; then
    # 中文备注：非官方包时，尽量沿用包名作为可执行名（用户可自行改）
    cli_bin="${pkg_name}"
  fi

  if has_cmd "${cli_bin}"; then
    log_info "已安装并可执行：${cli_bin} --version"
    "${cli_bin}" --version || true
    return 0
  fi

  # 中文备注：PATH 未包含 npm 全局 bin 时，提示用户路径并尝试展示目录内容
  local bin_dir
  bin_dir="$(get_npm_quanju_bin_mulu)"

  log_warn "未在 PATH 中发现命令：${cli_bin}。这通常是 PATH 未包含 npm 全局 bin 目录导致。"
  if [[ -n "${bin_dir}" ]]; then
    log_info "推测 npm 全局 bin 目录：${bin_dir}"
    log_info "目录内容："
    ls -la "${bin_dir}" || true

    log_info "临时生效（当前会话）：export PATH=\"${bin_dir}:\$PATH\""
    log_info "永久生效（写入 ~/.bashrc）：echo 'export PATH=\"${bin_dir}:\$PATH\"' >> ~/.bashrc"
  else
    log_warn "无法自动定位 npm 全局 bin 目录。请执行：npm prefix -g 并检查其下的 bin 目录。"
  fi
}

# 中文备注：强校验 codex 是否真正可执行，安装完成后立即失败更容易定位问题
verify_codex_kezhixing() {
  local codex_bin
  codex_bin="$(get_codex_real_bin_lujing)"

  if [[ -z "${codex_bin}" ]]; then
    log_err "未找到 codex 可执行文件。请检查 npm 全局安装目录与 PATH。"
    exit 1
  fi

  if ! "${codex_bin}" --version >/dev/null 2>&1; then
    log_err "codex 已找到但执行失败：${codex_bin}"
    exit 1
  fi

  log_info "codex 校验通过：${codex_bin}"
}



# 中文备注：读取用户输入（支持默认值）
read_input() {
  local prompt="$1"
  local default="${2:-}"
  local var
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [默认: ${default}]: " var
    echo "${var:-$default}"
  else
    read -r -p "${prompt}: " var
    echo "${var}"
  fi
}

# 中文备注：读取敏感输入（不回显）
read_secret() {
  local prompt="$1"
  local var
  read -r -s -p "${prompt}: " var
  echo
  echo "${var}"
}

# 中文备注：判断是否官方 OpenAI URL（host=api.openai.com）
check_guanfang_openai_url() {
  local api_base_url="$1"
  local host

  host="$(echo -n "${api_base_url}" | sed -E 's#^https?://([^/]+).*$#\1#' | tr '[:upper:]' '[:lower:]')"
  if [[ "${host}" == "api.openai.com" ]]; then
    return 0
  fi
  return 1
}
save_codex_zuigao_quanxian_peizhi() {
  local cfg_dir="${HOME}/.codex"
  local cfg_file="${cfg_dir}/config.toml"
  local marker_begin="# >>> codexcli max permissions begin >>>"
  local marker_end="# <<< codexcli max permissions end <<<"

  mkdir -p "${cfg_dir}"
  chmod 700 "${cfg_dir}"
  if [[ ! -f "${cfg_file}" ]]; then
    touch "${cfg_file}"
  fi

  # 中文备注：先移除旧 marker 区块，避免重复叠加
  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_begin}" "${marker_end}"

  # 中文备注：按文本方式写入根级权限配置，避免依赖命令行参数包装导致启动异常
  delete_regex_hang_wenjian "${cfg_file}" '^[[:space:]]*approval_policy[[:space:]]*=[[:space:]]*"never"[[:space:]]*$'
  delete_regex_hang_wenjian "${cfg_file}" '^[[:space:]]*sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"[[:space:]]*$'
  delete_regex_hang_wenjian "${cfg_file}" '^[[:space:]]*notice\.hide_full_access_warning[[:space:]]*=[[:space:]]*true[[:space:]]*$'
  delete_toml_biao_qukuai_wenjian "${cfg_file}" '^[[:space:]]*\[shell_environment_policy\][[:space:]]*$'

  local tmp_yuanshi_wenjian
  local tmp_xin_wenjian
  tmp_yuanshi_wenjian="$(mktemp)"
  tmp_xin_wenjian="$(mktemp)"
  cp "${cfg_file}" "${tmp_yuanshi_wenjian}"

  cat > "${tmp_xin_wenjian}" <<EOF
${marker_begin}
approval_policy = "never"
sandbox_permissions = [
  "disk-full-access"
]

[shell_environment_policy]
inherit = "all"
${marker_end}

EOF

  # 中文备注：确保权限块位于文件顶部（所有 [table] 之前），再拼接原内容
  cat "${tmp_xin_wenjian}" "${tmp_yuanshi_wenjian}" > "${cfg_file}"
  rm -f "${tmp_xin_wenjian}" "${tmp_yuanshi_wenjian}"

  chmod 600 "${cfg_file}"
  log_info "已写入 Codex 最高权限配置：${cfg_file}"
}



# 中文备注：清理旧版写入 ~/.bashrc 的 env 自动加载片段（迁移到 config.toml）
cleanup_legacy_env_bashrc_loader() {
  local bashrc="${HOME}/.bashrc"
  local marker_begin="# >>> codexcli env begin >>>"
  local marker_end="# <<< codexcli env end <<<"

  if [[ -f "${bashrc}" ]] && grep -qF "${marker_begin}" "${bashrc}"; then
    delete_marker_qukuai_wenjian "${bashrc}" "${marker_begin}" "${marker_end}"
    log_info "检测到旧版 ~/.bashrc 环境变量加载片段，已移除。"
  fi
}

# 中文备注：兼容清理旧版遗留的 codexcli_custom 根级配置与 TOML 表块
clear_codexcli_custom_canliu_peizhi() {
  local cfg_file="$1"
  local legacy_marker_begin="# >>> codexcli feiguanfang provider begin >>>"
  local legacy_marker_end="# <<< codexcli feiguanfang provider end <<<"

  if [[ ! -f "${cfg_file}" ]]; then
    return 0
  fi

  delete_marker_qukuai_wenjian "${cfg_file}" "${legacy_marker_begin}" "${legacy_marker_end}"
  delete_regex_hang_wenjian "${cfg_file}" '^[[:space:]]*profile[[:space:]]*=[[:space:]]*"codexcli_custom"[[:space:]]*$'
  delete_regex_hang_wenjian "${cfg_file}" '^[[:space:]]*model_provider[[:space:]]*=[[:space:]]*"codexcli_custom"[[:space:]]*$'
  delete_toml_biao_qukuai_wenjian "${cfg_file}" '^[[:space:]]*\[model_providers\.codexcli_custom\][[:space:]]*$'
  delete_toml_biao_qukuai_wenjian "${cfg_file}" '^[[:space:]]*\[profiles\.codexcli_custom\][[:space:]]*$'
  cleanup_kong_wenjian "${cfg_file}"
}

# 中文备注：统一将 provider + token 写入 ~/.codex/config.toml（不再依赖环境变量文件）
save_codex_provider_peizhi() {
  local api_base_url="$1"
  local api_key="$2"

  local cfg_dir="${HOME}/.codex"
  local cfg_file="${cfg_dir}/config.toml"
  local marker_begin="# >>> codexcli provider begin >>>"
  local marker_end="# <<< codexcli provider end <<<"
  local legacy_marker_begin="# >>> codexcli feiguanfang provider begin >>>"
  local legacy_marker_end="# <<< codexcli feiguanfang provider end <<<"
  local marker_profile_begin="# >>> codexcli moren profile begin >>>"
  local marker_profile_end="# <<< codexcli moren profile end <<<"
  local escaped_base_url
  local escaped_api_key
  local tmp_yuanshi_wenjian
  local tmp_profile_wenjian

  mkdir -p "${cfg_dir}"
  chmod 700 "${cfg_dir}"
  if [[ ! -f "${cfg_file}" ]]; then
    touch "${cfg_file}"
  fi

  escaped_base_url="$(escape_toml_jiben_zifuchuan "${api_base_url}")"
  escaped_api_key="$(escape_toml_jiben_zifuchuan "${api_key}")"

  # 中文备注：幂等更新脚本写入区块，避免重复叠加
  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_begin}" "${marker_end}"
  # 中文备注：兼容清理旧版 marker，避免历史块残留导致配置混乱
  delete_marker_qukuai_wenjian "${cfg_file}" "${legacy_marker_begin}" "${legacy_marker_end}"
  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_profile_begin}" "${marker_profile_end}"
  clear_codexcli_custom_canliu_peizhi "${cfg_file}"

  tmp_yuanshi_wenjian="$(mktemp)"
  tmp_profile_wenjian="$(mktemp)"
  cp "${cfg_file}" "${tmp_yuanshi_wenjian}"

  cat > "${tmp_profile_wenjian}" <<EOF
${marker_profile_begin}
profile = "codexcli_custom"
${marker_profile_end}

EOF

  cat "${tmp_profile_wenjian}" "${tmp_yuanshi_wenjian}" > "${cfg_file}"
  rm -f "${tmp_profile_wenjian}" "${tmp_yuanshi_wenjian}"

  cat >> "${cfg_file}" <<EOF

${marker_begin}
[model_providers.codexcli_custom]
name = "codexcli_custom"
base_url = "${escaped_base_url}"
experimental_bearer_token = "${escaped_api_key}"
wire_api = "responses"

[profiles.codexcli_custom]
model_provider = "codexcli_custom"
model_verbosity = "high"
${marker_end}
EOF

  chmod 600 "${cfg_file}"
  log_info "已写入 Codex Provider 配置：${cfg_file}"
  log_info "已写入根级默认 profile=codexcli_custom"
}

# 中文备注：写入项目 trust 配置，避免目录信任确认提示
save_codex_project_trust_peizhi() {
  local project_mulu="$1"
  local cfg_dir="${HOME}/.codex"
  local cfg_file="${cfg_dir}/config.toml"
  local marker_begin="# >>> codexcli trusted project begin >>>"
  local marker_end="# <<< codexcli trusted project end <<<"
  local escaped_project_mulu

  mkdir -p "${cfg_dir}"
  chmod 700 "${cfg_dir}"
  if [[ ! -f "${cfg_file}" ]]; then
    touch "${cfg_file}"
  fi

  escaped_project_mulu="$(escape_toml_jiben_zifuchuan "${project_mulu}")"
  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_begin}" "${marker_end}"

  cat >> "${cfg_file}" <<EOF

${marker_begin}
[projects."${escaped_project_mulu}"]
trust_level = "trusted"
${marker_end}
EOF

  chmod 600 "${cfg_file}"
  log_info "已将项目目录标记为 trusted：${project_mulu}"
}

# 中文备注：清理旧版 codex shell 包装与本地包装脚本残留，避免继续影响启动
clear_codex_wrapper_canliu_peizhi() {
  local marker_wrapper_begin="# >>> codexcli wrapper begin >>>"
  local marker_wrapper_end="# <<< codexcli wrapper end <<<"
  local local_wrapper="${HOME}/.local/bin/codex"

  delete_marker_qukuai_wenjian "${HOME}/.bashrc" "${marker_wrapper_begin}" "${marker_wrapper_end}"
  delete_marker_qukuai_wenjian "${HOME}/.profile" "${marker_wrapper_begin}" "${marker_wrapper_end}"

  if [[ -f "${local_wrapper}" ]]; then
    rm -f "${local_wrapper}"
    log_info "已删除旧版本地 codex 包装脚本：${local_wrapper}"
  fi
}

# 中文备注：按需清理自定义 provider、默认 profile 与最高权限配置，可选择是否删除登录态
clear_codex_zidingyi_peizhi_tongyong() {
  local is_delete_auth_json="${1:-1}"
  local cfg_file="${HOME}/.codex/config.toml"
  local marker_quanxian_begin="# >>> codexcli max permissions begin >>>"
  local marker_quanxian_end="# <<< codexcli max permissions end <<<"
  local marker_provider_begin="# >>> codexcli provider begin >>>"
  local marker_provider_end="# <<< codexcli provider end <<<"
  local legacy_marker_begin="# >>> codexcli feiguanfang provider begin >>>"
  local legacy_marker_end="# <<< codexcli feiguanfang provider end <<<"
  local marker_profile_begin="# >>> codexcli moren profile begin >>>"
  local marker_profile_end="# <<< codexcli moren profile end <<<"
  local marker_trust_begin="# >>> codexcli trusted project begin >>>"
  local marker_trust_end="# <<< codexcli trusted project end <<<"
  local marker_wrapper_begin="# >>> codexcli wrapper begin >>>"
  local marker_wrapper_end="# <<< codexcli wrapper end <<<"
  local auth_file="${HOME}/.codex/auth.json"
  local local_wrapper="${HOME}/.local/bin/codex"

  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_quanxian_begin}" "${marker_quanxian_end}"
  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_provider_begin}" "${marker_provider_end}"
  delete_marker_qukuai_wenjian "${cfg_file}" "${legacy_marker_begin}" "${legacy_marker_end}"
  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_profile_begin}" "${marker_profile_end}"
  delete_marker_qukuai_wenjian "${cfg_file}" "${marker_trust_begin}" "${marker_trust_end}"
  clear_codexcli_custom_canliu_peizhi "${cfg_file}"
  cleanup_kong_wenjian "${cfg_file}"

  delete_marker_qukuai_wenjian "${HOME}/.bashrc" "${marker_wrapper_begin}" "${marker_wrapper_end}"
  delete_marker_qukuai_wenjian "${HOME}/.profile" "${marker_wrapper_begin}" "${marker_wrapper_end}"

  if [[ -f "${local_wrapper}" ]]; then
    rm -f "${local_wrapper}"
    log_info "已删除本地 codex 包装脚本：${local_wrapper}"
  fi

  if [[ "${is_delete_auth_json}" == "1" && -f "${auth_file}" ]]; then
    rm -f "${auth_file}"
    log_info "已清除登录态文件：${auth_file}"
  fi
}

# 中文备注：清理自定义 provider、默认 profile 与最高权限配置
clear_codex_zidingyi_peizhi() {
  clear_codex_zidingyi_peizhi_tongyong "1"
  log_info "已清除菜单 1 写入的配置。"
  log_info "重新打开终端后，可直接使用官方方式执行：codex login"
}

# 中文备注：仅设置 Codex 最高权限与当前项目 trusted，不配置自定义 provider
setup_codex_zuigao_quanxian_duli() {
  local current_project_mulu

  current_project_mulu="$(pwd -P)"
  clear_codex_wrapper_canliu_peizhi
  save_codex_zuigao_quanxian_peizhi
  save_codex_project_trust_peizhi "${current_project_mulu}"

  log_info "已设置 Codex 最高权限。"
  log_info "权限通过 ~/.codex/config.toml 生效，不再写入 shell 包装。"
}

# 中文备注：修复菜单脚本中途退出后遗留的 codex 启动残留，保留官方登录态
repair_codex_qidong_yichang() {
  clear_codex_zidingyi_peizhi_tongyong "0"
  log_info "已修复 codex 启动残留，保留现有登录态。"
  log_info "重新打开终端后，可直接执行：codex"
}

# 中文备注：菜单 1，设置 API KEY 并强制 codex 走自定义 provider
setup_api_key_zidingyi_provider() {
  log_info "开始配置 API 接口与 KEY（将写入 ~/.codex/config.toml）"

  local default_base="https://api.openai.com/v1"
  local api_base_url_raw
  local api_key_raw
  local current_project_mulu
  api_base_url_raw="$(read_input "请输入 API Base URL（可只填域名/也可填到具体接口；留空则取消，建议值：${default_base}）")"
  current_project_mulu="$(pwd -P)"

  api_base_url_raw="$(echo -n "${api_base_url_raw}" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"
  if [[ -z "${api_base_url_raw}" ]]; then
    log_warn "API Base URL 为空，已取消，不修改任何配置。"
    return 0
  fi

  api_key_raw="$(read_input "请输入 API KEY（明文显示；留空则取消）")"
  api_key_raw="$(echo -n "${api_key_raw}" | tr -d '[:space:]')"
  if [[ -z "${api_key_raw}" ]]; then
    log_warn "API KEY 为空，已取消，不修改任何配置。"
    return 0
  fi

  local api_base_url
  api_base_url="$(normalize_api_base_url "${api_base_url_raw}")"
  api_base_url="$(echo -n "${api_base_url}" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

  if [[ -z "${api_base_url}" ]]; then
    log_err "API Base URL 解析失败（输入为空或格式不合法）。"
    return 1
  fi

  log_info "已规范化 API Base URL => ${api_base_url}"

  local api_key
  api_key="${api_key_raw}"

  if [[ -z "${api_key}" ]]; then
    log_err "API KEY 不能为空。"
    return 1
  fi

  cleanup_legacy_env_bashrc_loader
  clear_codex_wrapper_canliu_peizhi
  save_codex_zuigao_quanxian_peizhi
  save_codex_provider_peizhi "${api_base_url}" "${api_key}"
  save_codex_project_trust_peizhi "${current_project_mulu}"

  log_info "配置完成，权限与 provider 已写入 ~/.codex/config.toml"
  log_info "之后直接运行 codex，即会默认使用 codexcli_custom，且按配置文件权限策略运行"
}

# 中文备注：打印菜单
show_caidan_xinxi() {
  echo
  echo "=============================="
  echo " codexcli 菜单"
  echo "=============================="
  echo "1. 设置 API KEY（强制 codex 走自定义 provider）"
  echo "2. 清除配置（恢复到可官方登录的初始状态）"
  echo "3. 修复 codex 启动异常（清理残留，保留登录态）"
  echo "4. 仅设置 Codex 最高权限（不配置 provider）"
  echo "0. 退出"
  echo "=============================="
}

# 中文备注：循环处理菜单选择
handle_caidan_xuanze() {
  local xuanze

  show_caidan_xinxi
  xuanze="$(read_input "请选择操作" "1")"

  case "${xuanze}" in
    1)
      setup_api_key_zidingyi_provider
      log_info "脚本执行完毕，已退出"
      ;;
    2)
      clear_codex_zidingyi_peizhi
      log_info "脚本执行完毕，已退出。"
      ;;
    3)
      repair_codex_qidong_yichang
      log_info "脚本执行完毕，已退出。"
      ;;
    4)
      setup_codex_zuigao_quanxian_duli
      log_info "脚本执行完毕，已退出。"
      ;;
    0)
      log_info "已退出。"
      ;;
    *)
      log_warn "无效选项：${xuanze}"
      log_info "脚本执行完毕，已退出。"
      ;;
  esac
}

# 中文备注：启动时默认检查/安装，检查完成后进入菜单
main() {
  check_debian_xitong
  install_apt_yilai
  install_node_lts
  install_codexcli_npm
  verify_codex_kezhixing
  handle_caidan_xuanze
}

main "$@"
