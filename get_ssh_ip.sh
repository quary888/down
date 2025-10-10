#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# 解析 IPv4/IPv6 地址（去掉端口，IPv6 保留方括号）
parse_ip() {
    local addr="$1"
    if [[ "$addr" =~ ^\[.*\]: ]]; then
        echo "${addr%\]*}]"   # IPv6
    else
        echo "${addr%:*}"     # IPv4
    fi
}

# 遍历 ESTAB 的 sshd/dropbear 连接
ss -tnp | grep ESTAB | grep -E 'sshd|dropbear' | while read -r line; do
    # 提取 PID
    pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]\+\).*/\1/p')
    [[ -z "$pid" ]] && continue

    # 提取本地 IP 和远程 IP
    local_ip=$(parse_ip "$(echo "$line" | awk '{print $4}')")
    remote_ip=$(parse_ip "$(echo "$line" | awk '{print $5}')")

    # 输出纯净格式
    echo "$pid $local_ip $remote_ip"
done
