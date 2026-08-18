# =====================================================================
#  DeepSeek Harness Desktop Launcher —— 卸载脚本
#  停止运行中的启动器/服务进程，删除安装目录和桌面快捷方式，
#  清理临时日志；不影响 DSH 的会话数据（~/.dsh）。
# =====================================================================

param([switch]$Quiet)

$InstallDir = "$env:LOCALAPPDATA\DeepSeek-Harness-Launcher"
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'DeepSeek Harness.lnk'

if (-not $Quiet) {
    $ans = Read-Host '将停止运行中的 DSH 服务，并删除安装目录和桌面快捷方式（不会删除 DSH 会话数据）。继续？(Y/N)'
    if ($ans -notmatch '^[Yy]') { Write-Host '已取消。'; exit 0 }
}

# ---- 0) 停止运行中的启动器/服务进程 ----
$targets = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and (
        $_.CommandLine -match 'DSH-(Launcher|Server)\.ps1' -or
        $_.CommandLine -match '@deepseek-ai[/\\]dsh'
    )
}
foreach ($t in $targets) {
    if ($t.ProcessId -eq $PID) { continue }
    cmd.exe /c "taskkill /PID $($t.ProcessId) /T /F >nul 2>&1"
}

if (Test-Path -LiteralPath $lnkPath) {
    Remove-Item -LiteralPath $lnkPath -Force
    Write-Host "已删除桌面图标：$lnkPath"
}
if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "已删除安装目录：$InstallDir"
}

# ---- 3) 清理临时日志/标记（只删本项目的 DSH-Server*，不碰 dsh 自己的数据）----
Get-ChildItem -LiteralPath $env:TEMP -Filter 'DSH-Server*' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host '卸载完成。DSH 的会话数据（~/.dsh）未受影响。'
