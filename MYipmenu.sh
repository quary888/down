#!/bin/bash

# ================== 配置 ==================
URL="https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md"
PERSIST_DIR="/etc/ipset"
TMP_RAW="/tmp/iplist_raw.txt"
TARGET_PATH="/usr/bin/MYipmenu"

sudo mkdir -p "$PERSIST_DIR"

# ================== 自我移动和开机延时执行 ==================
if [ "$(readlink -f "$0")" != "$TARGET_PATH" ]; then
    echo "📦 移动脚本到 $TARGET_PATH"
    sudo cp "$0" "$TARGET_PATH"
    sudo chmod +x "$TARGET_PATH"
    
    # 创建 systemd 延时启动服务
    SERVICE_FILE="/etc/systemd/system/MYipmenu.service"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Restore ipset collections and iptables rules with delay
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $TARGET_PATH S
TimeoutStartSec=60
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable MYipmenu.service
    sudo systemctl start MYipmenu.service
    echo "✅ 脚本已安装并开机自动延时执行"
    exit 0
fi

# ================== 依赖检查 ==================
检查依赖() {
    declare -a deps=("curl" "ipset" "iptables")
    for cmd in "${deps[@]}"; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "⚠️ 系统缺少依赖: $cmd, 自动安装..."
            sudo apt-get update
            sudo apt-get install -y $cmd
        fi
    done
}
检查依赖

# ================== 下载和解析 ==================
下载数据() {
    if [ ! -f "$TMP_RAW" ]; then
        echo "📥 下载省市列表..."
        TMPFILE=$(mktemp)
        curl -s "$URL" -o "$TMPFILE" || { echo "❌ 下载失败"; exit 1; }
        grep -E '^\|[^|]+\|https' "$TMPFILE" > "$TMP_RAW"
        rm -f "$TMPFILE"
    fi
}

解析数据() {
    下载数据
    declare -gA province_map
    declare -gA city_map
    current_province=""
    while IFS='|' read -r _ name link _; do
        name=$(echo "$name" | tr -d ' ')
        link=$(echo "$link" | tr -d ' ')
        if [[ "$link" =~ cncity/[0-9]{2}0000\.txt$ ]]; then
            current_province="$name"
            province_map["$name"]="$link"
        else
            if [ -n "$current_province" ]; then
                city_map["$current_province"]+="$name|$link "
            fi
        fi
    done < "$TMP_RAW"
}

# ================== 工具函数 ==================
删除集合() {
    local setname="$1"
    while iptables -D INPUT -m set --match-set "$setname" src -j ACCEPT 2>/dev/null; do :; done
    ipset destroy "$setname" 2>/dev/null
    rm -f "$PERSIST_DIR/${setname}.ipset"
}

清空所有() {
    echo "🧹 删除所有 ipset 白名单..."
    for setname in $(ipset list -n | grep '^whitelist_'); do
        删除集合 "$setname"
        echo "  - 删除 $setname"
    done
    echo "✅ 所有 whitelist 集合已清除"
}

添加数据() {
    local name="$1"
    local url="$2"
    local setname="whitelist_${name}"

    if [[ "$url" == "无" || -z "$url" ]]; then
        echo "⚠️ $name 没有对应数据"
        return
    fi

    echo "🚀 处理：$name ($url)"
    TMPIP=$(mktemp)
    curl -s "$url" -o "$TMPIP"

    if ipset list -n | grep -q "$setname"; then
        删除集合 "$setname"
    fi

    ipset create "$setname" hash:net 2>/dev/null || true
    grep -v '^$' "$TMPIP" | xargs -I{} ipset add "$setname" {} 2>/dev/null
    iptables -C INPUT -m set --match-set "$setname" src -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -m set --match-set "$setname" src -j ACCEPT
    ipset save "$setname" > "$PERSIST_DIR/${setname}.ipset"

    echo "✅ 已添加 $name 白名单集合 ($setname)"
}

# ================== 列出规则 ==================
列出规则() {
    mapfile -t sets < <(ipset list -n | grep '^whitelist_')
    if [ ${#sets[@]} -eq 0 ]; then
        echo "❌ 当前没有任何白名单集合"
        return
    fi
    while true; do
        echo "当前白名单集合："
        for i in "${!sets[@]}"; do
            echo "$((i+1))) ${sets[$i]}"
        done
        read -p "输入编号删除对应集合（回车返回上级菜单）: " sel
        if [ -z "$sel" ]; then
            break
        elif [[ "$sel" -ge 1 && "$sel" -le ${#sets[@]} ]]; then
            删除集合 "${sets[$((sel-1))]}"
            echo "✅ 已删除 ${sets[$((sel-1))]}"
            mapfile -t sets < <(ipset list -n | grep '^whitelist_')
        else
            echo "❌ 无效编号"
        fi
    done
}

更新规则() {
    解析数据
    echo "🌀 更新已添加集合..."
    mapfile -t sets < <(ipset list -n | grep '^whitelist_')
    for setname in "${sets[@]}"; do
        name="${setname#whitelist_}"
        url="${province_map[$name]}"
        if [ -z "$url" ]; then
            for prov in "${!city_map[@]}"; do
                for pair in ${city_map[$prov]}; do
                    city="${pair%%|*}"
                    link="${pair##*|}"
                    if [[ "$city" == "$name" ]]; then
                        url="$link"
                        break 2
                    fi
                done
            done
        fi
        if [ -z "$url" ]; then
            echo "⚠️ 找不到 $name 的数据"
            continue
        fi
        删除集合 "$setname"
        添加数据 "$name" "$url"
    done
    echo "✅ 已完成更新"
}

# ================== 开机 restore 模式 ==================
if [ "$1" == "S" ]; then
    echo "⏱️ 开机延时30秒后恢复 ipset 集合和 iptables 规则..."
    sleep 30
    for f in $PERSIST_DIR/whitelist_*.ipset; do
        [ -f "$f" ] || continue
        setname=$(basename "$f" .ipset)
        ipset restore < "$f"
        iptables -C INPUT -m set --match-set "$setname" src -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -m set --match-set "$setname" src -j ACCEPT
    done
    echo "✅ 开机 restore 完成"
    exit 0
fi

# ================== 参数模式 ==================
if [ "$1" == "D" ]; then
    清空所有
    exit 0
elif [ "$1" == "U" ]; then
    更新规则
    exit 0
elif [ -n "$1" ]; then
    解析数据
    prov="$1"
    url="${province_map[$prov]}"
    if [ -z "$url" ]; then
        echo "❌ 未找到省份: $prov"
        exit 1
    fi
    添加数据 "$prov" "$url"
    exit 0
fi

# ================== 主菜单 ==================
while true; do
    echo "零级菜单 - 请选择操作："
    echo "0) 列出规则"
    echo "1) 添加规则"
    echo "2) 清空规则"
    echo "3) 更新规则"
    read -p "输入编号（回车退出）: " choice
    if [ -z "$choice" ]; then
        break
    fi
    case "$choice" in
        0) 列出规则 ;;
        1)
            解析数据
            while true; do
                echo "一级菜单 - 请选择省份（回车返回上级菜单）："
                i=1
                for prov in "${!province_map[@]}"; do
                    echo "$i) $prov"
                    prov_index[$i]="$prov"
                    ((i++))
                done
                read -p "输入编号: " sel
                if [ -z "$sel" ]; then
                    break
                fi
                province="${prov_index[$sel]}"
                if [ -z "$province" ]; then
                    echo "❌ 无效编号"
                    continue
                fi

                while true; do
                    echo -e "\n你选择的是: $province"
                    echo "二级菜单 - 请选择城市（回车返回上一级省份菜单）："
                    j=1
                    echo "0) 全部添加（仅省级数据）"
                    for pair in ${city_map[$province]}; do
                        city="${pair%%|*}"
                        link="${pair##*|}"
                        echo "$j) $city"
                        city_index[$j]="$city|$link"
                        ((j++))
                    done
                    read -p "输入编号: " sub_choice
                    if [ -z "$sub_choice" ]; then
                        break
                    fi
                    if [ "$sub_choice" == "0" ]; then
                        添加数据 "$province" "${province_map[$province]}"
                    else
                        selected="${city_index[$sub_choice]}"
                        if [ -z "$selected" ]; then
                            echo "❌ 无效编号"
                            continue
                        fi
                        city="${selected%%|*}"
                        link="${selected##*|}"
                        添加数据 "$city" "$link"
                    fi
                done
            done
            ;;
        2) 清空所有 ;;
        3) 更新规则 ;;
        *) echo "❌ 无效选择" ;;
    esac
done
