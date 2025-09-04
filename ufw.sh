#!/bin/sh
set -e

# 检测系统类型
if [ -f /etc/debian_version ]; then
    echo "[INFO] Debian/Ubuntu 系统检测到"

    # 更新包列表并安装 ufw
    apt-get update -y
    apt-get install -y ufw jq

    # 确保允许 SSH，否则可能断连
    ufw allow ssh

    # 启用 ufw（--force 跳过交互确认）
    ufw --force enable

    # 确保 ufw 开机启动
    systemctl enable ufw
    systemctl start ufw

elif [ -f /etc/alpine-release ]; then
    echo "[INFO] Alpine 系统检测到"

    apk update
    # Alpine 默认源未必有 ufw，可能要用 edge/testing
    if ! apk add ufw jq 2>/dev/null; then
        echo "[WARN] 默认仓库没有 ufw，尝试使用 edge/testing..."
        apk add ufw jq --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing
    fi

    # 允许 SSH
    ufw allow ssh

    # 启用 ufw
    ufw --force enable

    # 设置开机启动
    echo -e '#!/bin/sh\nufw --force enable' | tee /etc/local.d/ufw.start > /dev/null
    chmod +x /etc/local.d/ufw.start
    rc-update add local

else
    echo "[ERROR] 不支持的系统类型"
    exit 1
fi

# 配置 Docker 不自动修改 iptables
echo "[INFO] 配置 Docker daemon.json"
mkdir -p /etc/docker

if [ -f /etc/docker/daemon.json ]; then
    # 合并配置，不覆盖已有内容
    tmpfile=$(mktemp)
    jq '. + {"iptables": false}' /etc/docker/daemon.json > "$tmpfile" && mv "$tmpfile" /etc/docker/daemon.json
else
    echo '{ "iptables": false }' | tee /etc/docker/daemon.json > /dev/null
fi

# 重启 Docker
if systemctl list-unit-files | grep -q docker.service; then
    systemctl restart docker
elif rc-status | grep -q docker; then
    rc-service docker restart
else
    echo "[WARN] 未检测到 systemd 或 openrc 的 docker 服务，请手动重启 docker"
fi

echo "[INFO] UFW 已安装并启用，Docker 已禁用自动修改 iptables"
