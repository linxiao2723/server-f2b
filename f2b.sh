#!/usr/bin/env bash
set -euo pipefail

# ====================================================
# Fail2Ban 全自动一键部署脚本（稳妥增强版）
# 特点：
# - 自动修复部分 Debian APT 源问题
# - 自动安装 fail2ban
# - 自动识别 SSH 真实端口
# - 启用递增封禁 + recidive 惯犯封禁
# - 自动日志轮转
# - 自动备份旧配置
# ====================================================

if [ "${EUID}" -ne 0 ]; then
echo "❌ 请以 root 权限运行此脚本"
exit 1
fi

log() { echo -e "[+] $*"; }
warn() { echo -e "[!] $*"; }
err() { echo -e "[-] $*" >&2; }

FAIL2BAN_JAIL="/etc/fail2ban/jail.local"
BACKUP_TIME="$(date +%F-%H%M%S)"
OS_FAMILY=""
SSH_PORTS=""
F2B_BACKEND="auto"
F2B_BANACTION="iptables-multiport"
F2B_BANACTION_ALLPORTS="iptables-allports"

detect_os() {
if [ -f /etc/debian_version ]; then
OS_FAMILY="debian"
elif [ -f /etc/redhat-release ]; then
OS_FAMILY="redhat"
else
err "当前系统不在支持范围内（仅 Debian/Ubuntu/CentOS/RHEL）"
exit 1
fi

log "检测到系统类型：${OS_FAMILY}"
}

fix_apt_sources_if_needed() {
if [ "${OS_FAMILY}" != "debian" ]; then
return
fi

log "步骤 1: 检查并修复 APT 源..."
if [ -f /etc/apt/sources.list ]; then
sed -i '/backports/s/^/#/' /etc/apt/sources.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/backports.list 2>/dev/null || true
fi
}

install_packages() {
log "步骤 2: 安装 Fail2Ban 及必要组件..."

if [ "${OS_FAMILY}" = "debian" ]; then
apt-get update -qq
apt-get install -y fail2ban python3-systemd iptables >/dev/null
else
yum install -y epel-release >/dev/null || true
yum install -y fail2ban iptables >/dev/null
fi
}

detect_ssh_ports() {
SSH_PORTS="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -u | paste -sd, - || true)"

if [ -z "${SSH_PORTS}" ]; then
SSH_PORTS="$(grep -hE '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u | paste -sd, - || true)"
fi

if [ -z "${SSH_PORTS}" ]; then
SSH_PORTS="22"
warn "未能自动识别 SSH 端口，已回退为 22"
fi

log "检测到 SSH 端口：${SSH_PORTS}"
}

detect_backend() {
if command -v journalctl >/dev/null 2>&1; then
F2B_BACKEND="systemd"
else
F2B_BACKEND="auto"
fi

log "Fail2Ban backend：${F2B_BACKEND}"
}

detect_banaction() {
if command -v nft >/dev/null 2>&1 && [ -f /etc/fail2ban/action.d/nftables-multiport.conf ]; then
F2B_BANACTION="nftables-multiport"
F2B_BANACTION_ALLPORTS="nftables-allports"
else
F2B_BANACTION="iptables-multiport"
F2B_BANACTION_ALLPORTS="iptables-allports"
fi

log "banaction：${F2B_BANACTION}"
}

backup_existing_config() {
log "步骤 3: 备份旧配置..."

if [ -f "${FAIL2BAN_JAIL}" ]; then
cp "${FAIL2BAN_JAIL}" "${FAIL2BAN_JAIL}.bak-${BACKUP_TIME}"
log "已备份 ${FAIL2BAN_JAIL} -> ${FAIL2BAN_JAIL}.bak-${BACKUP_TIME}"
fi
}

write_jail_config() {
log "步骤 4: 写入防护规则..."

cat > "${FAIL2BAN_JAIL}" <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1

bantime = 12h
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 4w

findtime = 10m
maxretry = 5

banaction = ${F2B_BANACTION}
banaction_allports = ${F2B_BANACTION_ALLPORTS}

[sshd]
enabled = true
port = ${SSH_PORTS}
backend = ${F2B_BACKEND}
mode = aggressive

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
backend = auto
banaction = ${F2B_BANACTION_ALLPORTS}
findtime = 7d
maxretry = 3
bantime = 4w
bantime.increment = false
protocol = tcp
EOF
}

write_logrotate() {
log "步骤 5: 配置日志轮转..."

cat > /etc/logrotate.d/fail2ban <<'EOF'
/var/log/fail2ban.log {
weekly
rotate 4
compress
delaycompress
missingok
notifempty
postrotate
/usr/bin/fail2ban-client flushlogs >/dev/null 2>&1 || true
endscript
}
EOF
}

restart_fail2ban() {
log "步骤 6: 启用并重启 Fail2Ban..."
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
}

verify_fail2ban() {
log "步骤 7: 验证状态..."
fail2ban-client ping >/dev/null

echo "✅ 部署完成！"
echo "------------------------------------------------"
echo "🛡️ 已启用：递增封禁 + 惯犯重罚 + 日志轮转"
echo "📊 当前 Fail2Ban 状态："
fail2ban-client status
echo
echo "📊 当前 SSH 拦截状态："
fail2ban-client status sshd || true
echo
echo "ℹ️ 常用命令："
echo " fail2ban-client status"
echo " fail2ban-client status sshd"
echo " fail2ban-client set sshd unbanip <IP>"
echo " tail -f /var/log/fail2ban.log"
}

main() {
detect_os
fix_apt_sources_if_needed
install_packages
detect_ssh_ports
detect_backend
detect_banaction
backup_existing_config
write_jail_config
write_logrotate
restart_fail2ban
verify_fail2ban
}

main "$@"
