#!/bin/bash
# 文件：/usr/local/bin/update_cloudflare_ufw.sh
# 功能：只更新 Cloudflare IP 访问规则，保留你其他 UFW 设置

set -e

echo "[INFO] Updating Cloudflare IP ranges..."

# 删除旧的 Cloudflare 规则（带注释 Cloudflare）
for num in $(sudo ufw status numbered | grep -n "Cloudflare" | awk -F'[][]' '{print $2}' | sort -rn); do
    sudo ufw --force delete $num
done

# 添加新的 IPv4
for ip in $(curl -s https://www.cloudflare.com/ips-v4); do
    sudo ufw allow from $ip to any port 80,443 proto tcp comment 'Cloudflare'
done

# 添加新的 IPv6
for ip in $(curl -s https://www.cloudflare.com/ips-v6); do
    sudo ufw allow from $ip to any port 80,443 proto tcp comment 'Cloudflare'
done



sudo ufw --force enable

echo "[INFO] Cloudflare IP list updated successfully!"
