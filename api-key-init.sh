#!/bin/bash

# -------------------------- 颜色输出函数 --------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -------------------------- 主逻辑 --------------------------

BASHRC="$HOME/.bashrc"

info "开始配置环境变量..."

# 1. 询问并获取 DEEPSEEK_API_KEY
echo ""
warning "请输入你的 DEEPSEEK_API_KEY"
info "获取地址：https://platform.deepseek.com/usage"
read -r -p "Key: " DEEPSEEK_KEY

# 2. 询问并获取 BRAVE_API_KEY
echo ""
warning "请输入你的 BRAVE_API_KEY"
info "获取地址：https://brave.com/search/api/"
read -r -p "Key: " BRAVE_KEY

# 3. 备份当前的 .bashrc (可选，为了安全)
# if [ -f "$BASHRC" ]; then
#     cp "$BASHRC" "${BASHRC}.backup_$(date +%Y%m%d_%H%M%S)"
#     info "已备份 .bashrc 至 ${BASHRC}.backup_*"
# fi

# 4. 写入环境变量 (使用 sed 删除旧值，避免重复添加，然后追加新值)
# 移除旧的 DEEPSEEK_API_KEY
sed -i '/export DEEPSEEK_API_KEY=/d' "$BASHRC"
# 移除旧的 BRAVE_API_KEY
sed -i '/export BRAVE_API_KEY=/d' "$BASHRC"

# 追加新的 Key
echo "" >> "$BASHRC"
echo "# Added by setup_script on $(date)" >> "$BASHRC"
echo "export DEEPSEEK_API_KEY=\"${DEEPSEEK_KEY}\"" >> "$BASHRC"
echo "export BRAVE_API_KEY=\"${BRAVE_KEY}\"" >> "$BASHRC"

echo ""
info "配置已写入 ${BASHRC}"
info "请运行以下命令使配置立即生效："
echo "   source ~/.bashrc"