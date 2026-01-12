#!/bin/sh

REPO="quary888/down"
API_BASE="https://api.github.com/repos/$REPO/contents"

# 当前浏览路径（根目录为空）
CURRENT_PATH=""

list_and_select() {
    local api_url
    if [ -z "$CURRENT_PATH" ]; then
        api_url="$API_BASE"
    else
        api_url="$API_BASE/$CURRENT_PATH"
    fi

    echo
    echo "当前路径: /$CURRENT_PATH"
    echo "----------------------------------------"

    RESPONSE=$(curl -s "$api_url")

    # 提取 name / type / download_url / path
    names=$(echo "$RESPONSE" | grep '"name":' | cut -d '"' -f4)
    types=$(echo "$RESPONSE" | grep '"type":' | cut -d '"' -f4)
    urls=$(echo "$RESPONSE" | grep '"download_url":' | cut -d '"' -f4)
    paths=$(echo "$RESPONSE" | grep '"path":' | cut -d '"' -f4)

    i=1
    echo "文件列表："

    # 显示列表（目录加标注）
    paste -d '|' \
        <(echo "$names") \
        <(echo "$types") | while IFS="|" read name type; do
            if [ "$type" = "dir" ]; then
                echo "$i) [DIR]  $name"
            else
                echo "$i) [FILE] $name"
            fi
            i=$((i+1))
        done

    echo "----------------------------------------"
    printf "请输入序号 (Ctrl+C 退出): "
    read num

    selected_type=$(echo "$types" | sed -n "${num}p")
    selected_path=$(echo "$paths" | sed -n "${num}p")
    selected_url=$(echo "$urls" | sed -n "${num}p")
    selected_name=$(echo "$names" | sed -n "${num}p")

    if [ -z "$selected_type" ]; then
        echo "序号无效"
        exit 1
    fi

    # 如果是目录 → 进入目录，递归
    if [ "$selected_type" = "dir" ]; then
        CURRENT_PATH="$selected_path"
        list_and_select
    fi

    # 如果是文件 → 下载
    if [ "$selected_type" = "file" ]; then
        echo "正在下载文件: $selected_name"
        curl -L -o "$selected_name" "$selected_url"
        echo "下载完成: $selected_name"
        exit 0
    fi
}

echo "正在浏览 GitHub 仓库: $REPO"
list_and_select
