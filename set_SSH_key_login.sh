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
    echo "Usage: bash <(curl -fsSL script.sh) <PUB_KEY_URL>"
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
# 强化 SSH 配置（绝不禁止 pubkey）
#---------------------------
SSHD_CONFIG="/etc/ssh/sshd_config"

echo -e "${INFO} Securing SSH configuration..."

# 保证 key 登录永远开启
$SUDO sed -i 's@^#*PubkeyAuthentication .*@PubkeyAuthentication yes@g' "$SSHD_CONFIG"

# 防止 Include 覆盖 pubkey
if [ -d /etc/ssh/sshd_config.d ]; then
    for f in /etc/ssh/sshd_config.d/*.conf; do
        [ -f "$f" ] || continue
        $SUDO sed -i 's@^PubkeyAuthentication.*@PubkeyAuthentication yes@g' "$f"
    done
fi

# 确保 root 能用密钥登录
$SUDO sed -i 's@^#*PermitRootLogin .*@PermitRootLogin yes@g' "$SSHD_CONFIG"

# 禁用密码，不影响 pubkey
$SUDO sed -i 's@^#*PasswordAuthentication .*@PasswordAuthentication no@g' "$SSHD_CONFIG"

# 禁止 challenge/keyboard interactive
$SUDO sed -i 's@^#*KbdInteractiveAuthentication .*@KbdInteractiveAuthentication no@g' "$SSHD_CONFIG"

#---------------------------
# 清理 include 文件中的 password 设置
#---------------------------
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

echo -e "${INFO} SSH key setup completed with enhanced security."
