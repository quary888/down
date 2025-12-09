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

    # 取得 ps 输出（带参数）
    PS_RAW=$(ps -eo pid,ppid,user,args)

    # 校验是否成功获取到 PID 字段（BusyBox/Alpine 也会输出 PID）
    echo "$PS_RAW" | grep -q "PID"
    if [[ $? -ne 0 ]]; then
        echo "获取信息失败"
        exit 1
    fi

    # 去掉标题行
    PS_RAW=$(echo "$PS_RAW" | sed '1d')

    # 只保留 args（最后部分）
    PS_ARGS=$(echo "$PS_RAW" | awk '{ $1=""; $2=""; $3=""; sub(/^  */, ""); print }')

    # 将多空格标准化
    PS_NORMALIZED=$(echo "$PS_ARGS" | sed 's/[ \t][ \t]*/ /g')
	#echo $PS_NORMALIZED

    for raw in "${lines[@]}"; do
        [[ "$raw" =~ ^#.* || -z "$raw" ]] && continue

        # 标准化配置项
        task_norm=$(normalize_cmd "$raw")

        # 查找任务是否已存在
        echo "$PS_NORMALIZED" | grep -Fx "$task_norm" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            continue
        fi

        echo "启动任务: $raw"
        nohup bash -c "$raw" >/dev/null 2>&1 &
    done
}

数据处理() {
    [[ ! -f "$Q_path_ini" ]] && touch "$Q_path_ini"

    mapfile -t lines < "$Q_path_ini"

    # 去除 Windows 回车符
    for i in "${!lines[@]}"; do
        lines[$i]=$(echo "${lines[$i]}" | tr -d '\r')
    done
}

主函数
exit 0
