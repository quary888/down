#!/usr/bin/env bash
# 适配Debian/Alpine，下载后不退出，输入0退出，支持连续下载/目录切换

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

    # 拉取仓库目录/文件信息（静默模式，屏蔽curl输出）
    RESPONSE=$(curl -s "$api_url")
    # 判空：处理网络错误/仓库不存在/路径错误
    if [ -z "$RESPONSE" ]; then
        echo "错误：获取目录信息失败（网络问题/路径无效）"
        return 1
    fi

    # 提取 name / type / download_url / path（兼容sh语法）
    names=$(echo "$RESPONSE" | grep '"name":' | cut -d '"' -f4)
    types=$(echo "$RESPONSE" | grep '"type":' | cut -d '"' -f4)
    urls=$(echo "$RESPONSE" | grep '"download_url":' | cut -d '"' -f4)
    paths=$(echo "$RESPONSE" | grep '"path":' | cut -d '"' -f4)

    i=1
    echo "文件列表："

    # 显示列表（目录[DIR] / 文件[FILE] 标注）
    paste -d '|' \
        <(echo "$names") \
        <(echo "$types") | while IFS="|" read -r name type; do
            if [ "$type" = "dir" ]; then
                echo "$i) [DIR]  $name"
            else
                echo "$i) [FILE] $name"
            fi
            i=$((i+1))
        done

    echo "----------------------------------------"
    printf "请输入序号（0=退出，其他序号选择文件/目录）: "
    read -r num

    # 核心：输入0直接退出脚本
    if [ "$num" = "0" ]; then
        echo "退出程序，感谢使用！"
        exit 0
    fi

    # 校验序号是否为有效数字（简单判空+非数字处理）
    if [ -z "$num" ] || ! echo "$num" | grep -q '^[0-9]\+$'; then
        echo "错误：请输入有效数字序号！"
        return 1
    fi

    # 获取选中项的信息
    selected_type=$(echo "$types" | sed -n "${num}p")
    selected_path=$(echo "$paths" | sed -n "${num}p")
    selected_url=$(echo "$urls" | sed -n "${num}p")
    selected_name=$(echo "$names" | sed -n "${num}p")

    # 校验序号是否在有效范围内
    if [ -z "$selected_type" ]; then
        echo "错误：序号无效，超出列表范围！"
        return 1
    fi

    # 选中目录 → 切换路径，重新加载列表（替代递归，避免栈溢出）
    if [ "$selected_type" = "dir" ]; then
        CURRENT_PATH="$selected_path"
        echo "进入目录: $selected_name"
    fi

    # 选中文件 → 下载（-L 跟随重定向，确保GitHub文件能正常下载）
    if [ "$selected_type" = "file" ]; then
        echo "正在下载文件: $selected_name ..."
        if curl -L -o "$selected_name" "$selected_url"; then
            echo "✅ 下载完成: $selected_name（保存在当前目录）"
        else
            echo "❌ 下载失败: $selected_name（网络问题/文件不存在）"
        fi
    fi
}

# 主循环：持续执行，直到输入0退出
echo "========== GitHub 仓库文件下载工具 =========="
echo "仓库地址: $REPO"
echo "使用说明: 输入序号选择文件/目录，输入0退出程序"
echo "============================================"
while true; do
    list_and_select
done