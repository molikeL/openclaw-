#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw 中文版 Windows 一键部署脚本

.DESCRIPTION
    本脚本用于在 Windows 环境下一键部署 OpenClaw 中文版（openclaw-cn）。
    功能包括：
      1. 环境检测 - 检测并自动安装缺失的依赖（Node.js、Git、pnpm）
      2. 一键部署 - 自动克隆仓库、安装依赖、初始化服务
      3. 日志记录 - 无论成功或失败，均输出详细日志文件

.PARAMETER InstallDir
    OpenClaw 的安装目录，默认为用户主目录下的 openclaw-cn 文件夹。

.PARAMETER LogDir
    日志文件输出目录，默认为脚本所在目录下的 logs 文件夹。

.PARAMETER SkipEnvCheck
    跳过环境检测步骤（不推荐，仅供调试使用）。

.PARAMETER Force
    强制重新部署，即使目标目录已存在也会覆盖。

.EXAMPLE
    # 使用默认参数部署
    .\deploy.ps1

    # 自定义安装目录
    .\deploy.ps1 -InstallDir "D:\openclaw-cn"

    # 强制重新部署
    .\deploy.ps1 -Force
#>

[CmdletBinding()]
param(
    [string]$InstallDir = "$env:USERPROFILE\openclaw-cn",
    [string]$LogDir     = "$PSScriptRoot\logs",
    [switch]$SkipEnvCheck,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# 常量定义
# ============================================================
$OPENCLAW_REPO      = 'https://github.com/jiulingyun/openclaw-cn.git'
$NODE_VERSION_MIN   = 22          # Node.js 最低版本号（主版本）
$NODE_WINGET_ID     = 'OpenJS.NodeJS.LTS'
$GIT_WINGET_ID      = 'Git.Git'
$PNPM_INSTALL_URL   = 'https://get.pnpm.io/install.ps1'
$LOG_TIMESTAMP      = (Get-Date -Format 'yyyyMMdd_HHmmss')
$LOG_FILE           = Join-Path $LogDir "deploy_$LOG_TIMESTAMP.log"

# ============================================================
# 辅助函数
# ============================================================

function Write-Log {
    <#
    .SYNOPSIS 同时向控制台和日志文件写出一条日志记录。#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','STEP')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line      = "[$timestamp][$Level] $Message"

    # 控制台颜色
    $color = switch ($Level) {
        'INFO'    { 'Cyan'    }
        'WARN'    { 'Yellow'  }
        'ERROR'   { 'Red'     }
        'SUCCESS' { 'Green'   }
        'STEP'    { 'Magenta' }
        default   { 'White'   }
    }

    Write-Host $line -ForegroundColor $color

    # 追加到日志文件
    try {
        Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
    } catch {
        Write-Host "[WARN] 无法写入日志文件: $_" -ForegroundColor Yellow
    }
}

function Test-Administrator {
    <#.SYNOPSIS 检测当前 PowerShell 会话是否以管理员权限运行。#>
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CommandVersion {
    <#.SYNOPSIS 尝试获取命令的版本字符串，若命令不存在则返回 $null。#>
    param([string]$Command, [string]$VersionArg = '--version')
    try {
        $output = & $Command $VersionArg 2>&1
        return ($output | Select-Object -First 1).ToString().Trim()
    } catch {
        return $null
    }
}

function Test-WingetAvailable {
    <#.SYNOPSIS 检测 winget 是否可用。#>
    try {
        $null = & winget --version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Install-WithWinget {
    <#.SYNOPSIS 通过 winget 静默安装指定软件包，失败则抛出异常。#>
    param([string]$PackageId, [string]$FriendlyName)
    Write-Log "正在通过 winget 安装 $FriendlyName ($PackageId)..." -Level STEP
    $result = & winget install --id $PackageId --silent --accept-package-agreements --accept-source-agreements 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "winget 安装 $FriendlyName 失败（退出码 $LASTEXITCODE）。详情：$result"
    }
    Write-Log "$FriendlyName 安装完成。" -Level SUCCESS
}

function Invoke-RefreshPath {
    <#
    .SYNOPSIS 刷新当前会话的 PATH 环境变量（从注册表重新加载）。
    .NOTES   安装新软件后需要刷新 PATH，否则新命令无法在同一会话中调用。
    #>
    $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH    = "$machinePath;$userPath"
}

# ============================================================
# 初始化日志目录
# ============================================================
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# 清除旧的 $Error 记录
$Error.Clear()

# ============================================================
# 脚本头信息
# ============================================================
Write-Log ('=' * 60)                        -Level INFO
Write-Log ' OpenClaw 中文版 一键部署脚本'   -Level INFO
Write-Log " 版本: 1.0  日期: $(Get-Date -Format 'yyyy-MM-dd')" -Level INFO
Write-Log " 日志文件: $LOG_FILE"             -Level INFO
Write-Log ('=' * 60)                        -Level INFO

# ============================================================
# 步骤 0: 权限检测
# ============================================================
Write-Log '步骤 0/5: 检测运行权限...' -Level STEP
if (-not (Test-Administrator)) {
    Write-Log '当前未以管理员权限运行。部分安装步骤可能需要管理员权限。' -Level WARN
    Write-Log '建议：右键点击 deploy.bat，选择「以管理员身份运行」。' -Level WARN
} else {
    Write-Log '已以管理员权限运行。' -Level SUCCESS
}

# ============================================================
# 步骤 1: 环境检测
# ============================================================
if (-not $SkipEnvCheck) {
    Write-Log '步骤 1/5: 开始环境检测...' -Level STEP

    # --- 1.1 Windows 版本 ---
    Write-Log '检测 Windows 版本...' -Level INFO
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Log "操作系统: $($osInfo.Caption) (版本号: $($osInfo.Version))" -Level INFO

    $buildNumber = [int]($osInfo.BuildNumber)
    if ($buildNumber -lt 17763) {   # Windows 10 1809
        Write-Log '警告: 操作系统版本过低。建议使用 Windows 10 (1809+) 或 Windows 11。' -Level WARN
    } else {
        Write-Log 'Windows 版本检测通过。' -Level SUCCESS
    }

    # --- 1.2 检测 winget ---
    Write-Log '检测 winget 包管理器...' -Level INFO
    $wingetAvailable = Test-WingetAvailable
    if ($wingetAvailable) {
        $wingetVer = & winget --version 2>&1 | Select-Object -First 1
        Write-Log "winget 版本: $wingetVer" -Level SUCCESS
    } else {
        Write-Log 'winget 未检测到。将尝试手动安装依赖。' -Level WARN
    }

    # --- 1.3 检测 Git ---
    Write-Log '检测 Git...' -Level INFO
    $gitVer = Get-CommandVersion -Command 'git'
    if ($gitVer) {
        Write-Log "Git 已安装: $gitVer" -Level SUCCESS
    } else {
        Write-Log 'Git 未安装，正在尝试安装...' -Level WARN
        if ($wingetAvailable) {
            Install-WithWinget -PackageId $GIT_WINGET_ID -FriendlyName 'Git'
            Invoke-RefreshPath
        } else {
            Write-Log '无法自动安装 Git。请手动下载并安装: https://git-scm.com/download/win' -Level ERROR
            throw '缺少 Git，无法继续部署。'
        }

        # 验证安装
        $gitVer = Get-CommandVersion -Command 'git'
        if (-not $gitVer) {
            throw 'Git 安装后仍无法调用，请重启命令行窗口后再试。'
        }
        Write-Log "Git 安装成功: $gitVer" -Level SUCCESS
    }

    # --- 1.4 检测 Node.js ---
    Write-Log '检测 Node.js...' -Level INFO
    $nodeVer = Get-CommandVersion -Command 'node'
    $needNodeInstall = $false

    if ($nodeVer) {
        Write-Log "Node.js 已安装: $nodeVer" -Level INFO
        # 提取主版本号（例如 "v22.13.0" → 22）
        if ($nodeVer -match 'v(\d+)\.') {
            $nodeMajor = [int]$Matches[1]
            if ($nodeMajor -lt $NODE_VERSION_MIN) {
                Write-Log "Node.js 版本 ($nodeMajor) 低于最低要求 ($NODE_VERSION_MIN)，将更新..." -Level WARN
                $needNodeInstall = $true
            } else {
                Write-Log "Node.js 版本满足要求 (主版本: $nodeMajor >= $NODE_VERSION_MIN)。" -Level SUCCESS
            }
        } else {
            Write-Log '无法解析 Node.js 版本号，将尝试重新安装...' -Level WARN
            $needNodeInstall = $true
        }
    } else {
        Write-Log 'Node.js 未安装，正在安装...' -Level WARN
        $needNodeInstall = $true
    }

    if ($needNodeInstall) {
        if ($wingetAvailable) {
            Install-WithWinget -PackageId $NODE_WINGET_ID -FriendlyName 'Node.js LTS'
            Invoke-RefreshPath
        } else {
            Write-Log '无法自动安装 Node.js。请手动下载安装: https://nodejs.org/zh-cn/download' -Level ERROR
            throw '缺少 Node.js，无法继续部署。'
        }

        # 验证安装
        $nodeVer = Get-CommandVersion -Command 'node'
        if (-not $nodeVer) {
            throw 'Node.js 安装后仍无法调用，请重启命令行窗口后再试。'
        }
        Write-Log "Node.js 安装成功: $nodeVer" -Level SUCCESS
    }

    # --- 1.5 检测 npm ---
    Write-Log '检测 npm...' -Level INFO
    $npmVer = Get-CommandVersion -Command 'npm'
    if ($npmVer) {
        Write-Log "npm 已安装: $npmVer" -Level SUCCESS
    } else {
        throw 'npm 未找到。请确认 Node.js 安装完整。'
    }

    # --- 1.6 检测 pnpm（可选但推荐）---
    Write-Log '检测 pnpm...' -Level INFO
    $pnpmVer = Get-CommandVersion -Command 'pnpm'
    if ($pnpmVer) {
        Write-Log "pnpm 已安装: $pnpmVer" -Level SUCCESS
    } else {
        Write-Log 'pnpm 未安装，正在通过 npm 安装...' -Level WARN
        try {
            $pnpmInstallOut = & npm install -g pnpm 2>&1
            Write-Log "pnpm 安装输出: $pnpmInstallOut" -Level INFO
            Invoke-RefreshPath
            $pnpmVer = Get-CommandVersion -Command 'pnpm'
            if ($pnpmVer) {
                Write-Log "pnpm 安装成功: $pnpmVer" -Level SUCCESS
            } else {
                Write-Log 'pnpm 安装后未能在 PATH 中找到，将使用 npm 作为包管理器。' -Level WARN
            }
        } catch {
            Write-Log "pnpm 安装失败: $_。将使用 npm 作为备选。" -Level WARN
        }
    }

    Write-Log '环境检测完成。' -Level SUCCESS
} else {
    Write-Log '步骤 1/5: 已跳过环境检测（--SkipEnvCheck）。' -Level WARN
}

# ============================================================
# 步骤 2: 准备安装目录
# ============================================================
Write-Log "步骤 2/5: 准备安装目录 ($InstallDir)..." -Level STEP

if (Test-Path $InstallDir) {
    if ($Force) {
        Write-Log "目录已存在，因指定 -Force 参数将删除并重新安装..." -Level WARN
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Log '旧目录已清除。' -Level INFO
    } else {
        Write-Log "安装目录已存在: $InstallDir" -Level WARN
        Write-Log '如需重新部署，请使用 -Force 参数，或手动删除该目录后重新运行。' -Level WARN
        Write-Log '跳过克隆步骤，直接进行依赖安装...' -Level INFO
    }
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Log "安装目录已创建: $InstallDir" -Level SUCCESS
}

# ============================================================
# 步骤 3: 克隆/更新 OpenClaw 仓库
# ============================================================
Write-Log '步骤 3/5: 克隆 OpenClaw 中文版仓库...' -Level STEP

$gitDir = Join-Path $InstallDir '.git'
if (Test-Path $gitDir) {
    Write-Log '检测到已有仓库，正在执行 git pull 更新...' -Level INFO
    try {
        Push-Location $InstallDir
        $pullOut = & git pull 2>&1
        Write-Log "git pull 输出: $pullOut" -Level INFO
        Pop-Location
        Write-Log '仓库更新完成。' -Level SUCCESS
    } catch {
        Pop-Location -ErrorAction SilentlyContinue
        Write-Log "git pull 失败: $_。将跳过更新，继续使用现有代码。" -Level WARN
    }
} else {
    Write-Log "正在从 $OPENCLAW_REPO 克隆..." -Level INFO
    $cloneOut = & git clone $OPENCLAW_REPO $InstallDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git clone 失败（退出码 $LASTEXITCODE）。详情：$cloneOut"
    }
    Write-Log "仓库克隆完成: $InstallDir" -Level SUCCESS
}

# ============================================================
# 步骤 4: 安装 Node.js 依赖
# ============================================================
Write-Log '步骤 4/5: 安装项目依赖...' -Level STEP

Push-Location $InstallDir

try {
    # 设置国内 npm 镜像加速
    Write-Log '配置 npm 镜像（npmmirror.com）以加速国内下载...' -Level INFO
    & npm config set registry https://registry.npmmirror.com 2>&1 | Out-Null

    # 选择包管理器
    $pkgManager = if (Get-CommandVersion -Command 'pnpm') { 'pnpm' } else { 'npm' }
    Write-Log "使用包管理器: $pkgManager" -Level INFO

    # 安装依赖
    Write-Log '正在安装依赖（可能需要数分钟，请耐心等待）...' -Level INFO
    if ($pkgManager -eq 'pnpm') {
        $installOut = & pnpm install 2>&1
    } else {
        $installOut = & npm install 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        throw "依赖安装失败（退出码 $LASTEXITCODE）。详情：$installOut"
    }
    Write-Log "依赖安装输出（最后 20 行）:" -Level INFO
    $installOut | Select-Object -Last 20 | ForEach-Object { Write-Log "  $_" -Level INFO }
    Write-Log '依赖安装完成。' -Level SUCCESS

    # 检查是否有构建步骤（package.json 中存在 build 脚本）
    $packageJson = Join-Path $InstallDir 'package.json'
    if (Test-Path $packageJson) {
        $pkg = Get-Content $packageJson -Raw | ConvertFrom-Json
        if ($pkg.scripts.PSObject.Properties.Name -contains 'build') {
            Write-Log '检测到 build 脚本，正在执行构建...' -Level INFO
            if ($pkgManager -eq 'pnpm') {
                $buildOut = & pnpm run build 2>&1
            } else {
                $buildOut = & npm run build 2>&1
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Log "构建失败（退出码 $LASTEXITCODE）。详情：$buildOut" -Level WARN
                Write-Log '构建失败，但继续尝试完成部署...' -Level WARN
            } else {
                Write-Log '项目构建完成。' -Level SUCCESS
            }
        }
    }
} finally {
    Pop-Location
}

# ============================================================
# 步骤 5: 验证部署
# ============================================================
Write-Log '步骤 5/5: 验证部署...' -Level STEP

$checks = @(
    @{ Name = '安装目录';         Path = $InstallDir },
    @{ Name = 'package.json';     Path = (Join-Path $InstallDir 'package.json') },
    @{ Name = 'node_modules 目录'; Path = (Join-Path $InstallDir 'node_modules') }
)

$allPassed = $true
foreach ($check in $checks) {
    if (Test-Path $check.Path) {
        Write-Log "✔ $($check.Name) 存在: $($check.Path)" -Level SUCCESS
    } else {
        Write-Log "✘ $($check.Name) 未找到: $($check.Path)" -Level ERROR
        $allPassed = $false
    }
}

# ============================================================
# 部署完成总结
# ============================================================
Write-Log ('=' * 60) -Level INFO
if ($allPassed) {
    Write-Log '✔ OpenClaw 中文版部署成功！' -Level SUCCESS
    Write-Log "安装目录: $InstallDir" -Level SUCCESS
    Write-Log '使用方法：' -Level INFO
    Write-Log '  • 双击 start.bat 一键启动 OpenClaw' -Level INFO
    Write-Log '  • 或在安装目录中运行: npm start / pnpm start' -Level INFO
} else {
    Write-Log '✘ 部署过程中出现错误，请查阅日志文件排查问题。' -Level ERROR
}
Write-Log " 日志文件已保存: $LOG_FILE" -Level INFO
Write-Log ('=' * 60) -Level INFO

# 将安装路径写入配置文件，供 start.ps1 使用
$configFile = Join-Path $PSScriptRoot 'openclaw.config.json'
$config = @{
    InstallDir  = $InstallDir
    DeployedAt  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    NodeVersion = (Get-CommandVersion -Command 'node')
    PackageManager = if (Get-CommandVersion -Command 'pnpm') { 'pnpm' } else { 'npm' }
}
$config | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8
Write-Log "配置文件已保存: $configFile" -Level INFO

if (-not $allPassed) {
    exit 1
}
