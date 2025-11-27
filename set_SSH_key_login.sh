#!/bin/bash

RED="\033[31m"
GREEN="\033[1;32m"
END="\033[0m"

INFO="[${GREEN}INFO${END}]"
ERROR="[${RED}ERROR${END}]"

[ $EUID != 0 ] && SUDO=sudo

#---------------------------
# 参数检查
#---------------------------
if [ $# -lt 1 ]; then
    echo -e "${ERROR} Missing URL argument."
    echo "Usage: bash <(curl -fsSL script.sh) <URL>"
    exit 1
fi

PUB_KEY_URL="$1"

#---------------------------
# 获取公钥
#---------------------------
echo -e "${INFO} Fetching SSH public key from: $PUB_KEY_URL"
PUB_KEY=$(curl -fsSL "${PUB_KEY_URL}")
if [ -z "$PUB_KEY" ]; then
    echo -e "${ERROR} Failed to fetch public key."
    exit 1
fi

#---------------------------
# 创建 .ssh 与权限
#---------------------------
echo -e "${INFO} Preparing ~/.ssh directory..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo -e "${INFO} Installing SSH key (overwrite mode)..."
echo "${PUB_KEY}" > ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

#---------------------------
# 禁用密码登录（强制禁密修复所有覆盖文件）
#---------------------------
echo -e "${INFO} Disabling password login (full override)..."

SSHD_CONFIG="/etc/ssh/sshd_config"

# 修改主配置
$SUDO sed -i 's@^#*PasswordAuthentication .*@PasswordAuthentication no@g' "$SSHD_CONFIG"
$SUDO sed -i 's@^#*PermitRootLogin .*@PermitRootLogin prohibit-password@g' "$SSHD_CONFIG"

# 禁用 sshd_config.d 内所有 yes
if [ -d /etc/ssh/sshd_config.d ]; then
    for f in /etc/ssh/sshd_config.d/*.conf; do
        [ -f "$f" ] || continue
        $SUDO sed -i 's@^PasswordAuthentication.*@PasswordAuthentication no@g' "$f"
        $SUDO sed -i 's@^#*PasswordAuthentication.*@PasswordAuthentication no@g' "$f"
    done
fi

#---------------------------
# 自动识别系统并重启 sshd
#---------------------------
restart_sshd() {
    if command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl restart sshd && return 0
    fi
    if command -v rc-service >/dev/null 2>&1; then
        $SUDO rc-service sshd restart && return 0
    fi
    if command -v service >/dev/null 2>&1; then
        $SUDO service sshd restart && return 0
    fi
    return 1
}

echo -e "${INFO} Restarting sshd..."
if restart_sshd; then
    echo -e "${INFO} SSHD restarted successfully."
else
    echo -e "${ERROR} Failed to restart sshd. Please restart manually."
    exit 1
fi

echo -e "${INFO} SSH key setup completed."
