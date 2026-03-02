# 🛡️ Server Fail2Ban 一键全自动防御脚本

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu%20%7C%20CentOS-lightgrey)](https://github.com/linxiao2723/server-f2b)

这是一个为 Linux 服务器设计的 Fail2Ban 高强度防护脚本。它针对常见的 SSH 暴力破解攻击进行了深度优化，具备自动修复系统环境、长期封禁惯犯、日志自动轮转等进阶功能。

## 🚀 快速开始

在 root 权限下执行以下命令，即可完成全自动部署：

```bash
curl -sSO https://raw.githubusercontent.com/linxiao2723/server-f2b/main/f2b.sh && chmod +x f2b.sh && sudo ./f2b.sh
