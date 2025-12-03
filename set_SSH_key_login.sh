#!/bin/bash

RED="\033[31m"
GREEN="\033[1;32m"
END="\033[0m"

INFO="[${GREEN}INFO${END}]"
ERROR="[${RED}ERROR${END}]"

[ $EUID != 0 ] && SUDO=sudo

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_D="/etc/ssh/sshd_config.d"

########################################
# 无参数 → 启用密码登录模式
########################################
if [ $# -lt 1 ]; then
    echo -e "${INFO} No PUB_KEY_URL provided. Enabling password login..."

    $SUDO sed -i 's@^#*PasswordAuthentication .*@PasswordAuthentication yes@g' "$SSHD_CONFIG"
    $SUDO sed -i 's@^#*KbdInteractiveAuthentication .*@KbdInteractiveAuthentication yes@g' "$SSHD_CONFIG"

    if [ -d "$SSHD_D" ]; then
        for f in $SSHD_D/*.conf; do
            [ -f "$f" ] || continue
            $SUDO sed -i 's@^PasswordAuthentication.*@PasswordAuthentication yes@g' "$f"
            $SUDO sed -i 's@^#*PasswordAuthentication.*@PasswordAuthentication yes@g' "$f"
            $SUDO sed -i 's@^KbdInteractiveAuthentication.*@KbdInteractiveAuthentication yes@g' "$f"
            $SUDO sed -i 's@^#*KbdInteractiveAuthentication.*@KbdInteractiveAuthentication yes@g' "$f"
        done
    fi

    echo -e "${INFO} Password login enabled. Restarting sshd..."
    if systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null || rc-service sshd restart 2>/dev/null; then
        echo -e "${INFO} SSHD restarted."
    else
        echo -e "${ERROR} Cannot restart sshd. Restart manually."
    fi
    exit 0
fi

########################################
# 有参数 → 正常密钥安装 & 禁用密码
########################################

PUB_KEY_URL="$1"
echo -e "${INFO} Fetching SSH public key from: $PUB_KEY_URL"

PUB_KEY=$(curl -fsSL "${PUB_KEY_URL}")
if [ -z "$PUB_KEY" ]; then
    echo -e "${ERROR} Failed to fetch public key."
    exit 1
fi

echo -e "${INFO} Preparing ~/.ssh directory..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo -e "${INFO} Installing SSH key (overwrite mode)..."
echo "${PUB_KEY}" > ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo -e "${INFO} Securing SSH configuration..."

# 强制开启密钥登录
$SUDO sed -i 's@^#*PubkeyAuthentication .*@PubkeyAuthentication yes@g' "$SSHD_CONFIG"

if [ -d "$SSHD_D" ]; then
    for f in $SSHD_D/*.conf; do
        [ -f "$f" ] || continue
        $SUDO sed -i 's@^PubkeyAuthentication.*@PubkeyAuthentication yes@g' "$f"
    done
fi

# root 允许密钥
$SUDO sed -i 's@^#*PermitRootLogin .*@PermitRootLogin yes@g' "$SSHD_CONFIG"

# 禁用密码
$SUDO sed -i 's@^#*PasswordAuthentication .*@PasswordAuthentication no@g' "$SSHD_CONFIG"
$SUDO sed -i 's@^#*KbdInteractiveAuthentication .*@KbdInteractiveAuthentication no@g' "$SSHD_CONFIG"

if [ -d "$SSHD_D" ]; then
    for f in $SSHD_D/*.conf; do
        [ -f "$f" ] || continue
        $SUDO sed -i 's@^PasswordAuthentication.*@PasswordAuthentication no@g' "$f"
        $SUDO sed -i 's@^#*PasswordAuthentication.*@PasswordAuthentication no@g' "$f"
        $SUDO sed -i 's@^KbdInteractiveAuthentication.*@KbdInteractiveAuthentication no@g' "$f"
        $SUDO sed -i 's@^#*KbdInteractiveAuthentication.*@KbdInteractiveAuthentication no@g' "$f"
    done
fi

echo -e "${INFO} Restarting sshd..."
if systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null || rc-service sshd restart 2>/dev/null; then
    echo -e "${INFO} SSHD restarted successfully."
else
    echo -e "${ERROR} Failed to restart sshd."
    exit 1
fi

echo -e "${INFO} SSH key setup completed with enhanced security."
