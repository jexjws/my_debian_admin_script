#!/bin/bash

# Enable TCP BBR congestion control on Debian.
set -e

SYSCTL_CONFIG="/etc/sysctl.d/99-bbr.conf"
MODULES_CONFIG="/etc/modules-load.d/bbr.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    cat << EOF
用法: sudo ./debian-enable-bbr.sh

开启并持久化 TCP BBR:
  net.core.default_qdisc=fq
  net.ipv4.tcp_congestion_control=bbr

脚本会写入 ${SYSCTL_CONFIG}，并立即加载配置。
如果 BBR 以内核模块形式提供，也会写入 ${MODULES_CONFIG}。
EOF
}

bbr_is_available() {
    sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr
}

load_bbr_module() {
    if command -v modprobe >/dev/null 2>&1; then
        modprobe tcp_bbr 2>/dev/null || true
    fi
}

backup_if_exists() {
    local config_file="$1"
    local label="$2"
    local backup_file

    if [ -f "$config_file" ]; then
        backup_file="${config_file}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$backup_file"
        warning "已备份现有${label}到 ${backup_file}"
    fi
}

write_sysctl_config() {
    backup_if_exists "$SYSCTL_CONFIG" "sysctl 配置"

    cat > "$SYSCTL_CONFIG" << EOF
# Managed by debian-enable-bbr.sh
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    info "已写入 ${SYSCTL_CONFIG}"
}

write_modules_config() {
    backup_if_exists "$MODULES_CONFIG" "模块加载配置"

    cat > "$MODULES_CONFIG" << EOF
# Managed by debian-enable-bbr.sh
tcp_bbr
EOF

    info "已写入 ${MODULES_CONFIG}"
}

if [ "$#" -gt 0 ]; then
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "未知参数: $1"
            echo "使用 --help 查看用法。"
            exit 1
            ;;
    esac
fi

if [ "$EUID" -ne 0 ]; then
    error "请使用 sudo 或 root 权限运行此脚本。"
    exit 1
fi

if ! command -v sysctl >/dev/null 2>&1; then
    error "未找到 sysctl 命令。"
    exit 1
fi

if ! bbr_is_available; then
    load_bbr_module
fi

if ! bbr_is_available; then
    load_bbr_module
fi

if ! bbr_is_available; then
    error "已执行 modprobe tcp_bbr，但当前内核仍未提供 BBR。请检查内核模块和 dmesg 输出。"
    exit 1
fi

if command -v modinfo >/dev/null 2>&1 && modinfo tcp_bbr >/dev/null 2>&1; then
    write_modules_config
fi

write_sysctl_config

sysctl -p "$SYSCTL_CONFIG" >/dev/null

current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"

info "当前 default_qdisc: ${current_qdisc}"
info "当前 tcp_congestion_control: ${current_congestion}"

if [ "$current_qdisc" = "fq" ] && [ "$current_congestion" = "bbr" ]; then
    info "BBR 已开启。"
else
    error "BBR 配置已写入，但当前运行值未生效。请检查 sysctl 输出和内核配置。"
    exit 1
fi
