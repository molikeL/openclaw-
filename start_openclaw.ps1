# ==============================================================
# OpenClaw 中文版 — 一键启动脚本
# 版本: 1.0
# 用途: 启动 OpenClaw gateway 服务并自动打开管理面板
# ==============================================================

#Requires -Version 5.1

# ── 路径与日志 ──
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir    = Join-Path $ScriptDir "logs"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $LogDir "launch_$Timestamp.log"
$DashboardUrl = "http://localhost:18789"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR","WSL")]
        [string]$Level = "INFO"
    )
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        "INFO"    { Write-Host $line -ForegroundColor Cyan   }
        "SUCCESS" { Write-Host $line -ForegroundColor Green  }
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        "ERROR"   { Write-Host $line -ForegroundColor Red    }
        "WSL"     { Write-Host "  $line" -ForegroundColor Gray }
    }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Write-Separator {
    $s = "-" * 62
    Write-Host $s -ForegroundColor DarkGray
    Add-Content -Path $LogFile -Value $s -Encoding UTF8
}

# ══════════════════════════════════════════════════════════════
# 前置检查
# ══════════════════════════════════════════════════════════════
function Test-Prerequisites {
    Write-Log "检测运行环境..." "INFO"

    # 检查 WSL 是否存在
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Log "错误: 未检测到 WSL，请先运行 deploy.bat 完成部署" "ERROR"
        return $false
    }

    # 检查 Ubuntu 是否安装
    $list = wsl --list --quiet 2>$null
    if ($list -notmatch "Ubuntu") {
        Write-Log "错误: WSL 中未找到 Ubuntu，请先运行 deploy.bat 完成部署" "ERROR"
        return $false
    }

    # 检查 openclaw 命令
    $which = wsl -d Ubuntu -- bash -lc "which openclaw 2>/dev/null" 2>$null
    if (-not $which -or $which.Trim() -eq "") {
        Write-Log "错误: 未检测到 openclaw 命令，请先运行 deploy.bat 完成部署" "ERROR"
        return $false
    }

    Write-Log "环境检测通过 ✓" "SUCCESS"
    return $true
}

# ══════════════════════════════════════════════════════════════
# 检查服务状态
# ══════════════════════════════════════════════════════════════
function Get-GatewayStatus {
    $status = wsl -d Ubuntu -- bash -lc "openclaw gateway status 2>&1" 2>$null
    return $status
}

function Test-GatewayRunning {
    # 尝试连接本地端口 18789
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", 18789)
        $tcp.Close()
        return $true
    } catch {
        return $false
    }
}

# ══════════════════════════════════════════════════════════════
# 启动 Gateway
# ══════════════════════════════════════════════════════════════
function Start-OpenClawGateway {
    Write-Separator
    Write-Log "正在启动 OpenClaw Gateway..." "INFO"

    # 若已在运行则直接返回
    if (Test-GatewayRunning) {
        Write-Log "OpenClaw Gateway 已经在运行 ✓" "SUCCESS"
        return $true
    }

    # 检查服务状态
    $status = Get-GatewayStatus
    if ($status) {
        Write-Log "当前状态: $($status -join ' ')" "INFO"
    }

    # 后台启动 gateway —— 用 nohup 确保进程与终端完全分离
    Write-Log "在 WSL Ubuntu 后台启动 Gateway..." "INFO"
    Start-Process -FilePath "wsl" `
        -ArgumentList "-d", "Ubuntu", "--", "bash", "-lc",
                      "nohup openclaw gateway start </dev/null >>/tmp/openclaw_gateway.log 2>&1 &" `
        -WindowStyle Hidden -ErrorAction SilentlyContinue

    # 等待端口就绪 (最多 30 秒)
    Write-Log "等待 Gateway 就绪 (最多 30 秒)..." "INFO"
    $waited = 0
    while ($waited -lt 30) {
        Start-Sleep -Seconds 2
        $waited += 2
        if (Test-GatewayRunning) {
            Write-Log "OpenClaw Gateway 启动成功 ✓ (耗时 ${waited}s)" "SUCCESS"
            return $true
        }
        Write-Host "." -NoNewline -ForegroundColor DarkGray
    }
    Write-Host ""

    if (Test-GatewayRunning) {
        Write-Log "OpenClaw Gateway 启动成功 ✓" "SUCCESS"
        return $true
    }

    Write-Log "警告: Gateway 可能需要更长时间启动，请稍后刷新浏览器" "WARNING"
    return $true  # 仍然尝试打开浏览器
}

# ══════════════════════════════════════════════════════════════
# 打开管理面板
# ══════════════════════════════════════════════════════════════
function Open-Dashboard {
    Write-Log "正在打开管理面板: $DashboardUrl" "INFO"
    try {
        Start-Process $DashboardUrl
        Write-Log "已在默认浏览器中打开管理面板 ✓" "SUCCESS"
    } catch {
        Write-Log "警告: 无法自动打开浏览器，请手动访问: $DashboardUrl" "WARNING"
    }
}

# ══════════════════════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════════════════════
function Main {
    Write-Host ""
    Write-Host " ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host " ║         OpenClaw 中文版 — 一键启动器  v1.0              ║" -ForegroundColor Cyan
    Write-Host " ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "====== 启动 OpenClaw ======" "INFO"
    Write-Log "日志文件: $LogFile" "INFO"

    if (-not (Test-Prerequisites)) {
        Write-Host ""
        Write-Host " 请先运行 deploy.bat 完成 OpenClaw 的安装部署。" -ForegroundColor Yellow
        Write-Host ""
        Write-Host " 按任意键退出..." -ForegroundColor DarkGray
        try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Read-Host "按 Enter 键退出" | Out-Null }
        exit 1
    }

    if (-not (Start-OpenClawGateway)) {
        Write-Log "Gateway 启动异常，请检查日志" "ERROR"
    }

    Open-Dashboard

    Write-Separator
    Write-Log "管理面板地址: $DashboardUrl" "INFO"
    Write-Log "如需停止服务，请在 WSL Ubuntu 中运行: openclaw gateway stop" "INFO"
    Write-Log "日志文件: $LogFile" "INFO"
    Write-Separator
    Write-Host ""
    Write-Host " OpenClaw 已在后台运行。关闭此窗口不会停止服务。" -ForegroundColor Green
    Write-Host ""
    Write-Host " 按任意键关闭此窗口..." -ForegroundColor DarkGray
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Read-Host "按 Enter 键关闭此窗口" | Out-Null }
}

Main
