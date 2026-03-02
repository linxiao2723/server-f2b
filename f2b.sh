#!/bin/bash

# ====================================================
# Fail2Ban 全能防御一键部署脚本
# 包含：SSH防护 + 惯犯7天封禁 + 日志自动管理
# ====================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请以 root 权限运行此脚本 (sudo ./script.sh)"
  exit 1
fi

echo "🚀 开始部署 Fail2Ban 安全防御体系..."

# 2. 自动识别并安装软件包
if [ -f /etc/debian_version ]; then
    apt update && apt install -y fail2ban python3-systemd iptables
elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release
    yum install -y fail2ban iptables
else
    echo "❌ 暂不支持的系统发行版。"
    exit 1
fi

# 3. 备份现有配置（如有）
[ -f /etc/fail2ban/jail.local ] && cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak

echo "📝 注入安全规则 (SSH + Recidive)..."

# 4. 写入整合配置
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
# 忽略本机及本地链路
ignoreip = 127.0.0.1/8 ::1
# 基础封禁：1天
bantime  = 1d
# 查找间隔：10分钟
findtime = 10m
# 尝试次数：3次
maxretry = 3
# 使用最稳定的 iptables 动作
banaction = iptables-multiport
banaction_allports = iptables-allports

[sshd]
# 开启 SSH 监控
enabled = true
port    = ssh
backend = systemd
# 开启激进模式，匹配更多非法尝试
mode    = aggressive

[recidive]
# 惯犯监控：针对反复被封的 IP
enabled  = true
logpath  = /var/log/fail2ban.log
banaction = iptables-allports
# 查找过去 1 天内被封禁过的记录
findtime = 1d
# 如果 1 天内被封禁超过 3 次
maxretry = 3
# 直接升级封禁 1 周 (7d)
bantime  = 7d
protocol = tcp
EOF

echo "🧹 配置日志自动轮转..."

# 5. 配置日志管理 (logrotate)
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

# 6. 启动并激活
systemctl enable fail2ban
systemctl restart fail2ban

echo "✅ 部署完成！"
echo "------------------------------------------------"
echo "🛡️ 当前防御状态："
echo "1. 普通攻击：3次失败封 1 天"
echo "2. 顽固攻击：24小时内封 3 次则升级封 7 天"
echo "3. 日志管理：每周自动清理压缩，保留 4 周"
echo "------------------------------------------------"
echo "💡 常用查看命令："
echo "- 查看SSH拦截：sudo fail2ban-client status sshd"
echo "- 查看惯犯名单：sudo fail2ban-client status recidive"
echo "- 查看实时日志：sudo tail -f /var/log/fail2ban.log"
echo "------------------------------------------------"