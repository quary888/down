#!/bin/sh

set -u

CONF_FILE="/etc/microsocks_manager.conf"
SERVICE_NAME="microsocks-manager"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
MICROSOCKS_BIN=""

err() {
  echo "错误: $1" >&2
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

detect_os() {
  if [ -f /etc/alpine-release ]; then
    echo "alpine"
    return
  fi
  if [ -f /etc/debian_version ]; then
    echo "debian"
    return
  fi
  echo "unknown"
}

has_systemd() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

has_openrc() {
  command -v rc-update >/dev/null 2>&1 && [ -d /etc/init.d ]
}

find_microsocks_bin() {
  if command -v microsocks >/dev/null 2>&1; then
    echo "$(command -v microsocks)"
    return
  fi
  if [ -x /usr/bin/microsocks ]; then
    echo "/usr/bin/microsocks"
    return
  fi
  if [ -x /usr/sbin/microsocks ]; then
    echo "/usr/sbin/microsocks"
    return
  fi
  echo ""
}

install_dependencies() {
  if [ -n "$(find_microsocks_bin)" ]; then
    echo "已检测到 microsocks，跳过依赖安装"
    return 0
  fi

  os="$(detect_os)"
  case "$os" in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y microsocks
      ;;
    alpine)
      apk update
      apk add --no-cache microsocks
      ;;
    *)
      err "仅支持 Debian/Alpine"
      return 1
      ;;
  esac
  return 0
}

load_conf() {
  USERNAME=""
  PASSWORD=""
  PORT=""
  if [ -f "$CONF_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONF_FILE"
  fi
}

save_conf() {
  umask 077
  cat >"$CONF_FILE" <<EOF
USERNAME='${USERNAME}'
PASSWORD='${PASSWORD}'
PORT='${PORT}'
EOF
  chmod 600 "$CONF_FILE"
}

validate_port() {
  p="$1"
  case "$p" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

build_microsocks_args() {
  if [ -n "${USERNAME:-}" ]; then
    echo "-i 0.0.0.0 -p ${PORT} -u ${USERNAME} -P ${PASSWORD}"
    return
  fi
  echo "-i 0.0.0.0 -p ${PORT}"
}

create_systemd_service() {
  MICROSOCKS_BIN="$(find_microsocks_bin)"
  if [ -z "$MICROSOCKS_BIN" ]; then
    err "未找到 microsocks 可执行文件"
    return 1
  fi

  MICROSOCKS_ARGS="$(build_microsocks_args)"

  cat >"$SYSTEMD_SERVICE_FILE" <<EOF
[Unit]
Description=SOCKS5 Server (microsocks)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${MICROSOCKS_BIN} ${MICROSOCKS_ARGS}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

create_openrc_service() {
  MICROSOCKS_BIN="$(find_microsocks_bin)"
  if [ -z "$MICROSOCKS_BIN" ]; then
    err "未找到 microsocks 可执行文件"
    return 1
  fi

  MICROSOCKS_ARGS="$(build_microsocks_args)"

  cat >"$OPENRC_SERVICE_FILE" <<EOF
#!/sbin/openrc-run

name="microsocks manager"
description="SOCKS5 Server (microsocks)"
command="${MICROSOCKS_BIN}"
command_args="${MICROSOCKS_ARGS}"
command_background="yes"
pidfile="/run/${SERVICE_NAME}.pid"

depend() {
  need net
}
EOF
  chmod +x "$OPENRC_SERVICE_FILE"
}

enable_and_start_service() {
  if has_systemd; then
    create_systemd_service || return 1
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    return $?
  fi

  if has_openrc; then
    create_openrc_service || return 1
    rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
    rc-service "$SERVICE_NAME" restart
    return $?
  fi

  err "未检测到可用的 init 系统(systemd/openrc)"
  return 1
}

disable_and_stop_service() {
  ret=0
  if has_systemd; then
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    if [ -f "$SYSTEMD_SERVICE_FILE" ]; then
      rm -f "$SYSTEMD_SERVICE_FILE"
      systemctl daemon-reload
    fi
  fi

  if has_openrc; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
    rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
    [ -f "$OPENRC_SERVICE_FILE" ] && rm -f "$OPENRC_SERVICE_FILE"
  fi

  return $ret
}

service_running() {
  if has_systemd; then
    systemctl is-active --quiet "$SERVICE_NAME"
    return $?
  fi
  if has_openrc; then
    rc-service "$SERVICE_NAME" status >/dev/null 2>&1
    return $?
  fi
  return 1
}

boot_enabled() {
  if has_systemd; then
    systemctl is-enabled --quiet "$SERVICE_NAME" >/dev/null 2>&1
    return $?
  fi
  if has_openrc; then
    rc-update show default 2>/dev/null | grep -q "^${SERVICE_NAME}[[:space:]]"
    return $?
  fi
  return 1
}

print_status() {
  load_conf

  if service_running; then
    run_state="运行中"
  else
    run_state="未运行"
  fi

  if boot_enabled; then
    boot_state="已启用"
  else
    boot_state="未启用"
  fi

  show_user="${USERNAME:-未配置}"
  show_pass="${PASSWORD:-未配置}"
  show_port="${PORT:-未配置}"

  echo "=============================="
  echo "运行状态: ${run_state}"
  echo "开机启动: ${boot_state}"
  echo "账号: ${show_user}"
  echo "密码: ${show_pass}"
  echo "端口: ${show_port}"
  echo "=============================="
}

setup_flow() {
  printf "请输入账号: "
  read -r USERNAME_INPUT
  if [ -z "$USERNAME_INPUT" ]; then
    PASSWORD_INPUT=""
    echo "已设置为无账号密码"
  else
    printf "请输入密码: "
    read -r PASSWORD_INPUT
    [ -z "$PASSWORD_INPUT" ] && { err "密码不能为空"; return 1; }
  fi

  printf "请输入端口: "
  read -r PORT_INPUT
  if ! validate_port "$PORT_INPUT"; then
    err "端口不合法(1-65535)"
    return 1
  fi

  USERNAME="$USERNAME_INPUT"
  PASSWORD="$PASSWORD_INPUT"
  PORT="$PORT_INPUT"

  install_dependencies || return 1
  save_conf
  enable_and_start_service || return 1

  echo "配置完成，已加入开机启动并启动服务"
  return 0
}

start_flow() {
  load_conf
  if [ -z "${PORT:-}" ]; then
    err "未检测到完整配置，请先执行设置"
    return 1
  fi

  if [ -n "${USERNAME:-}" ] && [ -z "${PASSWORD:-}" ]; then
    err "账号已配置但密码缺失，请先执行设置"
    return 1
  fi

  install_dependencies || return 1
  enable_and_start_service || return 1
  echo "服务已启动，且已加入开机启动"
}

stop_flow() {
  disable_and_stop_service || return 1
  echo "服务已停止，开机启动项已删除"
}

main_menu() {
  while true; do
    print_status
    echo "1) 设置"
    echo "2) 停止服务"
    echo "3) 启动服务"
    echo "0) 退出"
    printf "请选择: "
    read -r choice

    case "$choice" in
      1)
        setup_flow
        ;;
      2)
        stop_flow
        ;;
      3)
        start_flow
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选项"
        ;;
    esac
    echo
  done
}

if ! is_root; then
  err "请使用 root 运行此脚本"
  exit 1
fi

main_menu
