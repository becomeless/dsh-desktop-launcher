# =====================================================================
#  DeepSeek Harness Desktop Launcher —— 一键安装脚本
#
#  一行安装（PowerShell）：
#    [Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install.ps1 | iex
#
#  也可以下载本文件后右键「使用 PowerShell 运行」。
#  默认安装到 %LOCALAPPDATA%\DeepSeek-Harness-Launcher（无需管理员权限），
#  并在桌面创建 "DeepSeek Harness" 图标。
# =====================================================================

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\DeepSeek-Harness-Launcher",
    [string]$LocalSource = '',            # 指定本地目录则跳过下载（离线安装/测试用）
    [switch]$NoShortcut,
    [switch]$Quiet,
    [switch]$SkipNodeCheck,
    [string]$Branch = 'main',
    [string]$Owner = 'becomeless',
    [string]$Repo = 'dsh-desktop-launcher'
)

# Windows PowerShell 5.1 默认不开 TLS 1.2，先补上
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$T) if (-not $Quiet) { Write-Host $T -ForegroundColor Cyan } }
function Write-Ok   { param([string]$T) if (-not $Quiet) { Write-Host $T -ForegroundColor Green } }
function Write-Bad  { param([string]$T) Write-Host $T -ForegroundColor Red }

$files = @('DSH-Launcher.ps1', 'DSH-Server.ps1', 'DSH-Launcher.vbs', 'DeepSeek-blue.ico', 'uninstall.ps1')

# ---- 0) 前置检查：Node.js / npx ----
if (-not $SkipNodeCheck -and -not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Bad '未检测到 Node.js（DeepSeek Harness 需要 npx 来运行）。'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if ($Quiet) { Write-Bad '请先安装 Node.js（https://nodejs.org），然后重新运行安装命令。'; exit 1 }
        $ans = Read-Host '要现在用 winget 自动安装 Node.js LTS 吗？(Y/N)'
        if ($ans -match '^[Yy]') {
            winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
            if (Get-Command npx -ErrorAction SilentlyContinue) {
                Write-Ok 'Node.js 安装完成。'
            } else {
                Write-Bad 'Node.js 已安装但当前窗口还没生效。请新开一个 PowerShell 窗口后重新运行安装命令。'
                exit 1
            }
        } else {
            Write-Bad '请先安装 Node.js（https://nodejs.org），然后重新运行安装命令。'
            exit 1
        }
    } else {
        Write-Bad '请先安装 Node.js（https://nodejs.org），然后重新运行安装命令。'
        exit 1
    }
}

# ---- 1) 获取文件：本地源优先，否则 jsDelivr -> GitHub raw ----
if (-not $LocalSource) {
    $here = $PSScriptRoot
    if ($here -and (Test-Path -LiteralPath (Join-Path $here 'DSH-Launcher.ps1'))) { $LocalSource = $here }
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
if ($LocalSource) {
    Write-Step "从本地复制安装文件：$LocalSource"
    foreach ($f in $files) {
        Copy-Item -LiteralPath (Join-Path $LocalSource $f) -Destination (Join-Path $InstallDir $f) -Force
    }
} else {
    Write-Step '下载安装文件...'
    $srcBase = "https://cdn.jsdelivr.net/gh/$Owner/$Repo@$Branch"
    $srcFallback = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch"
    foreach ($f in $files) {
        $dest = Join-Path $InstallDir $f
        $ok = $false
        foreach ($base in @($srcBase, $srcFallback)) {
            try {
                Invoke-WebRequest -Uri "$base/$f" -OutFile $dest -UseBasicParsing -TimeoutSec 30
                $ok = $true
                break
            } catch { }
        }
        if (-not $ok) { throw "下载失败：$f（已尝试 jsDelivr 和 GitHub 两个源，请检查网络）" }
    }
}
Write-Ok "安装目录：$InstallDir"

# ---- 2) 桌面快捷方式 ----
if (-not $NoShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop 'DeepSeek Harness.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnkPath)
    $s.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $s.Arguments = '"' + (Join-Path $InstallDir 'DSH-Launcher.vbs') + '"'
    $s.WorkingDirectory = $InstallDir
    $ico = Join-Path $InstallDir 'DeepSeek-blue.ico'
    if (Test-Path -LiteralPath $ico) { $s.IconLocation = "$ico,0" }
    $s.Description = 'DeepSeek Harness：启动服务并用浏览器独立窗口打开'
    $s.Save()
    Write-Ok "桌面图标已创建：$lnkPath"
}

# ---- 3) 完成 ----
Write-Ok '安装完成！双击桌面的 "DeepSeek Harness" 图标即可使用。'
Write-Host '· 首次启动需要联网下载 DeepSeek Harness，请耐心等待'
Write-Host '· 与模型对话需要配置 DeepSeek API Key（环境变量 DEEPSEEK_API_KEY 或网页模型设置）'
Write-Host '· 排错日志：%TEMP%\DSH-Server.log   ·  卸载：运行安装目录里的 uninstall.ps1'
