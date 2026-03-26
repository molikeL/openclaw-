# OpenClaw 中文版 — Windows 一键部署工具

适用于 Windows 10 / Windows 11 的 OpenClaw 中文版自动部署与一键启动工具。  
可在陌生电脑上全自动完成环境配置、依赖安装和 OpenClaw 部署。

---

## 文件说明

| 文件 | 用途 |
|---|---|
| `deploy.bat` | **一键部署入口**（双击运行，自动申请管理员权限） |
| `deploy.ps1` | PowerShell 部署核心脚本 |
| `start_openclaw.bat` | **一键启动入口**（部署完成后使用） |
| `start_openclaw.ps1` | PowerShell 启动核心脚本 |
| `logs/` | 所有日志文件（自动生成） |

---

## 快速开始

### 第一步：一键部署

1. 右键 `deploy.bat` → **以管理员身份运行**（或直接双击，脚本会自动申请权限）  
2. 按照屏幕提示操作（如果需要重启，重启后会自动继续）  
3. 部署完成后桌面会出现 **"启动 OpenClaw"** 快捷方式

> 首次使用，在 Ubuntu (WSL) 终端运行 `openclaw onboard` 完成初始配置（选择 AI 模型、配置渠道等）。

### 第二步：一键启动

部署完成后，每次使用：

- 双击桌面 **"启动 OpenClaw"** 快捷方式，或  
- 双击 `start_openclaw.bat`

启动器会自动：
1. 检测运行环境
2. 在 WSL2 Ubuntu 后台启动 OpenClaw Gateway
3. 打开浏览器进入管理面板（`http://localhost:18789`）

---

## 部署内容（自动完成）

脚本会按顺序自动完成以下 6 个阶段：

| 阶段 | 内容 |
|---|---|
| 1 | 检测 Windows 版本、磁盘空间、内存、网络、管理员权限 |
| 2 | 启用 WSL2（Windows Subsystem for Linux 2）功能 |
| 3 | 安装 Ubuntu 22.04（WSL2 发行版） |
| 4 | 在 Ubuntu 中安装 Node.js 22+ |
| 5 | 全局安装 `openclaw` npm 包 |
| 6 | 创建桌面快捷方式 |

如果阶段 2 需要重启，脚本会自动注册计划任务，**重启后从断点继续**，无需手动干预。

---

## 系统要求

- **操作系统**：Windows 10 (Build 19041+) / Windows 11
- **架构**：64 位
- **内存**：建议 ≥ 4 GB
- **磁盘**：建议剩余 ≥ 10 GB
- **网络**：需要能访问 npm registry（国内环境可在 `deploy.ps1` 中取消注释淘宝镜像行）
- **权限**：管理员权限（用于启用 WSL2 功能）

---

## 日志

所有操作均会记录日志，文件保存在 `logs/` 目录：

- `deploy_YYYYMMDD_HHMMSS.log` — 部署日志
- `launch_YYYYMMDD_HHMMSS.log` — 启动日志

---

## 常见问题

**Q: 部署时提示需要重启，重启后没有自动继续怎么办？**  
A: 再次双击 `deploy.bat`，脚本会自动从上次断点继续。

**Q: 国内网络安装 npm 包很慢怎么办？**  
A: 打开 `deploy.ps1`，找到 `# npm config set registry https://registry.npmmirror.com` 这一行，去掉行首的 `#` 注释即可使用淘宝镜像。

**Q: 如何手动启动/停止服务？**  
A: 打开 WSL Ubuntu 终端，运行：
```bash
openclaw gateway start   # 启动
openclaw gateway stop    # 停止
openclaw gateway status  # 查看状态
openclaw dashboard       # 打开管理面板
```

**Q: 管理面板地址是什么？**  
A: `http://localhost:18789`
