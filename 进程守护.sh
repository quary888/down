#!/bin/bash
# 每行一个任务, 如果第一字符为 '#' 则跳过该任务

Q_path=$(dirname "$0")/
Q_path_ini="${Q_path}进程守护.txt"

# 多空格压缩成一个空格
normalize_cmd() {
    local cmd="$1"
    echo "$cmd" | sed 's/^[ \t]*//;s/[ \t]*$//;s/[ \t][ \t]*/ /g'
}

主函数() {
    数据处理

    # 一次性获取所有进程完整命令行
    # 注意：ps aux 输出中命令行从第11列开始，但更简单方式是：
    PROCESS_LIST=$(ps -eo args --no-header)

    # 对 ps 输出也做规范化以提高对比准确性
    NORMALIZED_PS=$(echo "$PROCESS_LIST" | sed 's/[ \t][ \t]*/ /g')

    for raw in "${lines[@]}"; do
        [[ "$raw" =~ ^#.* || -z "$raw" ]] && continue

        # 规范化配置文件中的任务行
        norm_task=$(normalize_cmd "$raw")

        # 判断任务是否已存在（字符串匹配）
        # 使用 grep -Fx 完整匹配一整行
        echo "$NORMALIZED_PS" | grep -Fx "$norm_task" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            continue    # 已在运行
        fi

        echo "启动任务: $raw"
        nohup bash -c "$raw" >/dev/null 2>&1 &
    done
}

数据处理() {
    [[ ! -f "$Q_path_ini" ]] && touch "$Q_path_ini"

    # 读文件
    mapfile -t lines < "$Q_path_ini"

    # 去掉 Windows 回车
    for i in "${!lines[@]}"; do
        lines[$i]=$(echo "${lines[$i]}" | tr -d '\r')
    done
}

主函数
exit 0
