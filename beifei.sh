#!/bin/bash

# 定义备份目录
BACKUP_DIR="/path/to/backup"

# 依赖软件列表
REQUIRED_APPS=("rsync" "tar")

# 检查并安装依赖软件
check_dependencies() {
    for app in "${REQUIRED_APPS[@]}"; do
        if ! command -v $app &> /dev/null; then
            echo "$app 未安装，正在安装..."
            if [ -x "$(command -v apt-get)" ]; then
                sudo apt-get update
                sudo apt-get install -y $app
            elif [ -x "$(command -v yum)" ]; then
                sudo yum install -y $app
            else
                echo "无法自动安装 $app，请手动安装。"
                exit 1
            fi
        fi
    done
}

# 检查并创建备份目录
check_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "备份目录 $BACKUP_DIR 不存在，正在创建..."
        mkdir -p $BACKUP_DIR
        if [ $? -ne 0 ]; then
            echo "无法创建备份目录 $BACKUP_DIR，请检查权限。"
            exit 1
        fi
    fi
}

# 备份系统
backup_system() {
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

    # 使用 tar 备份系统
    sudo tar -czvf $BACKUP_PATH --exclude="$BACKUP_DIR" --one-file-system /
    
    echo "备份完成: $BACKUP_PATH"
}

# 恢复系统
restore_system() {
    echo "可用的备份文件:"
    ls $BACKUP_DIR

    read -p "请输入要恢复的备份文件名: " BACKUP_FILE

    if [ -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
        echo "恢复系统可能会覆盖当前系统配置，是否继续? (y/n)"
        read CONFIRM
        if [ "$CONFIRM" == "y" ]; then
            # 使用 tar 解压备份文件
            sudo tar -xzvf "$BACKUP_DIR/$BACKUP_FILE" -C /
            echo "系统恢复完成。"
        else
            echo "恢复操作已取消。"
        fi
    else
        echo "备份文件不存在。"
    fi
}

# 显示菜单
show_menu() {
    echo "菜单:"
    echo "1. 备份系统"
    echo "2. 系统恢复"
    echo "3. 退出"
    read -p "请选择操作: " CHOICE

    case $CHOICE in
        1)
            backup_system
            ;;
        2)
            restore_system
            ;;
        3)
            exit 0
            ;;
        *)
            echo "无效选择，请重新选择。"
            show_menu
            ;;
    esac
}

# 主程序
main() {
    check_dependencies
    check_backup_dir
    while true; do
        show_menu
    done
}

main
