# my_debian_admin_script

我自用的一些 debian 系统运维脚本

# 注

- 脚本由AI生成，仅为我自用而写
- 脚本仅支持在 debian发行版 上运行

# 脚本

- `debian-enable-bbr.sh`: 开启并持久化 TCP BBR；如果当前未加载 `tcp_bbr`，会执行 `modprobe tcp_bbr`。用法: `sudo ./debian-enable-bbr.sh`
