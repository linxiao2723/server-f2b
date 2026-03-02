#!/bin/bash

# ====================================================
# Fail2Ban 全自动一键部署脚本 (终极兼容版)
# 适用：Debian/Ubuntu/CentOS
# 功能：自动修源 + 基础防护 + 惯犯重罚 + 日志维护
# ====================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请以 root 权限运行此脚本"
  exit 1
fi

echo "🛠️  步骤 1: 正在修复系统环境..."

# 自动处理 Debian Bullseye backports 404 错误
if [ -f /etc/apt/sources.list ]; then
    sed -i '/backports/s/^/#/' /etc/apt/sources.list 2>/dev/null
    rm -f /etc/apt/sources.list.d/backports.list 2>/dev/null
fi

# 2. 软件安装
echo "📦 步骤 2: 正在安装 Fail2Ban 及必要组件..."
if [ -f /etc/debian_version ]; then
    apt-get update -qq
    apt-get install -y fail2ban python3-systemd iptables >/dev/null
elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release >/dev/null
    yum install -y fail2ban iptables >/dev/null
fi

# 3. 解决 Debian 11/12+ 的 iptables 兼容性警告
if [ -f /usr/sbin/iptables-legacy ]; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1
fi

echo "📝 步骤 3: 正在注入安全防御规则..."

# 4. 写入整合配置
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime  = 1d
findtime = 10m
maxretry = 3
banaction = iptables-multiport
banaction_allports = iptables-allports

[sshd]
enabled = true
port    = ssh
backend = systemd
mode    = aggressive

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
banaction = iptables-allports
findtime = 1d
maxretry = 3
bantime  = 7d
protocol = tcp
EOF

# 5. 配置日志自动轮转
echo "🧹 步骤 4: 正在配置日志自动管理..."
cat <<EOF > /etc/logrotate.d/fail2ban
/var/log/fail2ban.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        /usr/bin/fail2ban-client flushlogs >/dev/null || true
    endscript
}
EOF

# 6. 重启服务
systemctl stop fail2ban >/dev/null 2>&1
systemctl enable fail2ban >/dev/null 2>&1
systemctl start fail2ban

echo "✅ 部署完成！"
echo "------------------------------------------------"
echo "🛡️  服务器已进入高强度受保护状态"
echo "------------------------------------------------"
fail2ban-client status sshd
