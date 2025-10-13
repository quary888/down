#!/usr/bin/env bash
# ��������ű����ñ��ű�  ��Ҫʹ�� 'set -euo pipefail'


IFS=$'\n\t'

# ���� IPv4/IPv6 ��ַ��ȥ���˿ڣ�IPv6 ���������ţ�
parse_ip() {
    local addr="$1"
    if [[ "$addr" =~ ^\[.*\]: ]]; then
        echo "${addr%\]*}]"    # IPv6
    else
        echo "${addr%:*}"      # IPv4
    fi
}

# ��ʱ����������
tmpfile=$(mktemp)

# ���� ESTAB �� sshd/dropbear ����
ss -tnp | grep ESTAB | grep -E 'sshd|dropbear' | while read -r line; do
    pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]\+\).*/\1/p')
    [[ -z "$pid" ]] && continue

    local_ip=$(parse_ip "$(echo "$line" | awk '{print $4}')")
    remote_ip=$(parse_ip "$(echo "$line" | awk '{print $5}')")

    echo "$pid $local_ip $remote_ip" >> "$tmpfile"
done

# ȥ���ظ��� remote_ip�����ֵ�һ�γ��ֵ��У�
awk '!seen[$3]++' "$tmpfile"

rm -f "$tmpfile"
exit 0
