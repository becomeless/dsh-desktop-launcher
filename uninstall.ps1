# =====================================================================
#  DeepSeek Harness Desktop Launcher —— 卸载脚本
#  删除安装目录和桌面快捷方式；不影响 DSH 的会话数据（~/.dsh）。
# =====================================================================

param([switch]$Quiet)

$InstallDir = "$env:LOCALAPPDATA\DeepSeek-Harness-Launcher"
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'DeepSeek Harness.lnk'

if (-not $Quiet) {
    $ans = Read-Host '将删除安装目录和桌面快捷方式（不会删除 DSH 会话数据）。继续？(Y/N)'
    if ($ans -notmatch '^[Yy]') { Write-Host '已取消。'; exit 0 }
}

if (Test-Path -LiteralPath $lnkPath) {
    Remove-Item -LiteralPath $lnkPath -Force
    Write-Host "已删除桌面图标：$lnkPath"
}
if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "已删除安装目录：$InstallDir"
}
Write-Host '卸载完成。DSH 的会话数据（~/.dsh）未受影响。'
