#!/bin/sh

REPO="quary888/down"
API_URL="https://api.github.com/repos/$REPO/contents"

echo "正在获取仓库文件列表: $REPO"
echo "----------------------------------------"

# 获取文件信息(JSON)，只取文件类型 entries
FILE_LIST=$(curl -s $API_URL)

# 提取文件名和下载 URL
names=$(echo "$FILE_LIST" | grep '"name":' | cut -d '"' -f4)
urls=$(echo "$FILE_LIST" | grep '"download_url":' | cut -d '"' -f4)

i=1

# 转数组
names_arr=$(echo "$names")
urls_arr=$(echo "$urls")

# 显示列表
echo "文件列表："
for name in $names_arr; do
    echo "$i) $name"
    i=$((i+1))
done

echo "----------------------------------------"
printf "请输入要下载的序号: "
read num

# 获取对应的下载链接
url=$(echo "$urls_arr" | sed -n "${num}p")
filename=$(echo "$names_arr" | sed -n "${num}p")

if [ -z "$url" ]; then
    echo "序号无效"
    exit 1
fi

echo "正在下载: $filename"
curl -L -o "$filename" "$url"

echo "下载完成: $filename"