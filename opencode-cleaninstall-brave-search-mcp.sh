#!/bin/bash

npm i -g opencode-ai

# 创建目标目录（如果不存在）
mkdir -p ~/.config/opencode

read -p "是否启用 Brave Search MCP？如果你在大陆网络环境的话，可能会有网络问题，建议关闭 (y/n): " -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    BRAVE_ENABLED="true"
else
    BRAVE_ENABLED="false"
fi

# 创建JSON配置文件
cat > ~/.config/opencode/opencode.json << EOF
{
  "mcp": {
    "web-search": {
      "type": "local",
      "command": ["npx", "-y", "@brave/brave-search-mcp-server"],
      "enabled": ${BRAVE_ENABLED},
      "environment": {
        "BRAVE_API_KEY": "{env:BRAVE_API_KEY}"
      }
    }
  },
  "tui": {
    "animations": false
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
