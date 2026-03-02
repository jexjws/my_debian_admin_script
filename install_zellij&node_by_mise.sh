#!/bin/bash

# ==========================================
# 仅支持 Bash，配置写入 ~/.bashrc
# ==========================================

set -e # 遇到错误立即退出

# 定义颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[SETUP] $1${NC}"
}

success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

# 1. 安装系统基础依赖
log "更新系统并安装 curl, git..."
if command -v sudo &> /dev/null; then
    sudo apt update && sudo apt install -y curl git unzip build-essential
else
    apt update && apt install -y curl git unzip build-essential
fi

# 2. 安装 mise (如果已存在则跳过)
if ! command -v mise &> /dev/null; then
    log "正在下载并安装 mise..."
    curl https://mise.run | sh
    
    # 临时添加到 PATH 以便当前脚本使用
    export PATH="$HOME/.local/bin:$PATH"
else
    log "mise 已安装，跳过下载。"
fi

# 3. 配置 ~/.bashrc
log "配置 ~/.bashrc..."

# 确保 ~/.local/bin 在 PATH 中
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

# 确保 mise activate bash 在 .bashrc 中
if ! grep -q 'mise activate bash' ~/.bashrc; then
    echo 'eval "$(mise activate bash)"' >> ~/.bashrc
    success "已将 mise配置写入 ~/.bashrc"
else
    log "mise 配置已存在于 ~/.bashrc，跳过。"
fi

# 在当前 Shell 激活 mise 以安装后续软件
eval "$(mise activate bash)"

# 4. 通过 mise 安装软件
log "开始通过 mise 安装工具..."

# 安装 Zellij
log "安装 Zellij (最新版)..."
mise use --global zellij@latest

# 安装 Node.js
log "安装 Node.js (LTS 版本)..."
mise use --global node@lts


# 5. 完成
echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}  安装全部完成！  ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "请执行以下命令使环境立即生效："
echo -e "${BLUE}source ~/.bashrc${BLUE}"
echo ""
echo -e "已安装版本："
mise list --global
