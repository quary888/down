#!/usr/bin/env bash
# 如果其它脚本调用本脚本  不要使用 'set -euo pipefail'


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

# 临时保存输出结果
tmpfile=$(mktemp)

# 遍历 ESTAB 的 sshd/dropbear 连接
ss -tnp | grep ESTAB | grep -E 'sshd|dropbear' | while read -r line; do
    pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]\+\).*/\1/p')
    [[ -z "$pid" ]] && continue

    local_ip=$(parse_ip "$(echo "$line" | awk '{print $4}')")
    remote_ip=$(parse_ip "$(echo "$line" | awk '{print $5}')")

    echo "$pid $local_ip $remote_ip" >> "$tmpfile"
done

# 去掉重复的 remote_ip（保持第一次出现的行）
awk '!seen[$3]++' "$tmpfile"

rm -f "$tmpfile"
exit 0
