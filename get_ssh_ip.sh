#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# 解析 IPv4/IPv6 地址（去掉端口，IPv6 保留方括号）
parse_ip() {
    local addr="$1"
    if [[ "$addr" =~ ^\[.*\]: ]]; then
        echo "${addr%\]*}]"    # IPv6
    else
        echo "${addr%:*}"      # IPv4
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
    
    # 关键修改：输出第一个结果后立即退出脚本
    # 确保主脚本的管道能够干净关闭，避免 set -e 触发
    exit 0 
done

# 如果循环没有找到任何 ESTAB 连接就结束，脚本会正常退出。
exit 0 