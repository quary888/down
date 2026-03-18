#!/usr/bin/env bash
set -euo pipefail

# ===== User-editable variables =====
MTG_REPO_URL="https://github.com/9seconds/mtg"
MTG_VERSION="latest" # latest or explicit like 2.2.1
FORCE_REINSTALL=0 # 1=总是重新下载覆盖; 0=已安装则跳过下载
DEFAULT_FAKE_TLS_HOST="repo1.maven.org"
DEFAULT_BIND="0.0.0.0:10809"
# ================================

CONFIG_PATH="/etc/mtg.toml"
SERVICE_PATH="/etc/systemd/system/mtg.service"
BIN_PATH="/usr/local/bin/mtg"
CURL_PROXY_ARGS=()

color() {
  local code="$1"; shift
  printf "\033[%sm%s\033[0m\n" "$code" "$*"
}

log() { color "1;34" "[INFO] $*"; }
warn() { color "1;33" "[WARN] $*"; }
err() { color "1;31" "[ERR ] $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 运行: sudo bash $0"
    exit 1
  fi
}

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    err "无法识别系统: /etc/os-release 不存在"
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *)
      err "仅支持 Debian/Ubuntu，当前系统: ${PRETTY_NAME:-unknown}"
      exit 1
      ;;
  esac
  log "系统检测通过: ${PRETTY_NAME}"
}

map_arch() {
  local uarch
  uarch="$(uname -m)"
  case "$uarch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      err "不支持的架构: $uarch (仅支持 x86_64/amd64/aarch64/arm64)"
      exit 1
      ;;
  esac
}

check_cmds() {
  local missing=()
  local c
  for c in curl tar systemctl sed grep awk; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "缺少命令: ${missing[*]}"
    err "请先安装依赖后重试（例如: apt update && apt install -y curl tar systemd）"
    exit 1
  fi
}

setup_download_proxy() {
  # curl 默认会读取 http_proxy/https_proxy/all_proxy
  if [[ -n "${https_proxy:-}" || -n "${HTTPS_PROXY:-}" || -n "${http_proxy:-}" || -n "${HTTP_PROXY:-}" || -n "${all_proxy:-}" || -n "${ALL_PROXY:-}" ]]; then
    log "检测到环境代理变量，下载将沿用环境代理"
    return
  fi

  # 若本机存在 xray socks5 端口，则自动用于下载
  if command -v ss >/dev/null 2>&1; then
    if ss -lnt 2>/dev/null | grep -q '127.0.0.1:10808'; then
      CURL_PROXY_ARGS=(--socks5-hostname 127.0.0.1:10808)
      log "未检测到环境代理，下载自动使用 socks5://127.0.0.1:10808"
    fi
  fi
}

fetch_latest_tag() {
  local api_url repo_path tag
  repo_path="${MTG_REPO_URL#https://github.com/}"
  api_url="https://api.github.com/repos/${repo_path}/releases/latest"

  tag="$(curl "${CURL_PROXY_ARGS[@]}" -fsSL "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -z "$tag" ]]; then
    err "无法获取最新版本 tag，请检查网络或 GitHub API 限制"
    exit 1
  fi
  printf '%s' "$tag"
}

resolve_release() {
  local arch tag version_no file_name download_url
  arch="$(map_arch)"

  if [[ "$MTG_VERSION" == "latest" ]]; then
    tag="$(fetch_latest_tag)"
  else
    if [[ "$MTG_VERSION" =~ ^v ]]; then
      tag="$MTG_VERSION"
    else
      tag="v$MTG_VERSION"
    fi
  fi

  version_no="${tag#v}"
  file_name="mtg-${version_no}-linux-${arch}.tar.gz"
  download_url="${MTG_REPO_URL}/releases/download/${tag}/${file_name}"

  printf '%s|%s|%s|%s' "$tag" "$version_no" "$file_name" "$download_url"
}

installed_mtg_version() {
  if [[ -x "$BIN_PATH" ]]; then
    "$BIN_PATH" --version 2>/dev/null | awk 'NR==1{print $1}'
  fi
}

should_skip_download() {
  local installed wanted
  if [[ "$FORCE_REINSTALL" == "1" ]]; then
    return 1
  fi

  installed="$(installed_mtg_version || true)"
  if [[ -z "$installed" ]]; then
    return 1
  fi

  if [[ "$MTG_VERSION" == "latest" ]]; then
    log "检测到已安装 mtg ${installed}，跳过下载（MTG_VERSION=latest）"
    return 0
  fi

  wanted="${MTG_VERSION#v}"
  if [[ "$installed" == "$wanted" ]]; then
    log "检测到已安装 mtg ${installed}，与目标版本一致，跳过下载"
    return 0
  fi
  return 1
}

download_and_install_mtg() {
  local rel tag version_no file_name url
  if should_skip_download; then
    return 0
  fi

  rel="$(resolve_release)"
  IFS='|' read -r tag version_no file_name url <<<"$rel"

  log "目标版本: ${tag}"
  log "下载地址: ${url}"

  (
    local tmpd tgz mtg_file
    tmpd="$(mktemp -d)"
    tgz="${tmpd}/${file_name}"
    trap 'rm -rf "${tmpd:-}"' EXIT

    if ! curl "${CURL_PROXY_ARGS[@]}" -fL --connect-timeout 15 --retry 3 --retry-delay 2 -o "$tgz" "$url"; then
      err "下载失败: ${url}"
      err "你可以手动下载后放到本机，再自行替换 ${BIN_PATH}"
      exit 1
    fi

    tar -xzf "$tgz" -C "$tmpd"
    mtg_file="$(find "$tmpd" -maxdepth 3 -type f -name mtg | head -n1)"
    if [[ -z "$mtg_file" ]]; then
      err "压缩包中未找到 mtg 可执行文件"
      exit 1
    fi

    install -m 0755 "$mtg_file" "$BIN_PATH"
    log "已安装: ${BIN_PATH}"
    "$BIN_PATH" --version || true
  )
}

create_service() {
  cat > "$SERVICE_PATH" <<'UNIT'
[Unit]
Description=MTProto Proxy (mtg)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mtg run /etc/mtg.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable mtg >/dev/null 2>&1 || true
}

ensure_default_config() {
  if [[ -f "$CONFIG_PATH" ]]; then
    return
  fi
  local secret
  secret="$($BIN_PATH generate-secret "$DEFAULT_FAKE_TLS_HOST")"

  cat > "$CONFIG_PATH" <<EOF_CFG
secret = "$secret"
bind-to = "$DEFAULT_BIND"
EOF_CFG

  log "已创建默认配置: ${CONFIG_PATH}"
}

get_cfg_secret() {
  [[ -f "$CONFIG_PATH" ]] || return 0
  sed -n 's/^[[:space:]]*secret[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_PATH" | head -n1
}

get_cfg_bind() {
  [[ -f "$CONFIG_PATH" ]] || return 0
  sed -n 's/^[[:space:]]*bind-to[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_PATH" | head -n1
}

get_cfg_socks5() {
  [[ -f "$CONFIG_PATH" ]] || return 0
  sed -n 's/^[[:space:]]*proxies[[:space:]]*=[[:space:]]*\["\([^"]*\)"\].*/\1/p' "$CONFIG_PATH" | head -n1
}

write_config() {
  local secret bind socks
  secret="$1"
  bind="$2"
  socks="${3:-}"

  {
    printf 'secret = "%s"\n' "$secret"
    printf 'bind-to = "%s"\n' "$bind"
    if [[ -n "$socks" ]]; then
      printf '\n[network]\n'
      printf 'proxies = ["%s"]\n' "$socks"
    fi
  } > "$CONFIG_PATH"
}

restart_mtg() {
  systemctl restart mtg
  sleep 1
  systemctl --no-pager -l status mtg | sed -n '1,20p'
}

show_status() {
  echo
  color "1;36" "===== 当前状态 ====="
  echo "二进制: $BIN_PATH"
  "$BIN_PATH" --version 2>/dev/null || true
  echo "配置: $CONFIG_PATH"
  echo "secret: $(get_cfg_secret)"
  echo "bind-to: $(get_cfg_bind)"
  local s
  s="$(get_cfg_socks5 || true)"
  if [[ -n "$s" ]]; then
    echo "socks5上游: $s"
  else
    echo "socks5上游: (未设置)"
  fi
  echo "systemd: $(systemctl is-active mtg 2>/dev/null || true)"
  echo "监听端口:"
  ss -lntup 2>/dev/null | grep ':10809' || true
  echo "====================="
  echo
}

menu_set_socks5() {
  local current input
  current="$(get_cfg_socks5 || true)"
  echo
  color "1;36" "[设置Socks5]"
  echo "当前: ${current:-未设置}"
  echo "输入 socks5 URL，例如: socks5://127.0.0.1:10808"
  echo "直接回车 = 清空 socks5 配置（直连）"
  read -r -p "Socks5 URL: " input

  write_config "$(get_cfg_secret)" "$(get_cfg_bind)" "$input"
  restart_mtg
}

menu_set_mtproto() {
  while true; do
    echo
    color "1;36" "[设置MTProto]"
    echo "1) 生成新密钥 (按域名)"
    echo "2) 手动设置密钥"
    echo "3) 设置监听地址端口"
    echo "4) 查看连接信息 (mtg access)"
    echo "5) 重启 mtg"
    echo "0) 返回上级菜单"
    read -r -p "请选择: " sub

    case "$sub" in
      1)
        local host new_secret
        read -r -p "输入伪装域名 [默认: ${DEFAULT_FAKE_TLS_HOST}]: " host
        host="${host:-$DEFAULT_FAKE_TLS_HOST}"
        new_secret="$($BIN_PATH generate-secret "$host")"
        write_config "$new_secret" "$(get_cfg_bind)" "$(get_cfg_socks5 || true)"
        restart_mtg
        "$BIN_PATH" access "$CONFIG_PATH" || true
        ;;
      2)
        local manual_secret
        read -r -p "输入 secret(base64 或 ee...hex): " manual_secret
        if [[ -z "$manual_secret" ]]; then
          warn "未输入，已取消"
        else
          write_config "$manual_secret" "$(get_cfg_bind)" "$(get_cfg_socks5 || true)"
          restart_mtg
          "$BIN_PATH" access "$CONFIG_PATH" || true
        fi
        ;;
      3)
        local new_bind
        read -r -p "输入监听地址端口 [当前: $(get_cfg_bind)]: " new_bind
        new_bind="${new_bind:-$(get_cfg_bind)}"
        write_config "$(get_cfg_secret)" "$new_bind" "$(get_cfg_socks5 || true)"
        restart_mtg
        ;;
      4)
        "$BIN_PATH" access "$CONFIG_PATH" || true
        ;;
      5)
        restart_mtg
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项"
        ;;
    esac
  done
}

main_menu() {
  while true; do
    show_status
    echo "1) 设置Socks5"
    echo "2) 设置MTProto"
    echo "0) 退出"
    read -r -p "请选择: " choice

    case "$choice" in
      1) menu_set_socks5 ;;
      2) menu_set_mtproto ;;
      0) exit 0 ;;
      *) warn "无效选项" ;;
    esac
  done
}

bootstrap() {
  require_root
  check_os
  check_cmds
  setup_download_proxy

  download_and_install_mtg
  create_service
  ensure_default_config
  systemctl restart mtg

  log "安装完成，进入交互菜单"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  bootstrap
  main_menu
fi
