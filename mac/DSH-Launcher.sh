#!/bin/bash
# =====================================================================
#  DeepSeek Harness macOS 启动器（由 install-macos.sh 装进 .app 内）
#  双击 "DeepSeek Harness" 应用 → 启动服务 → 打开 Chrome 应用模式窗口；
#  关闭窗口自动停服；全程无终端窗口（错误用系统弹窗提示）。
#  首选端口被占用时自动换用备用端口；已在候选端口运行的服务会被复用。
#  日志：$TMPDIR/DSH-Server.log
# =====================================================================
set -uo pipefail

PORT=3080
PORT_FALLBACK="8080 18080 18081 30800 33080"   # 首选端口被占用时依次尝试
LOG="${TMPDIR:-/tmp}/DSH-Server.log"
MARKER="${TMPDIR:-/tmp}/DSH-Server-Exited.tmp"
TIMEOUT=180
STOP_ON_CLOSE=1          # 1=关窗自动停服；0=常驻后台

alert() {  # alert <标题> <内容>
  local title="$1" msg="$2"
  msg=$(printf '%s' "$msg" | tr '"' "'" | tr '\n' ' ' | cut -c1-500)
  osascript -e "display alert \"$title\" message \"$msg\"" >/dev/null 2>&1 || true
}

log_tail() { tail -n 10 "$LOG" 2>/dev/null || true; }

port_open() { nc -z 127.0.0.1 "${1:-$PORT}" >/dev/null 2>&1; }

dsh_on_port() {   # 端口上确实是 DeepSeek Harness（而不是别的服务）
  curl -fsS --max-time 3 "http://127.0.0.1:${1:-$PORT}/" 2>/dev/null | grep -qi 'DeepSeek Harness'
}

kill_tree() {
  local pid="${1:-}" c
  [ -n "$pid" ] || return 0
  for c in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$c"; done
  kill "$pid" 2>/dev/null || true
}

# ---- 0) Node.js 检查 ----
if ! command -v npx >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    resp=$(osascript -e 'display dialog "未检测到 Node.js。现在用 Homebrew 自动安装 Node.js LTS？" buttons {"取消", "安装"} default button "安装" with title "DeepSeek Harness"' 2>/dev/null || echo "取消")
    if [[ "$resp" == *"安装"* ]]; then
      brew install node
    else
      alert "缺少 Node.js" "请到 https://nodejs.org 安装 Node.js 后重新打开本应用。"
      exit 1
    fi
  else
    alert "缺少 Node.js" "请先安装 Homebrew（https://brew.sh）或 Node.js（https://nodejs.org），然后重新打开本应用。"
    exit 1
  fi
  if ! command -v npx >/dev/null 2>&1; then
    alert "Node.js 未就绪" "安装可能未生效，请重新打开本应用；或手动安装 Node.js 后重试。"
    exit 1
  fi
fi

# ---- 1) 确保服务在运行 ----
candidates="$PORT $PORT_FALLBACK"
chosen=""
started=0
server_pid=""
last_log=""

# 1a) 候选端口上已有 DSH 服务 → 复用，不重复启动
for p in $candidates; do
  if port_open "$p" && dsh_on_port "$p"; then chosen="$p"; break; fi
done

# 1b) 否则在第一个空闲端口上启动；起不来就试下一个
if [ -z "$chosen" ]; then
  started=1
  rm -f "$MARKER" "$LOG"
  deadline=$(( $(date +%s) + TIMEOUT ))
  for p in $candidates; do
    port_open "$p" && continue
    chosen="$p"
    rm -f "$MARKER"
    nohup npx --yes @deepseek-ai/dsh web --port "$p" >>"$LOG" 2>&1 &
    server_pid=$!
    ok=0
    while :; do
      if port_open "$p"; then ok=1; break; fi
      if [ -f "$MARKER" ] || ! kill -0 "$server_pid" 2>/dev/null; then
        last_log="$(log_tail)"
        break
      fi
      if [ "$(date +%s)" -ge "$deadline" ]; then
        alert "等待服务超时（${TIMEOUT}s）" "$(log_tail)"
        exit 1
      fi
      sleep 0.8
    done
    [ "$ok" -eq 1 ] && break
    kill_tree "$server_pid"
    server_pid=""
  done
  if [ -z "$chosen" ]; then
    alert "无法选择端口" "候选端口均被占用：$candidates"
    exit 1
  fi
  if ! port_open "$chosen"; then
    alert "DSH 服务启动失败" "$last_log"
    exit 1
  fi
  sleep 0.4
fi

URL="http://127.0.0.1:$chosen"

# ---- 2) 用应用模式打开（优先 Chrome，其次 Edge）----
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
EDGE="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
BROWSER=""
for b in "$CHROME" "$EDGE"; do
  if [[ -x "$b" ]]; then BROWSER="$b"; break; fi
done
if [[ -z "$BROWSER" ]]; then
  open "$URL"   # 没有 Chrome/Edge 就用默认浏览器打开
  exit 0
fi
APPNAME=""
case "$BROWSER" in
  *"Google Chrome"*) APPNAME="Google Chrome" ;;
  *"Microsoft Edge"*) APPNAME="Microsoft Edge" ;;
esac
open -na "$APPNAME" --args --app="$URL"
sleep 3
if ! pgrep -f -- "--app=$URL" >/dev/null 2>&1; then
  open "$URL"   # 应用窗口没起来（如被拦截），退回默认浏览器
  exit 0
fi

# ---- 3) 应用窗口关闭后，停掉由本启动器创建的服务 ----
if [[ $started -eq 1 && $STOP_ON_CLOSE -eq 1 ]]; then
  while pgrep -f -- "--app=$URL" >/dev/null 2>&1; do
    sleep 2
  done
  sleep 1
  kill_tree "$server_pid"
  # 兜底：进程树没杀干净时，直接关掉监听当前端口的进程
  if port_open "$chosen"; then
    lsof -ti tcp:"$chosen" 2>/dev/null | xargs kill 2>/dev/null || true
  fi
fi
