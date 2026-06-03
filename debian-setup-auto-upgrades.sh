#!/bin/bash

# 遇到错误立即退出
set -e

UNATTENDED_UPGRADES_CONFIG="/etc/apt/apt.conf.d/50unattended-upgrades"
MANAGED_CONFIG_MARKER="Managed by debian-setup-auto-upgrades.sh"
RESELECT_ORIGINS=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --select-origins|--reselect-origins)
            RESELECT_ORIGINS=1
            ;;
        -h|--help)
            cat << 'EOF'
用法: sudo ./debian-setup-auto-upgrades.sh [--select-origins]

首次运行时，脚本会扫描当前系统已启用的软件源，并让你多选哪些源允许 unattended-upgrades 自动更新。
之后重复运行会复用本脚本保存的现有选择，只刷新配置。需要重新选择时加 --select-origins。

也可以用环境变量跳过交互:
  UNATTENDED_UPGRADE_ORIGINS='origin=Debian,codename=${distro_codename},label=Debian-Security'
多个源用分号分隔。
EOF
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看用法。"
            exit 1
            ;;
    esac
    shift
done

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 或 root 权限运行此脚本。"
  exit 1
fi

extract_existing_origins() {
    local config_file="$1"
    local managed_marker="${MANAGED_CONFIG_MARKER:-Managed by debian-setup-auto-upgrades.sh}"

    [ -f "$config_file" ] || return 0
    grep -Fq "$managed_marker" "$config_file" || return 0

    awk '
        /Unattended-Upgrade::Origins-Pattern[[:space:]]*\{/ {
            in_block = 1
            next
        }
        in_block && /^[[:space:]]*\};/ {
            in_block = 0
        }
        in_block {
            line = $0
            if (line !~ /^[[:space:]]*"/) {
                next
            }
            sub(/^[[:space:]]*"/, "", line)
            sub(/";?[[:space:]]*$/, "", line)
            if (line ~ /=/) {
                print line
            }
        }
    ' "$config_file"
}

discover_available_origins() {
    apt-cache policy | awk '
        /^[[:space:]]*release / {
            release = $0
            sub(/^[[:space:]]*release[[:space:]]+/, "", release)

            origin = ""
            codename = ""
            label = ""
            archive = ""

            item_count = split(release, items, ",")
            for (i = 1; i <= item_count; i++) {
                split(items[i], kv, "=")
                key = kv[1]
                value = substr(items[i], length(key) + 2)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)

                if (key == "o") {
                    origin = value
                } else if (key == "n") {
                    codename = value
                } else if (key == "l") {
                    label = value
                } else if (key == "a") {
                    archive = value
                }
            }

            if (origin == "" || (codename == "" && archive == "" && label == "")) {
                next
            }

            pattern = "origin=" origin
            description = origin

            if (codename != "") {
                pattern = pattern ",codename=" codename
                description = description " / " codename
            } else if (archive != "") {
                pattern = pattern ",archive=" archive
                description = description " / " archive
            }

            if (label != "") {
                pattern = pattern ",label=" label
                description = label " / " description
            }

            if (codename != "" && archive != "" && archive != codename) {
                description = description " / " archive
            }

            if (!seen[pattern]++) {
                print pattern "\t" description
            }
        }
    '
}

is_positive_integer() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            [ "$1" -gt 0 ]
            ;;
    esac
}

expand_selection_token() {
    local token="$1"
    local max_index="$2"
    local start
    local end
    local i

    if is_positive_integer "$token"; then
        if [ "$token" -le "$max_index" ]; then
            printf '%s\n' "$token"
            return 0
        fi
        return 1
    fi

    case "$token" in
        *-*)
            start="${token%-*}"
            end="${token#*-}"
            if ! is_positive_integer "$start" || ! is_positive_integer "$end"; then
                return 1
            fi
            if [ "$start" -gt "$end" ] || [ "$end" -gt "$max_index" ]; then
                return 1
            fi
            i="$start"
            while [ "$i" -le "$end" ]; do
                printf '%s\n' "$i"
                i=$((i + 1))
            done
            ;;
        *)
            return 1
            ;;
    esac
}

prompt_for_origins() {
    local discovered_file
    local pattern
    local description
    local index
    local answer
    local token
    local selected_indexes
    local selected_index
    local seen_indexes
    local selected_count
    local max_index
    local expanded_indexes

    if [ ! -t 0 ]; then
        echo "未找到既有自动更新源配置，且当前不是交互式终端。" >&2
        echo "请在终端中运行一次，或设置 UNATTENDED_UPGRADE_ORIGINS 环境变量。" >&2
        exit 1
    fi

    discovered_file="$(mktemp)"
    discover_available_origins > "$discovered_file"

    if [ ! -s "$discovered_file" ]; then
        rm -f "$discovered_file"
        echo "未能从 apt-cache policy 扫描到可用的软件源。请先确认 apt-get update 可以正常完成。" >&2
        exit 1
    fi

    max_index="$(awk 'END { print NR }' "$discovered_file")"

    echo "-> 请选择允许 unattended-upgrades 自动更新的软件源。" >&2
    echo "   可输入多个编号，例如: 1,3,5 或 1-3。输入 all 选择全部。" >&2
    echo >&2

    index=1
    while IFS="$(printf '\t')" read -r pattern description; do
        printf '  %2d) %s\n' "$index" "$description" >&2
        printf '      %s\n' "$pattern" >&2
        index=$((index + 1))
    done < "$discovered_file"

    while true; do
        echo >&2
        printf '请输入要自动更新的源编号: ' >&2
        if ! read -r answer; then
            rm -f "$discovered_file"
            echo "未读取到输入，已取消。" >&2
            exit 1
        fi
        answer="$(printf '%s' "$answer" | tr -d '[:space:]')"

        case "$answer" in
            [Aa][Ll][Ll])
                index=1
                while [ "$index" -le "$max_index" ]; do
                    selected_indexes="${selected_indexes}${index}"$'\n'
                    index=$((index + 1))
                done
                break
                ;;
        esac

        if [ -z "$answer" ]; then
            echo "至少需要选择一个源。" >&2
            continue
        fi

        selected_indexes=""
        seen_indexes=""
        while IFS= read -r token; do
            if ! expanded_indexes="$(expand_selection_token "$token" "$max_index")"; then
                selected_indexes=""
                break
            fi

            while IFS= read -r selected_index; do
                case "
$seen_indexes
" in
                    *"
$selected_index
"*)
                        ;;
                    *)
                        seen_indexes="${seen_indexes}${selected_index}"$'\n'
                        selected_indexes="${selected_indexes}${selected_index}"$'\n'
                        ;;
                esac
            done << EOF
$expanded_indexes
EOF
        done << EOF
$(printf '%s' "$answer" | tr ',' '\n')
EOF

        if [ -n "$selected_indexes" ]; then
            break
        fi

        echo "输入无效，请使用列表中的编号、逗号或范围。" >&2
    done

    selected_count=0
    while IFS= read -r selected_index; do
        [ -n "$selected_index" ] || continue
        sed -n "${selected_index}p" "$discovered_file" | cut -f1
        selected_count=$((selected_count + 1))
    done << EOF
$selected_indexes
EOF

    rm -f "$discovered_file"

    if [ "$selected_count" -eq 0 ]; then
        echo "至少需要选择一个源。" >&2
        exit 1
    fi
}

resolve_unattended_upgrade_origins() {
    local existing_origins

    if [ -n "${UNATTENDED_UPGRADE_ORIGINS:-}" ]; then
        printf '%s' "$UNATTENDED_UPGRADE_ORIGINS" | tr ';' '\n' | sed '/^[[:space:]]*$/d'
        return 0
    fi

    if [ "$RESELECT_ORIGINS" -eq 0 ]; then
        existing_origins="$(extract_existing_origins "$UNATTENDED_UPGRADES_CONFIG")"
        if [ -n "$existing_origins" ]; then
            printf '%s\n' "$existing_origins"
            return 0
        fi
    fi

    prompt_for_origins
}

write_unattended_upgrades_config() {
    local origins_file="$1"

    {
        cat << 'EOF'
// Managed by debian-setup-auto-upgrades.sh
// Re-run with --select-origins to replace the Origins-Pattern selection.

Unattended-Upgrade::Origins-Pattern {
EOF
        while IFS= read -r origin_pattern; do
            [ -n "$origin_pattern" ] || continue
            printf '        "%s";\n' "$origin_pattern"
        done < "$origins_file"
        cat << 'EOF'
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
    } > "$UNATTENDED_UPGRADES_CONFIG"
}

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
echo "-> 配置 ${UNATTENDED_UPGRADES_CONFIG}..."
selected_origins_file="$(mktemp)"
resolve_unattended_upgrade_origins > "$selected_origins_file"

if [ ! -s "$selected_origins_file" ]; then
    rm -f "$selected_origins_file"
    echo "未找到可写入的自动更新源配置。"
    exit 1
fi

echo "   自动更新源:"
while IFS= read -r origin_pattern; do
    [ -n "$origin_pattern" ] || continue
    echo "   - ${origin_pattern}"
done < "$selected_origins_file"

write_unattended_upgrades_config "$selected_origins_file"
rm -f "$selected_origins_file"

# 6. 重启服务以应用更改
echo "-> 重启 unattended-upgrades 服务..."
systemctl restart unattended-upgrades

echo "=== 配置完成！ ==="
echo "系统现在将在后台自动安装已选择源的更新，并在需要时通过 kexec 于凌晨 4:00 秒级重启。"
echo "核心数据库 (PostgreSQL, Percona) 已被保护，不会被自动更新。"
echo "如需重新选择自动更新源，请重新运行: sudo $0 --select-origins"
