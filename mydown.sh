#!/bin/bash

# 1. 获取 GitHub 发布页面的 URL 作为输入参数
REPO_URL=$1

if [ -z "$REPO_URL" ]; then
  echo "请提供 GitHub 发布页面的 URL"
  exit 1
fi

# 提取 owner/repo 名称
REPO_PATH=$(echo "$REPO_URL" | sed -E 's#https://github.com/([^/]+/[^/]+)/releases/?#\1#')
#echo $REPO_PATH
if [ -z "$REPO_PATH" ]; then
  echo "无法从 URL 中提取仓库信息"
  exit 1
fi

# 2. 获取最新版本的 tag
URL="https://api.github.com/repos/$REPO_PATH/releases/latest"
echo $URL
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO_PATH/releases/latest" | jq -r .tag_name)

if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
  echo "无法获取最新版本号"
  exit 1
fi

echo "获取到最新版本: $LATEST_TAG"

# 3. 获取最新版本的 assets 信息
RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO_PATH/releases/tags/$LATEST_TAG")

if [[ "$RELEASE_JSON" == "null" || -z "$RELEASE_JSON" ]]; then
  echo "未能从 API 获取有效数据"
  exit 1
fi

# 4. 打印所有文件（带序号）
echo "可下载文件列表："
ASSET_NAMES=($(echo "$RELEASE_JSON" | jq -r '.assets[].name'))
ASSET_URLS=($(echo "$RELEASE_JSON" | jq -r '.assets[].browser_download_url'))

for i in "${!ASSET_NAMES[@]}"; do
  echo "$i) ${ASSET_NAMES[$i]}"
done

# 5. 用户输入序号
read -p "请输入要下载的文件序号: " INDEX

# 判断输入是否合法
if ! [[ "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -ge "${#ASSET_NAMES[@]}" ]; then
  echo "输入的序号无效"
  exit 1
fi

FILENAME=${ASSET_NAMES[$INDEX]}
DOWNLOAD_URL=${ASSET_URLS[$INDEX]}

echo "准备下载: $FILENAME"
curl -L -o "/root/$FILENAME" "$DOWNLOAD_URL"

# 6. 自动解压（支持 .tar.gz .tgz .zip）
cd /root
if [[ "$FILENAME" == *.tar.gz ]] || [[ "$FILENAME" == *.tgz ]]; then
  echo "检测到 tar.gz 格式，正在解压..."
  tar -xzvf "$FILENAME"
elif [[ "$FILENAME" == *.zip ]]; then
  echo "检测到 zip 格式，正在解压..."
  unzip "$FILENAME"
else
  echo "下载完成，非压缩文件无需解压"
fi

echo "操作完成！文件保存在 /root/"
