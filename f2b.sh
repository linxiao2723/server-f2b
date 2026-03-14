#!/usr/bin/env bash
set -euo pipefail

FAIL2BAN_JAIL="/etc/fail2ban/jail.local"
LOGROTATE_FILE="/etc/logrotate.d/fail2ban"
BACKUP_TIME="$(date +%F-%H%M%S)"
OS_FAMILY=""
SSH_PORTS=""
F2B_BACKEND="auto"
F2B_BANACTION="iptables-multiport"
F2B_BANACTION_ALLPORTS="iptables-allports"
SSH_UNIT="sshd.service"
SSH_JOURNALMATCH="_SYSTEMD_UNIT=sshd.service + _COMM=sshd"

green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
red() { echo -e "\033[31m$*\033[0m"; }
cyan() { echo -e "\033[36m$*\033[0m"; }

need_root() {
if [ "${EUID}" -ne 0 ]; then
red "❌ 请以 root 权限运行"
exit 1
fi
}

detect_os() {
if [ -f /etc/debian_version ]; then
OS_FAMILY="debian"
elif [ -f /etc/redhat-release ]; then
OS_FAMILY="redhat"
else
red "❌ 当前系统不在支持范围内（仅 Debian/Ubuntu/CentOS/RHEL）"
exit 1
fi
}

fix_apt_sources_if_needed() {
if [ "${OS_FAMILY}" != "debian" ]; then
return
fi

yellow "🛠️ 检查并修复 APT 源..."
if [ -f /etc/apt/sources.list ]; then
sed -i '/backports/s/^/#/' /etc/apt/sources.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/backports.list 2>/dev/null || true
fi
}

install_packages() {
yellow "📦 安装 Fail2Ban 及必要组件..."

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
yellow "⚠️ 未能自动识别 SSH 端口，已回退为 22"
fi
}

detect_backend() {
if command -v journalctl >/dev/null 2>&1; then
F2B_BACKEND="systemd"
else
F2B_BACKEND="auto"
fi
}

detect_banaction() {
if command -v nft >/dev/null 2>&1 && [ -f /etc/fail2ban/action.d/nftables-multiport.conf ]; then
F2B_BANACTION="nftables-multiport"
F2B_BANACTION_ALLPORTS="nftables-allports"
else
F2B_BANACTION="iptables-multiport"
F2B_BANACTION_ALLPORTS="iptables-allports"
fi
}

detect_ssh_unit() {
if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
SSH_UNIT="ssh.service"
elif systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
SSH_UNIT="sshd.service"
else
SSH_UNIT="sshd.service"
fi

SSH_JOURNALMATCH="_SYSTEMD_UNIT=${SSH_UNIT} + _COMM=sshd"
}

backup_existing_config() {
if [ -f "${FAIL2BAN_JAIL}" ]; then
cp "${FAIL2BAN_JAIL}" "${FAIL2BAN_JAIL}.bak-${BACKUP_TIME}"
green "✅ 已备份旧配置：${FAIL2BAN_JAIL}.bak-${BACKUP_TIME}"
fi
}

write_jail_config() {
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
journalmatch = ${SSH_JOURNALMATCH}
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
cat > "${LOGROTATE_FILE}" <<'EOF'
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

verify_fail2ban() {
yellow "🔍 正在验证 Fail2Ban 状态..."

local retries=10
local i=1

while [ $i -le $retries ]; do
if fail2ban-client ping >/dev/null 2>&1; then
green "✅ Fail2Ban 启动成功"
echo
fail2ban-client status || true
echo
fail2ban-client status sshd || true
return 0
fi
sleep 1
i=$((i+1))
done

red "❌ F
ail
2Ban 启动超时，请手动排查："
echo "systemctl status fail2ban --no-pager -l"
echo "journalctl -u fail2ban -n 80 --no-pager"
return 1
}
install_f2b() {
yellow "🚀 开始安装 / 重装 Fail2Ban 防护..."
detect_os
fix_apt_sources_if_needed
install_packages
detect_ssh_ports
detect_backend
detect_banaction
detect_ssh_unit
backup_existing_config
write_jail_config
write_logrotate

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

echo
green "🎉 配置写入完成"
echo "------------------------------------------------"
echo "系统类型: ${OS_FAMILY}"
echo "SSH端口 : ${SSH_PORTS}"
echo "backend : ${F2B_BACKEND}"
echo "banaction: ${F2B_BANACTION}"
echo "journalmatch: ${SSH_JOURNALMATCH}"
echo "------------------------------------------------"
echo

verify_fail2ban
}

show_status() {
echo
cyan "📊 Fail2Ban 总状态"
echo "------------------------------------------------"
fail2ban-client status || true
echo
}

show_sshd_status() {
echo
cyan "🛡️ SSHD Jail 状态"
echo "------------------------------------------------"
fail2ban-client status sshd || true
echo
}

unban_ip() {
echo
read -rp "请输入要解封的 IP: " TARGET_IP
if [ -z "${TARGET_IP}" ]; then
yellow "⚠️ 未输入 IP，已取消"
return
fi

fail2ban-client set sshd unbanip "${TARGET_IP}" && green "✅ 已尝试解封 ${TARGET_IP}"
}

uninstall_f2b() {
echo
red "⚠️ 你即将执行【足够完整卸载】"
echo "这会执行以下操作："
echo " - 停止 fail2ban"
echo " - 禁用开机自启"
echo " - 删除 jail.local"
echo " - 删除 fail2ban 日志轮转配置"
echo " - 卸载 fail2ban 软件包"
echo " - 清理日志、socket、数据库等残留"
echo
echo "不会主动暴力清空系统全局 iptables / nftables 规则。"
echo

read -rp "确认继续？输入 yes: " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
yellow "已取消卸载"
return
fi

yellow "🧹 正在停止 Fail2Ban..."
systemctl stop fail2ban >/dev/null 2>&1 || true
systemctl disable fail2ban >/dev/null 2>&1 || true

yellow "🧹 正在删除配置文件..."
rm -f /etc/fail2ban/jail.local
rm -f /etc/logrotate.d/fail2ban

yellow "🧹 正在卸载 fail2ban 软件包..."
if [ "${OS_FAMILY}" = "debian" ]; then
apt-get remove -y fail2ban >/dev/null 2>&1 || true
apt-get purge -y fail2ban >/dev/null 2>&1 || true
apt-get autoremove -y >/dev/null 2>&1 || true
else
yum remove -y fail2ban >/dev/null 2>&1 || true
fi

yellow "🧹 正在清理残留文件..."
rm -rf /var/log/fail2ban.log*
rm -rf /var/lib/fail2ban
rm -rf /var/run/fail2ban
rm -rf /run/fail2ban

green "✅ Fail2Ban 已完成卸载"
echo
echo "你可以手动确认："
echo " systemctl status fail2ban"
echo " which fail2ban-client"
echo " ls -lah /etc/fail2ban /var/lib/fail2ban /run/fail2ban"
}

show_menu() {
clear
echo "================================================"
echo " 🛡️ Fail2Ban 一键防护管理脚本"
echo "================================================"
echo " 1. 安装 / 重装 Fail2Ban 防护"
echo " 2. 查看 Fail2Ban 总状态"
echo " 3. 查看 SSHD Jail 状态"
echo " 4. 手动解封 IP"
echo " 5. 卸载当前脚本配置"
echo " 0. 退出"
echo "================================================"
}

main() {
need_root
detect_os || true

while true; do
show_menu
read -rp "请输入选项 [0-5]: " CHOICE
case "${CHOICE}" in
1)
install_f2b
read -rp "按回车继续..."
;;
2)
show_status
read -rp "按回车继续..."
;;
3)
show_sshd_status
read -rp "按回车继续..."
;;
4)
unban_ip
read -rp "按回车继续..."
;;
5)
uninstall_f2b
read -rp "按回车继续..."
;;
0)
green "已退出"
exit 0
;;
*)
red "无效选项，请重新输入"
sleep 1
;;
esac
done
}

main "$@"
