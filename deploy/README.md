# OpenClaw 中文版 Windows 一键部署工具

> 适用于 Windows 10/11，在陌生电脑上快速部署 [OpenClaw 中文版](https://github.com/jiulingyun/openclaw-cn)。

---

## 目录结构

```
deploy/
├── deploy.bat          # 一键部署脚本（双击运行）
├── deploy.ps1          # 部署 PowerShell 主脚本
├── start.bat           # 一键启动脚本（双击运行）
├── start.ps1           # 启动 PowerShell 主脚本
├── openclaw.config.json# 部署后自动生成的配置文件
├── logs/               # 日志输出目录
│   └── *.log           # 每次运行自动生成带时间戳的日志
└── README.md           # 本文档
```

---

## 快速开始

### 第一步：一键部署

1. **右键点击** `deploy.bat`，选择 **「以管理员身份运行」**
2. 在 UAC 弹窗中点击 **「是」**
3. 脚本将自动完成以下操作：
   - ✅ 检测 Windows 版本
   - ✅ 自动安装 Git（若未安装）
   - ✅ 自动安装 Node.js 22 LTS（若未安装或版本过低）
   - ✅ 自动安装 pnpm（若未安装）
   - ✅ 克隆 OpenClaw 中文版仓库
   - ✅ 安装项目依赖
   - ✅ 输出详细日志到 `logs/` 目录

> **默认安装目录：** `%USERPROFILE%\openclaw-cn`（例如 `C:\Users\你的用户名\openclaw-cn`）

### 第二步：一键启动

部署完成后，**双击** `start.bat` 即可启动 OpenClaw 服务，浏览器将自动打开管理界面。

---

## 高级用法

### 自定义安装目录

在命令提示符（管理员）中运行：

```powershell
PowerShell -ExecutionPolicy Bypass -File deploy.ps1 -InstallDir "D:\openclaw-cn"
```

### 强制重新部署

如需删除旧版本并重新安装：

```powershell
PowerShell -ExecutionPolicy Bypass -File deploy.ps1 -Force
```

### 启动时不打开浏览器

```powershell
PowerShell -ExecutionPolicy Bypass -File start.ps1 -NoBrowser
```

### 指定自定义端口

```powershell
PowerShell -ExecutionPolicy Bypass -File start.ps1 -Port 8080
```

---

## 系统要求

| 项目 | 最低要求 | 推荐 |
|------|----------|------|
| 操作系统 | Windows 10 (1809+) x64 | Windows 11 |
| 内存 | 4 GB | 8 GB+ |
| 磁盘空间 | 2 GB 可用 | 10 GB+ |
| 网络 | 可访问 GitHub 和 npm | 国内用户可使用代理 |
| Node.js | v22 LTS（自动安装） | 最新 LTS |
| Git | 任意版本（自动安装） | 最新版 |

---

## 日志说明

每次运行 `deploy.bat` 或 `start.bat`，都会在 `logs/` 目录下生成带时间戳的日志文件：

- `deploy_YYYYMMDD_HHmmss.log` — 部署日志
- `start_YYYYMMDD_HHmmss.log` — 启动日志

日志中包含以下级别：

| 标志 | 含义 |
|------|------|
| `[INFO]` | 普通信息 |
| `[STEP]` | 执行步骤 |
| `[SUCCESS]` | 操作成功 |
| `[WARN]` | 警告（不影响主流程） |
| `[ERROR]` | 错误（可能导致部署失败） |

---

## 常见问题

### 问：运行时提示「执行策略」错误？

脚本使用了 `-ExecutionPolicy Bypass` 参数，正常情况下不会出现此错误。
如果仍然出现，请以管理员身份在 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 问：克隆仓库时失败（网络问题）？

国内用户访问 GitHub 可能较慢，建议：
1. 使用 VPN 或代理
2. 或将仓库地址更换为 Gitee 镜像（如有）

### 问：安装依赖时失败？

脚本已配置 npmmirror.com 国内镜像加速。如仍然失败，请检查：
1. 网络连接是否正常
2. 查看 `logs/` 目录下的日志文件
3. 尝试手动运行：`cd %USERPROFILE%\openclaw-cn && npm install`

### 问：启动时提示找不到安装目录？

请先运行 `deploy.bat` 完成部署，再使用 `start.bat` 启动。

---

## 项目来源

- OpenClaw 中文版：[https://github.com/jiulingyun/openclaw-cn](https://github.com/jiulingyun/openclaw-cn)
- 本部署工具：[https://github.com/molikeL/openclaw-](https://github.com/molikeL/openclaw-)
