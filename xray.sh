#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ========= 颜色输出 =========
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"
red(){ printf "${RED}%s${RESET}\n" "$1"; }
green(){ printf "${GREEN}%s${RESET}\n" "$1"; }
yellow(){ printf "${YELLOW}%s${RESET}\n" "$1"; }

# ========= 必须 root =========
[ "$(id -u)" -eq 0 ] || { red "请使用 root 运行"; exit 1; }

# ========= 输出信息 =========
yellow "s5 自定义路由用法"
yellow "脚本所在目录 新建 *.socks5.txt 内容为:"
green "IP&端口&账号&密码 #第一行 s5配置信息"
green "a.com             #之后每一行一个域名"

read -n 1 -s -r -p "按任意键继续..."
echo


# ========= 安装依赖 =========
DEPENDENCIES=(curl wget unzip nc awk sed grep ss jq xxd)
install_pkg() {
    pkg="$1"
    yellow "检测到缺少 $pkg，尝试安装..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        [[ "$pkg" == "ss" ]] && pkg="iproute2"
        apt-get install -y "$pkg"
    elif command -v apk >/dev/null 2>&1; then
        [[ "$pkg" == "ss" ]] && pkg="iproute2"
        apk add --no-cache "$pkg"
    else
        red "当前系统不支持自动安装 $pkg，请手动安装"
        exit 1
    fi
}
for cmd in "${DEPENDENCIES[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || install_pkg "$cmd"
done

# ========= 安装目录 =========
INSTALL_DIR="/opt/xray"; BIN_PATH="$INSTALL_DIR/xray"
CONFIG_PATH="$INSTALL_DIR/config.json"; SHARE_LINK_PATH="$INSTALL_DIR/share-link.txt"
mkdir -p "$INSTALL_DIR"

# ========= 结束所有 xray 进程 =========
if pgrep -x xray >/dev/null 2>&1; then
    yellow "检测到正在运行的 xray，尝试停止..."
    pkill -9 xray
    sleep 1
    green "已结束所有 xray 进程"
fi


# ========= 下载 Xray =========
re_download=false
if [ -f "$BIN_PATH" ]; then
    read -rp "Xray 已存在，是否重新下载(默认否)[y/N]: " yn
    yn=${yn:-N}
    [[ "$yn" =~ ^[Yy]$ ]] && re_download=true
else
    re_download=true
fi

if $re_download; then
    yellow "获取 Xray 最新 release..."
    curl -sSfL https://api.github.com/repos/XTLS/Xray-core/releases/latest > /tmp/xray_release.json
    green "GitHub release JSON 已保存到 /tmp/xray_release.json"

    arch=$(uname -m)
    case "$arch" in
        x86_64) pattern="Xray-linux-64.zip" ;;
        i386|i686) pattern="Xray-linux-32.zip" ;;
        aarch64) pattern="Xray-linux-arm64.zip" ;;
        armv7*|armhf) pattern="Xray-linux-arm.zip" ;;
        *) red "未知架构 $arch"; exit 1 ;;
    esac
    green "系统架构: $arch -> 匹配文件: $pattern"

    asset_url=$(jq -r --arg pat "$pattern" '.assets[] | select(.name==$pat) | .browser_download_url' /tmp/xray_release.json)
    [ -n "$asset_url" ] || { red "未找到匹配的 Xray Linux 文件 ($pattern)"; exit 1; }
    green "下载地址: $asset_url"

    tmpzip="/tmp/xray_$(date +%s).zip"
    yellow "下载中..."
    wget -O "$tmpzip" "$asset_url"
    green "下载完成: $tmpzip"

    yellow "解压..."
    unzip -o "$tmpzip" -d "$INSTALL_DIR"
    rm -f "$tmpzip" "$INSTALL_DIR/geoip.dat" "$INSTALL_DIR/geosite.dat"
    green "已清理压缩包和 .dat 文件"

    if [ -f "$INSTALL_DIR/xray" ]; then
        green "xray 文件存在"
    elif [ -f "$INSTALL_DIR/Xray" ]; then
        mv "$INSTALL_DIR/Xray" "$INSTALL_DIR/xray"
        chmod +x "$INSTALL_DIR/xray"
        green "Xray 重命名并设置可执行权限"
    else
        red "解压后找不到 xray 文件"
        exit 1
    fi
else
    green "保留现有 Xray 文件: $BIN_PATH"
fi

# ========= Reality 配置生成函数 =========
generate_reality_config() {
    local port="$1"
    local dest_server="$2"

    UUID=$("$BIN_PATH" uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    green "UUID: $UUID"

    keys=$("$BIN_PATH" x25519 2>&1)
    echo "$keys" > "$INSTALL_DIR/keys.txt"
    green "x25519 key 已生成并写入 $INSTALL_DIR/keys.txt"

    private_key=$(echo "$keys" | awk -F':' '/PrivateKey/ {gsub(/ /,"",$2); print $2}')
    password=$(echo "$keys" | awk -F':' '/Password/ {gsub(/ /,"",$2); print $2}')
    short_id=$(xxd -p -l 4 /dev/urandom)

    [ -n "$private_key" ] || { red "解析 private_key 失败"; exit 1; }
    [ -n "$password" ] || { red "解析 pbk 失败"; exit 1; }

    green "private_key: $private_key"
    green "pbk (Password): $password"
    green "short_id: $short_id"

    REALITY_INBOUND=$(cat <<EOF
{
  "listen":"0.0.0.0",
  "port":$port,
  "protocol":"vless",
  "settings":{"clients":[{"id":"$UUID","flow":"xtls-rprx-vision"}],"decryption":"none"},
  "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"$dest_server:443","xver":0,"serverNames":["$dest_server"],"privateKey":"$private_key","shortIds":["$short_id"]}}
}
EOF
)

    # ========= 使用 获取本地 IP =========
    # 获取 IP
    IP1=$(bash <(wget -qO- -o- https://raw.githubusercontent.com/quary888/down/main/get_ssh_ip.sh) | head -n1 | awk '{print $2}')
    ip2=$(curl -6 -s --max-time 5 ipv6.icanhazip.com)
    ip3=$(curl -4 -s --max-time 5 ipv4.icanhazip.com)
    IP=""
    # 给 IPv6 前后加方括号
    [ -n "$ip2" ] && ip2="[$ip2]"

    # 显示 IP 列表
    echo "IP 列表："
    echo "1) $IP1"
    echo "2) $ip2"
    echo "3) $ip3"

    # 交互式选择
    while true; do
      read -rp "请选择入口IP (1/2/3): " choice
      case "$choice" in
        1) IP="$IP1"; break ;;
        2) 
           if [ -n "$ip2" ]; then 
             IP="$ip2"
             break
           else
             echo "IPv6 IP 不可用，请重新选择。"
           fi
           ;;
        3) IP="$ip3"; break ;;
        *) echo "输入不正确，请输入 1、2 或 3。" ;;
      esac
    done

    echo "你选择的 IP 是：$IP"



    
    

    red "请检查入口IP是否正确,有些小鸡出口入口IP不一样!"

    share_link="vless://$UUID@$IP:$port?encryption=none&flow=xtls-rprx-vision&security=reality&type=tcp&sni=$dest_server&fp=chrome&pbk=$password&sid=$short_id#Xray-Reality"
    printf "%s\n" "$share_link" > "$SHARE_LINK_PATH"
    green "分享链接已保存到 $SHARE_LINK_PATH"
    yellow "$share_link"
}

# ========= 检查 config.json 是否存在 =========
if [ -f "$CONFIG_PATH" ]; then
    read -rp "配置 已存在，是否重新生成(默认否)[y/N]: " regen
    regen=${regen:-N}
else
    regen="Y"
fi

if [[ "$regen" =~ ^[Yy]$ ]]; then
    DEFAULT_BUFFER=1024
    read -rp "设置 bufferSize(KB)(低配默认即可 否则BOOM) [默认 $DEFAULT_BUFFER]: " BUFFER_SIZE
    BUFFER_SIZE=${BUFFER_SIZE:-$DEFAULT_BUFFER}
    green "bufferSize 设置为 $BUFFER_SIZE KB"

    DEFAULT_PORT=10001
    read -rp "请输入 reality 监听端口 [默认 $DEFAULT_PORT]: " port
    port=${port:-$DEFAULT_PORT}

    read -rp "请输入回落域名 [默认 www.microsoft.com]: " dest_server
    dest_server=${dest_server:-www.microsoft.com}

    generate_reality_config "$port" "$dest_server"
else
    green "保留现有 Reality 配置，只更新 SOCKS5 出站和域名路由"
    REALITY_INBOUND=$(jq '.inbounds' "$CONFIG_PATH")
fi

# ========= 读取 *.socks5.txt 并生成出站规则 =========
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCKS_FILES=("$SCRIPT_DIR"/*.socks5.txt)
SOCKS_OUTBOUNDS=()
SOCKS_RULES=()

for f in "${SOCKS_FILES[@]}"; do
    [ -f "$f" ] || continue
    yellow "检测到 SOCKS5 配置文件: $f"

    first_line=$(head -n 1 "$f" | tr -d '\r\n')
    IFS='&' read -r ip port user pass <<< "$first_line"

    if [ -z "$ip" ] || [ -z "$port" ]; then
        red "⚠️ 文件 $f 第一行格式错误: 需要 IP&端口 或 IP&端口&账号&密码"
        continue
    fi

    users_json="[]"
    [[ -n "$user" && -n "$pass" ]] && users_json="[{\"user\":\"$user\",\"pass\":\"$pass\"}]"

    # tag 直接取文件名去掉 .socks5.txt
    tag_name="$(basename "$f" .socks5.txt)"

    socks_outbound=$(cat <<EOF
{
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "$ip",
        "port": $port,
        "users": $users_json
      }
    ]
  },
  "tag": "$tag_name"
}
EOF
)

    mapfile -t domains < <(tail -n +2 "$f" | tr -d '\r' | grep -Ev '^\s*$|^#' | sed 's/^/domain:/')
    [ ${#domains[@]} -eq 0 ] && { yellow "⚠️ 文件 $f 未发现域名，跳过"; continue; }

    domain_rules=$(printf '"%s",' "${domains[@]}")
    domain_rules="[${domain_rules%,}]"

    socks_rule=$(cat <<EOF
{
  "type": "field",
  "domain": $domain_rules,
  "outboundTag": "$tag_name"
}
EOF
)

    SOCKS_OUTBOUNDS+=("$socks_outbound")
    SOCKS_RULES+=("$socks_rule")
done

# ========= 生成或更新 config.json =========
if [[ "$regen" =~ ^[Yy]$ ]]; then
    cat > "$CONFIG_PATH" <<EOF
{
  "log": {"loglevel":"warning","dnsLog":false},
  "inbounds": [$REALITY_INBOUND],
  "outbounds": [{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"blocked"}],
  "routing": {"domainStrategy":"AsIs","rules":[]},
  "policy":{"handshake":4,"connIdle":300,"bufferSize":$BUFFER_SIZE}
}
EOF
else
    tmp_cfg="${CONFIG_PATH}.tmp"
    jq '.routing |= (.routing // {domainStrategy:"AsIs",rules:[]})' "$CONFIG_PATH" > "$tmp_cfg" && mv "$tmp_cfg" "$CONFIG_PATH"
fi

# ========= 重新生成 SOCKS5 出站和路由 =========
if [ ${#SOCKS_OUTBOUNDS[@]} -gt 0 ]; then
    yellow "重新生成 SOCKS5 出站和路由..."
    tmp_cfg="${CONFIG_PATH}.tmp"

    out_json=$(printf '%s\n' "${SOCKS_OUTBOUNDS[@]}" | jq -s '.')
    rule_json=$(printf '%s\n' "${SOCKS_RULES[@]}" | jq -s '.')

    jq --argjson socks_out "$out_json" --argjson socks_rules "$rule_json" '
        # 删除旧的 outbounds 并重新创建
        .outbounds = ([{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"blocked"}] + $socks_out)
        |
        # 删除并重建路由规则
        .routing.rules = $socks_rules
        |
        # 确保 routing.domainStrategy 存在
        .routing.domainStrategy = (.routing.domainStrategy // "AsIs")
    ' "$CONFIG_PATH" > "$tmp_cfg" && mv "$tmp_cfg" "$CONFIG_PATH"

    green "✅ 已重新生成 SOCKS5 出站和路由模块"
else
    yellow "未检测到 SOCKS5 配置，跳过"
fi

# ========= systemd / OpenRC 启动 Xray =========
if command -v systemctl >/dev/null 2>&1; then
    yellow "systemd detected, 创建 service..."
    cat > /etc/systemd/system/xray.service <<SRV
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
LimitNOFILE=30000
ExecStart=$BIN_PATH -config $CONFIG_PATH
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
SRV
    systemctl daemon-reload
    systemctl enable --now xray.service
    systemctl restart xray.service || true
    systemctl status xray.service --no-pager || true
else
    yellow "OpenRC detected..."
    cat > /etc/init.d/xray <<'INIT'
#!/sbin/openrc-run
name="xray"
description="Xray Service"
command="/opt/xray/xray"
command_args="-config /opt/xray/config.json"
pidfile="/run/xray.pid"
command_background="yes"
rc_ulimit="-n 30000"
depend() { need net; after net; }
INIT
    chmod +x /etc/init.d/xray
    command -v rc-update >/dev/null 2>&1 && rc-update add xray default
    service xray restart || true
fi

green "安装完成，Xray Reality + SOCKS5 已就绪"
