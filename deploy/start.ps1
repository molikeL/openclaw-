#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw 中文版 一键启动脚本

.DESCRIPTION
    本脚本用于在 Windows 上一键启动已部署的 OpenClaw 中文版服务。
    功能包括：
      1. 读取部署配置，自动定位安装目录
      2. 检查安装完整性
      3. 启动 OpenClaw 服务
      4. 自动在浏览器中打开管理界面
      5. 记录启动日志

.PARAMETER InstallDir
    手动指定安装目录（若配置文件不存在时使用）。

.PARAMETER NoBrowser
    启动服务后不自动打开浏览器。

.PARAMETER Port
    OpenClaw 监听端口，默认为 3000。
#>

[CmdletBinding()]
param(
    [string]$InstallDir = '',
    [switch]$NoBrowser,
    [int]$Port = 3000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# 常量定义
# ============================================================
$LOG_DIR       = Join-Path $PSScriptRoot 'logs'
$LOG_TIMESTAMP = (Get-Date -Format 'yyyyMMdd_HHmmss')
$LOG_FILE      = Join-Path $LOG_DIR "start_$LOG_TIMESTAMP.log"
$CONFIG_FILE   = Join-Path $PSScriptRoot 'openclaw.config.json'

# ============================================================
# 辅助函数
# ============================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','STEP')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line      = "[$timestamp][$Level] $Message"

    $color = switch ($Level) {
        'INFO'    { 'Cyan'    }
        'WARN'    { 'Yellow'  }
        'ERROR'   { 'Red'     }
        'SUCCESS' { 'Green'   }
        'STEP'    { 'Magenta' }
        default   { 'White'   }
    }

    Write-Host $line -ForegroundColor $color

    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    try {
        Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
    } catch {
        # 日志写入失败不中断主流程
    }
}

function Get-CommandVersion {
    param([string]$Command, [string]$VersionArg = '--version')
    try {
        $output = & $Command $VersionArg 2>&1
        return ($output | Select-Object -First 1).ToString().Trim()
    } catch {
        return $null
    }
}

# ============================================================
# 脚本头信息
# ============================================================
Write-Log ('=' * 60)                       -Level INFO
Write-Log ' OpenClaw 中文版 一键启动脚本'  -Level INFO
Write-Log " 启动时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
Write-Log " 日志文件: $LOG_FILE"            -Level INFO
Write-Log ('=' * 60)                       -Level INFO

# ============================================================
# 步骤 1: 读取部署配置
# ============================================================
Write-Log '步骤 1/4: 读取部署配置...' -Level STEP

if ($InstallDir -eq '') {
    if (Test-Path $CONFIG_FILE) {
        try {
            $config     = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
            $InstallDir = $config.InstallDir
            Write-Log "从配置文件读取安装目录: $InstallDir" -Level SUCCESS
            Write-Log "部署时间: $($config.DeployedAt)" -Level INFO
            Write-Log "Node.js 版本: $($config.NodeVersion)" -Level INFO
            Write-Log "包管理器: $($config.PackageManager)" -Level INFO
        } catch {
            Write-Log "读取配置文件失败: $_" -Level WARN
            $InstallDir = "$env:USERPROFILE\openclaw-cn"
            Write-Log "使用默认目录: $InstallDir" -Level WARN
        }
    } else {
        $InstallDir = "$env:USERPROFILE\openclaw-cn"
        Write-Log "未找到配置文件，使用默认安装目录: $InstallDir" -Level WARN
        Write-Log "提示: 请先运行 deploy.bat 完成部署。" -Level WARN
    }
}

# ============================================================
# 步骤 2: 检查安装完整性
# ============================================================
Write-Log '步骤 2/4: 检查安装完整性...' -Level STEP

if (-not (Test-Path $InstallDir)) {
    Write-Log "安装目录不存在: $InstallDir" -Level ERROR
    Write-Log '请先运行 deploy.bat 完成安装后，再使用本启动脚本。' -Level ERROR
    Read-Host '按 Enter 键退出'
    exit 1
}

$nodeModules = Join-Path $InstallDir 'node_modules'
if (-not (Test-Path $nodeModules)) {
    Write-Log "node_modules 目录不存在，依赖可能未正确安装。" -Level ERROR
    Write-Log '请先运行 deploy.bat 重新部署。' -Level ERROR
    Read-Host '按 Enter 键退出'
    exit 1
}

$packageJson = Join-Path $InstallDir 'package.json'
if (-not (Test-Path $packageJson)) {
    Write-Log "package.json 不存在，安装可能不完整。" -Level ERROR
    Read-Host '按 Enter 键退出'
    exit 1
}

Write-Log '安装完整性检查通过。' -Level SUCCESS

# ============================================================
# 步骤 3: 检测并确认运行时环境
# ============================================================
Write-Log '步骤 3/4: 确认运行环境...' -Level STEP

$nodeVer = Get-CommandVersion -Command 'node'
if (-not $nodeVer) {
    Write-Log 'Node.js 未找到！请先运行 deploy.bat 完成环境配置。' -Level ERROR
    Read-Host '按 Enter 键退出'
    exit 1
}
Write-Log "Node.js: $nodeVer" -Level SUCCESS

# 读取 package.json 中的启动命令
$pkg        = Get-Content $packageJson -Raw | ConvertFrom-Json
$startScript = $null

# 按优先级检测可用的启动命令
foreach ($scriptName in @('start', 'serve', 'dev')) {
    if ($pkg.scripts.PSObject.Properties.Name -contains $scriptName) {
        $startScript = $scriptName
        break
    }
}

if (-not $startScript) {
    Write-Log "未在 package.json 中找到可用的启动脚本（start/serve/dev）。" -Level ERROR
    Write-Log '请检查安装是否完整，或参考项目文档手动启动。' -Level ERROR
    Read-Host '按 Enter 键退出'
    exit 1
}

Write-Log "检测到启动命令: $startScript" -Level SUCCESS

# ============================================================
# 步骤 4: 启动 OpenClaw 服务
# ============================================================
Write-Log '步骤 4/4: 启动 OpenClaw 服务...' -Level STEP

# 选择包管理器
$pkgManager = if (Get-CommandVersion -Command 'pnpm') { 'pnpm' } else { 'npm' }
Write-Log "使用包管理器: $pkgManager" -Level INFO

Write-Log ('=' * 60)                                              -Level INFO
Write-Log ' OpenClaw 正在启动，请稍候...'                         -Level SUCCESS
Write-Log " 服务地址: http://localhost:$Port"                     -Level INFO
Write-Log ' 按 Ctrl+C 可停止服务'                                 -Level INFO
Write-Log ('=' * 60)                                              -Level INFO

# 如果未设置 --NoBrowser，稍等后自动打开浏览器
if (-not $NoBrowser) {
    $url = "http://localhost:$Port"
    Write-Log "将在 3 秒后自动打开浏览器: $url" -Level INFO
    Start-Job -Name 'OpenBrowser' -ScriptBlock {
        param($u)
        Start-Sleep -Seconds 3
        Start-Process $u
    } -ArgumentList $url | Out-Null
}

# 切换到安装目录并启动服务
Push-Location $InstallDir
try {
    Write-Log "工作目录: $InstallDir" -Level INFO
    Write-Log "执行命令: $pkgManager run $startScript" -Level INFO
    Write-Log ('─' * 60) -Level INFO

    if ($pkgManager -eq 'pnpm') {
        & pnpm run $startScript
    } else {
        & npm run $startScript
    }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Log "OpenClaw 服务退出，退出码: $exitCode" -Level WARN
    } else {
        Write-Log 'OpenClaw 服务已正常停止。' -Level SUCCESS
    }
} catch {
    Write-Log "启动过程中发生错误: $_" -Level ERROR
} finally {
    Pop-Location
    # 清理后台打开浏览器的 Job
    Get-Job -Name 'OpenBrowser' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
}

Write-Log "日志已保存: $LOG_FILE" -Level INFO
