#!/bin/bash

# 1. 获取 GitHub 发布页面的 URL 作为输入参数
REPO_URL=$1

if [ -z "$REPO_URL" ]; then
  echo "请提供 GitHub 发布页面的 URL"
  exit 1
fi

# 提取 owner 和 repo 名称（格式为 owner/repo）
REPO_PATH=$(echo $REPO_URL | sed -E 's#https://github.com/(.*)/releases#\1#')

if [ -z "$REPO_PATH" ]; then
  echo "无法从 URL 中提取仓库信息"
  exit 1
fi

# 2. 获取最新版本的 tag (例如 v0.63.0)
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO_PATH/releases/latest" | jq -r .tag_name)

if [ -z "$LATEST_TAG" ]; then
  echo "无法获取最新版本号"
  exit 1
fi

# 输出当前平台信息
ARCH=$(uname -m)
OS=$(uname -s)
echo "当前平台架构: $ARCH, 操作系统: $OS"

# 根据平台和架构选择后缀
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH_SUFFIX="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH_SUFFIX="arm64"
else
  echo "不支持此平台架构: $ARCH"
  exit 1
fi

# 根据操作系统选择前缀
if [[ "$OS" == "Linux" ]]; then
  OS_SUFFIX="linux"
elif [[ "$OS" == "Darwin" ]]; then
  OS_SUFFIX="darwin"
elif [[ "$OS" == "FreeBSD" ]]; then
  OS_SUFFIX="freebsd"
elif [[ "$OS" == "NetBSD" ]]; then
  OS_SUFFIX="netbsd"
elif [[ "$OS" == "OpenBSD" ]]; then
  OS_SUFFIX="openbsd"
elif [[ "$OS" == "CYGWIN"* || "$OS" == "MINGW"* ]]; then
  OS_SUFFIX="windows"
else
  echo "不支持此操作系统: $OS"
  exit 1
fi

echo "正在寻找适合平台的下载文件..."

# 3. 获取最新版本的 assets 信息
RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO_PATH/releases/tags/$LATEST_TAG")

# 打印整个 API 返回的数据，用于调试
#echo "API 返回的 JSON 数据："
#echo "$RELEASE_JSON"

# 如果没有返回有效数据，退出并提示
if [[ "$RELEASE_JSON" == "null" || -z "$RELEASE_JSON" ]]; then
  echo "未能从 API 获取有效数据"
  exit 1
fi

# 4. 打印所有发布的文件名，帮助调试
#echo "所有发布的文件名："
#echo "$RELEASE_JSON" | jq -r ".assets[].name"

# 5. 查找匹配操作系统和架构的下载链接
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r ".assets[] | select(.name | test(\"${OS_SUFFIX}-${ARCH_SUFFIX}\")) | .browser_download_url")

# 如果找不到合适的下载文件，给出提示
if [ -z "$DOWNLOAD_URL" ]; then
  echo "没有找到适合平台的下载文件"
  exit 1
fi

# 输出匹配的下载链接
echo "找到匹配的下载链接: $DOWNLOAD_URL"

# 6. 下载文件
FILENAME=$(basename "$DOWNLOAD_URL")
echo "正在下载: $DOWNLOAD_URL"
curl -L -o "$FILENAME" "$DOWNLOAD_URL"

# 7. 解压下载的文件
if [ -f "$FILENAME" ]; then
  echo "下载完成，正在解压..."
  tar -xzvf "$FILENAME"
else
  echo "下载失败"
  exit 1
fi

echo "操作完成！"
