#!/bin/bash

# 设置字符编码为 UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 定义全局变量
script_dir="$(dirname "$(realpath "$0")")"
path="$script_dir/port_守护.txt"

# 检查文件是否存在
if [[ ! -f "$path" ]]; then
    echo "File $path not found!"
    exit 1
fi

# 读取文件内容并处理每一行
while IFS=$'\r\n' read -r line || [[ -n "$line" ]]; do
    # 移除可能的 \r 字符
    line=$(echo "$line" | tr -d '\r')
    
    # 忽略以 # 开头的行
    if [[ "$line" =~ ^#.* ]]; then
        continue
    fi

    # 分割行内容，获取端口和脚本路径
    port=$(echo "$line" | cut -d '|' -f 1)
    script=$(echo "$line" | cut -d '|' -f 2)

    # 检查端口是否被占用
    if ! netstat -tuln | grep ":$port\b" >/dev/null 2>&1; then
        echo "Port $port is not in use, starting $script"
        nohup python3 "$script" > /dev/null 2>&1 &
    else
        echo "Port $port is already in use"
    fi
done < "$path"
