#!/bin/bash
#每行一个任务,如果第一个字符为'#'则跳过该任务

# 全局变量
Q_path=$(dirname "$0")/
Q_path_ini="${Q_path}进程守护.txt"


主函数() {
    数据处理
    for line in "${lines[@]}"; do
        # 跳过以 # 开头的行或空行
        [[ "$line" =~ ^#.* || -z "$line" ]] && continue

        # 执行 ps -aux | grep +本行内容
        count=$(ps -aux | grep -w "$line" | wc -l)

        # 如果返回数据的行数超过1，跳过
        if [ "$count" -gt 1 ]; then
            continue
        else
            # 执行本行内容并在后台运行
            echo "$line"
            eval "$line &"
        fi
    done
}

数据处理() {
    # 检查文件是否存在，不存在则创建
    if [[ ! -f "$Q_path_ini" ]]; then
        touch "$Q_path_ini"
    fi
    # 读取文件并处理分隔符
    if [[ -f "$Q_path_ini" ]]; then
        # 检查文件是否为空
        if [[ -s "$Q_path_ini" ]]; then
            # 读取文件内容到变量
            content=$(<"$Q_path_ini")
            # 如果没有换行符，则将内容设为数组[1]并返回
            if [[ "$content" != *$'\n'* ]]; then
                lines[0]="$content"  # 使用数组索引0
            else
                IFS=$'\n' read -d '' -r -a lines < "$Q_path_ini"
            fi
        fi
        
        # 处理每一行，删除可能的 \r
        for i in "${!lines[@]}"; do
            lines[$i]=$(echo -e "${lines[$i]}" | tr -d '\r')
        done
    fi
}

主函数
