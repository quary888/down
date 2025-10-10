#!/usr/bin/env bash
set -euo pipefail
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

# ���� ESTAB �� sshd/dropbear ����
ss -tnp | grep ESTAB | grep -E 'sshd|dropbear' | while read -r line; do
    # ��ȡ PID
    pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]\+\).*/\1/p')
    [[ -z "$pid" ]] && continue

    # ��ȡ���� IP ��Զ�� IP
    local_ip=$(parse_ip "$(echo "$line" | awk '{print $4}')")
    remote_ip=$(parse_ip "$(echo "$line" | awk '{print $5}')")

    # ���������ʽ
    echo "$pid $local_ip $remote_ip"
    
    # �ؼ��޸ģ������һ������������˳��ű�
    # ȷ�����ű��Ĺܵ��ܹ��ɾ��رգ����� set -e ����
    exit 0 
done

# ���ѭ��û���ҵ��κ� ESTAB ���Ӿͽ������ű��������˳���
exit 0 