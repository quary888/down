#!/usr/bin/env bash
set -euo pipefail

# =========================
# Debian: codexcli 安装 + 配置脚本
# - 自动检查/安装依赖
# - 安装 Node.js LTS (NodeSource)
# - 安装 codexcli (npm -g)
# - 交互输入 API_BASE_URL 与 API_KEY
# - 保存到 ~/.config/codexcli/env 并写入 ~/.bashrc 自动加载
# =========================

# 中文备注：统一输出
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_err()  { echo "[ERR ] $*" >&2; }

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

  log_info "更新 apt 索引..."
  ${sudo_cmd} apt-get update -y

  # 中文备注：基础依赖 + NodeSource 需要的证书/gnupg
  local pkgs=(
    ca-certificates
    curl
    gnupg
    git
    unzip
  )

  log_info "安装依赖：${pkgs[*]}"
  ${sudo_cmd} apt-get install -y "${pkgs[@]}"
}

# 中文备注：检查命令是否存在
has_cmd() { command -v "$1" >/dev/null 2>&1; }

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

# 中文备注：保存配置到 env 文件，并写入 ~/.bashrc 自动 source
save_api_peizhi() {
  local api_base_url="$1"
  local api_key="$2"

  if [[ -z "${api_base_url}" ]]; then
    log_err "API_BASE_URL 不能为空。"
    exit 1
  fi
  if [[ -z "${api_key}" ]]; then
    log_err "API_KEY 不能为空。"
    exit 1
  fi

  local cfg_dir="${HOME}/.config/codexcli"
  local env_file="${cfg_dir}/env"
  mkdir -p "${cfg_dir}"
  chmod 700 "${cfg_dir}"

  # 中文备注：写入 env（覆盖式），并限制权限
  umask 177
  cat > "${env_file}" <<EOF
# 自动生成：codexcli 环境变量
export OPENAI_BASE_URL="${api_base_url}"
export OPENAI_API_KEY="${api_key}"
EOF
  chmod 600 "${env_file}"

  log_info "已保存配置：${env_file}"

  # 中文备注：向 ~/.bashrc 写入一次性 source 片段（幂等）
  local bashrc="${HOME}/.bashrc"
  local marker_begin="# >>> codexcli env begin >>>"
  local marker_end="# <<< codexcli env end <<<"

  if [[ ! -f "${bashrc}" ]]; then
    touch "${bashrc}"
  fi

  # 若已存在旧片段，先删除再重写，避免重复
  if grep -qF "${marker_begin}" "${bashrc}"; then
    log_info "检测到 ~/.bashrc 已存在 codexcli 配置片段，进行更新..."
    # 用 sed 删除 marker 区间
    sed -i.bak "/${marker_begin}/,/${marker_end}/d" "${bashrc}"
  else
    log_info "写入 ~/.bashrc 自动加载配置..."
  fi

  cat >> "${bashrc}" <<EOF

${marker_begin}
# 中文备注：自动加载 codexcli 环境变量（由安装脚本写入）
if [ -f "${env_file}" ]; then
  . "${env_file}"
fi
${marker_end}
EOF

  log_info "已更新：${bashrc}（备份如存在：${bashrc}.bak）"
  log_info "当前会话立即生效：source ${env_file}"
  # 中文备注：当前 shell 尝试加载（不强制）
  # shellcheck disable=SC1090
  . "${env_file}" || true
}

main() {
  check_debian_xitong
  install_apt_yilai
  install_node_lts
  install_codexcli_npm

  log_info "开始配置 API 接口与 KEY（将保存到 ~/.config/codexcli/env）"

  # 中文备注：API_BASE_URL 可输入官方或自建代理/网关地址
  local default_base="https://api.openai.com/v1"
  local api_base_url_raw
  api_base_url_raw="$(read_input "请输入 API Base URL（可只填域名/也可填到具体接口）" "${default_base}")"

  local api_base_url
  api_base_url="$(normalize_api_base_url "${api_base_url_raw}")"
  # 去首尾空白
  api_base_url="$(echo -n "${api_base_url}" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"


  if [[ -z "${api_base_url}" ]]; then
    log_err "API Base URL 解析失败（输入为空或格式不合法）。"
    exit 1
  fi

  log_info "已规范化 API Base URL => ${api_base_url}"



  local api_key
  api_key="$(read_secret "请输入 API KEY（不回显）")"
  api_key="$(echo -n "${api_key}" | tr -d '[:space:]')"
  save_api_peizhi "${api_base_url}" "${api_key}"

  log_info "完成。新开终端或执行：source ~/.bashrc 以确保环境变量加载。"
  log_info "已设置：OPENAI_BASE_URL / OPENAI_API_KEY"
}

main "$@"
