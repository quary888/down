#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ===== 彩色输出 =====
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"
red(){ printf "${RED}%s${RESET}\n" "$1"; }
green(){ printf "${GREEN}%s${RESET}\n" "$1"; }
yellow(){ printf "${YELLOW}%s${RESET}\n" "$1"; }

# ===== 权限检测 =====
if [ "$(id -u)" -ne 0 ]; then
    red "请以 root 用户运行此脚本。"
    exit 1
fi

# ===== 准备目录 =====
mkdir -p /opt/xray

# ===== 输入信息 =====
read -rp "请输入 SOCKS5 监听端口 (1-65535): " port
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    red "端口不合法：$port"
    exit 1
fi

read -rp "请输入 SOCKS5 用户名: " user
[ -z "$user" ] && { red "用户名不能为空"; exit 1; }

# 密码输入可见
read -rp "请输入 SOCKS5 密码: " pass
[ -z "$pass" ] && { red "密码不能为空"; exit 1; }

OUT_FILE="/opt/xray/s5.json"

# ===== 生成配置文件 =====
cat > "$OUT_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $port,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          { "user": "$(printf '%s' "$user" | sed 's/"/\\"/g')", "pass": "$(printf '%s' "$pass" | sed 's/"/\\"/g')" }
        ],
        "udp": true,
        "ip": "127.0.0.1"
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF

chmod 600 "$OUT_FILE"
green "配置已保存：$OUT_FILE"

# ===== 写入 crontab（防重复） =====
CRON_CMD='@reboot sleep 60 && /opt/xray/xray -c /opt/xray/s5.json'
if crontab -l 2>/dev/null | grep -Fq "$CRON_CMD"; then
    yellow "crontab 已存在该任务，无需重复添加。"
else
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    green "已添加到 crontab: $CRON_CMD"
fi

# ===== 检查并启动 Xray =====
XRAY_BIN="/opt/xray/xray"
if [ -x "$XRAY_BIN" ]; then
    green "检测到 Xray 可执行文件：$XRAY_BIN"
    echo "正在启动 Xray..."
    pkill -f "$XRAY_BIN" 2>/dev/null || true  # 停掉旧进程
    nohup "$XRAY_BIN" -c "$OUT_FILE" >/opt/xray/xray.log 2>&1 &
    sleep 1
    if pgrep -f "$XRAY_BIN" >/dev/null; then
        green "✅ Xray 已成功启动 (后台运行)"
        yellow "日志文件：/opt/xray/xray.log"
    else
        red "❌ 启动失败，请检查日志：/opt/xray/xray.log"
    fi
else
    red "未找到 /opt/xray/xray，请先安装 Xray 到该目录！"
fi

green "全部完成。"
