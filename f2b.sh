#!/bin/bash

# ====================================================
# Fail2Ban 全自动一键部署脚本 (终极优化版)
# 包含：自动修源 + 阶梯封禁 + 惯犯重罚 + 日志维护
# ====================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请以 root 权限运行此脚本"
  exit 1
fi

echo "🛠️  步骤 1: 正在清理并修复系统环境..."
# 自动处理 Debian Bullseye 软件源 404 问题
if [ -f /etc/apt/sources.list ]; then
    sed -i '/backports/s/^/#/' /etc/apt/sources.list 2>/dev/null
    rm -f /etc/apt/sources.list.d/backports.list 2>/dev/null
fi

# 2. 强制安装组件
echo "📦 步骤 2: 正在安装 Fail2Ban 及必要组件..."
if [ -f /etc/debian_version ]; then
    apt-get update -qq
    apt-get install -y fail2ban python3-systemd iptables >/dev/null
elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release >/dev/null
    yum install -y fail2ban iptables >/dev/null
fi

# 3. 解决 iptables 兼容性问题
if [ -f /usr/sbin/iptables-legacy ]; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1
fi

echo "📝 步骤 3: 正在注入终极优化规则..."

# 4. 写入整合配置 (含阶梯封禁)
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
# 白名单：请在后面添加你的固定 IP (如有)
ignoreip = 127.0.0.1/8 ::1

# --- 阶梯封禁核心配置 ---
# 基础封禁时间：1天
bantime  = 1d
# 开启时间递增功能
bantime.increment = true
# 增长倍数：1天 -> 2天 -> 4天 -> 8天...
bantime.factor = 2
# 最大封禁上限：5周 (让顽固分子彻底消失)
bantime.maxtime = 5w

# 触发条件：10分钟内失败 3 次
findtime = 10m
maxretry = 3

# 防火墙动作
banaction = iptables-multiport
banaction_allports = iptables-allports

[sshd]
enabled = true
port    = ssh
backend = systemd
# 激进模式：捕获所有非法尝试
mode    = aggressive

[recidive]
# 惯犯监狱：针对在其他监狱反复进出的 IP
enabled  = true
logpath  = /var/log/fail2ban.log
banaction = iptables-allports
findtime = 1d
maxretry = 3
# 惯犯直接从 1 周封禁起步
bantime  = 1w
# 惯犯监狱不使用递增，避免逻辑过载
bantime.increment = false
protocol = tcp
EOF

# 5. 配置日志管理 (logrotate)
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

# 6. 重启并验证
systemctl stop fail2ban >/dev/null 2>&1
systemctl enable fail2ban >/dev/null 2>&1
systemctl start fail2ban

echo "✅ 终极部署完成！"
echo "------------------------------------------------"
echo "🛡️  已启用：[阶梯封禁] + [惯犯重罚] + [日志轮转]"
echo "📊 当前 SSH 拦截状态："
fail2ban-client status sshd
