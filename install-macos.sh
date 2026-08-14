#!/bin/bash
# =====================================================================
#  DeepSeek Harness Desktop Launcher —— macOS 一键安装脚本
#
#  一行安装：
#    curl -fsSL https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install-macos.sh | bash
#
#  会下载启动器文件到 ~/Library/Application Support/DeepSeek-Harness-Launcher，
#  组装 "DeepSeek Harness.app" 并放进 /Applications（无权限则放 ~/Applications）。
# =====================================================================
set -uo pipefail

OWNER=becomeless
REPO=dsh-desktop-launcher
BRANCH=main
BASE="https://cdn.jsdelivr.net/gh/$OWNER/$REPO@$BRANCH"
FALLBACK="https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH"
INSTALL_DIR="$HOME/Library/Application Support/DeepSeek-Harness-Launcher"

fetch() {  # fetch <仓库内路径> <目标文件>
  local src="$1" dst="$2"
  if ! curl -fsSL --connect-timeout 20 "$BASE/$src" -o "$dst" 2>/dev/null; then
    if ! curl -fsSL --connect-timeout 20 "$FALLBACK/$src" -o "$dst" 2>/dev/null; then
      echo "下载失败：$src（已尝试 jsDelivr 与 GitHub 两个源）"
      exit 1
    fi
  fi
}

# ---- 0) Node.js 检查 ----
if ! command -v npx >/dev/null 2>&1; then
  echo "未检测到 Node.js（npx）。"
  if command -v brew >/dev/null 2>&1; then
    read -rp "用 Homebrew 自动安装 Node.js LTS？(y/N) " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
      brew install node
    else
      echo "请先安装 Node.js（https://nodejs.org），然后重新运行本命令。"
      exit 1
    fi
  else
    echo "请先安装 Homebrew（https://brew.sh）或 Node.js（https://nodejs.org），然后重新运行本命令。"
    exit 1
  fi
  if ! command -v npx >/dev/null 2>&1; then
    echo "Node.js 未就绪，请新开终端后重试。"
    exit 1
  fi
fi

# ---- 1) 下载文件 ----
echo "下载安装文件..."
mkdir -p "$INSTALL_DIR/mac"
fetch "mac/DSH-Launcher.sh" "$INSTALL_DIR/mac/DSH-Launcher.sh"
fetch "mac/build-mac-app.sh" "$INSTALL_DIR/mac/build-mac-app.sh"
fetch "mac/Info.plist" "$INSTALL_DIR/mac/Info.plist"
fetch "mac/AppIcon.icns" "$INSTALL_DIR/mac/AppIcon.icns"
chmod +x "$INSTALL_DIR/mac/DSH-Launcher.sh" "$INSTALL_DIR/mac/build-mac-app.sh"

# ---- 2) 组装 .app ----
bash "$INSTALL_DIR/mac/build-mac-app.sh" "$INSTALL_DIR/DeepSeek Harness.app"

# ---- 3) 装到 Applications ----
if [[ -w /Applications ]]; then
  DEST=/Applications
else
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi
rm -rf "$DEST/DeepSeek Harness.app"
cp -R "$INSTALL_DIR/DeepSeek Harness.app" "$DEST/"

echo ""
echo "安装完成：$DEST/DeepSeek Harness.app"
echo "双击即可使用；想放进 Dock，从 Finder 把它拖进 Dock 即可。"
echo "（首次启动需要联网下载 DeepSeek Harness；与模型对话需配置 DEEPSEEK_API_KEY）"
