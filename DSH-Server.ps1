# =====================================================================
#  DSH 服务进程 —— 由 DSH-Launcher.ps1 静默启动，一般不用手动运行。
#  可选参数 -Port 指定监听端口（默认 3080），对应 dsh web 的 --port。
#  所有输出写入 %TEMP%\DSH-Server.log，出问题先看这个日志。
#  由启动器自动关闭；想手动停，关掉浏览器应用窗口即可。
# =====================================================================

param([int]$Port = 3080)

# 让工作目录和"手动打开 PowerShell 敲 npx"时保持一致
Set-Location $env:USERPROFILE

$logPath = Join-Path $env:TEMP 'DSH-Server.log'
$failMarker = Join-Path $env:TEMP 'DSH-Server-Exited.tmp'
Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $failMarker -Force -ErrorAction SilentlyContinue

npx --yes @deepseek-ai/dsh web --port $Port *>> $logPath

Set-Content -LiteralPath $failMarker -Value 'exited' -Encoding ASCII
Add-Content -LiteralPath $logPath -Value ("`r`n--- DSH 服务已停止（退出码 " + $LASTEXITCODE + "）---`r`n") -Encoding UTF8
