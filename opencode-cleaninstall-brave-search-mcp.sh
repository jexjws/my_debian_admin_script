#!/bin/bash

npm i -g opencode-ai

# 创建目标目录（如果不存在）
mkdir -p ~/.config/opencode

# 创建JSON配置文件
cat > ~/.config/opencode/opencode.json << 'EOF'
{
  "mcp": {
    "web-search": {
      "type": "local",
      "command": ["npx", "-y", "@brave/brave-search-mcp-server"],
      "enabled": true,
      "environment": {
        "BRAVE_API_KEY": "{env:BRAVE_API_KEY}"
      }
    }
  }
}
EOF

# 设置合适的权限
chmod 600 ~/.config/opencode/opencode.json

# 验证文件是否创建成功
if [ -f ~/.config/opencode/opencode.json ]; then
    echo "✅ 配置文件已成功写入：~/.config/opencode/opencode.json"
    echo "内容如下："
    cat ~/.config/opencode/opencode.json
else
    echo "❌ 配置文件创建失败"
    exit 1
fi
