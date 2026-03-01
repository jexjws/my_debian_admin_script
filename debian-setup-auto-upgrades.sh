#!/bin/bash

# 遇到错误立即退出
set -e

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 或 root 权限运行此脚本。"
  exit 1
fi

echo "=== 开始配置 Debian 自动化更新与热重启环境 ==="

# 1. 设置非交互模式，避免安装过程中出现粉色或蓝色弹窗卡住脚本
export DEBIAN_FRONTEND=noninteractive

echo "-> 更新软件包列表并安装必要组件 (unattended-upgrades, needrestart, kexec-tools)..."
apt-get update
# 预先配置 debconf 自动同意 kexec-tools 接管重启
echo "kexec-tools kexec-tools/load_kexec boolean true" | debconf-set-selections
apt-get install -y unattended-upgrades needrestart kexec-tools

# 2. 配置 needrestart (完全自动化，不弹窗)
echo "-> 配置 needrestart (静默模式与自动重启服务)..."
mkdir -p /etc/needrestart/conf.d
cat << 'EOF' > /etc/needrestart/conf.d/99-auto-restart.conf
# 自动重启需要重启的服务 (a = auto)
$nrconf{restart} = 'a';
# 禁用内核更新后的弹窗提示
$nrconf{kernelhints} = -1;
EOF

# 3. 配置 kexec-tools
echo "-> 配置 kexec-tools..."
# 确保 LOAD_KEXEC=true
if grep -q "^LOAD_KEXEC=" /etc/default/kexec; then
    sed -i 's/^LOAD_KEXEC=.*/LOAD_KEXEC=true/' /etc/default/kexec
else
    echo "LOAD_KEXEC=true" >> /etc/default/kexec
fi

# 4. 配置 APT 周期任务 (触发器)
echo "-> 配置 /etc/apt/apt.conf.d/20auto-upgrades..."
cat << 'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 5. 配置 Unattended-Upgrades (执行策略)
# 注意：使用 'EOF' (带单引号) 可以防止 bash 解析 ${distro_codename} 变量
echo "-> 配置 /etc/apt/apt.conf.d/50unattended-upgrades..."
cat << 'EOF' > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
};

Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Automatic-Reboot-With-Kexec "true";

Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

Unattended-Upgrade::Package-Blacklist {
    "percona-server-.*";
    "postgresql-.*";
};
EOF

# 6. 重启服务以应用更改
echo "-> 重启 unattended-upgrades 服务..."
systemctl restart unattended-upgrades

echo "=== 配置完成！ ==="
echo "系统现在将在后台自动安装安全更新，并在需要时通过 kexec 于凌晨 4:00 秒级重启。"
echo "核心数据库 (PostgreSQL, Percona) 已被保护，不会被自动更新。"