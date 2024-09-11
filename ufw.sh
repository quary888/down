#!/bin/sh

# 检测系统类型
if [ -f /etc/debian_version ]; then
    echo "Debian-based system detected."
    
    # 更新包列表
    apt-get update

    # 安装 ufw
    apt-get install -y ufw

    # 启用 ufw
    ufw enable

    # 创建 systemd 服务文件以确保 ufw 在启动时自动启用
    tee /etc/systemd/system/ufw.service > /dev/null <<EOL
[Unit]
Description=Uncomplicated Firewall
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ufw enable
ExecReload=/usr/sbin/ufw reload
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOL

    # 重新加载 systemd 配置
    systemctl daemon-reload

    # 启用并启动 ufw 服务
    systemctl enable ufw
    systemctl start ufw

elif [ -f /etc/alpine-release ]; then
    echo "Alpine Linux detected."
    
    # 更新包列表
    apk update

    # 安装 ufw
    apk add ufw

    # 启用 ufw
    ufw enable

    # 创建本地启动脚本
    echo -e '#!/bin/sh\nufw enable' | tee /etc/local.d/ufw.start > /dev/null
    chmod +x /etc/local.d/ufw.start

    # 启用 local 服务
    rc-update add local

else
    echo "Unsupported system type."
    exit 1
fi

echo "ufw has been installed and configured to start on boot."
