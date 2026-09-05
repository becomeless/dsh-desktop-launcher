#!/bin/bash
# =====================================================================
#  DeepSeek Harness macOS 启动器（由 install-macos.sh 装进 .app 内）
#  双击 "DeepSeek Harness" 应用 → 启动服务 → 打开 Chrome 应用模式窗口；
#  关闭窗口自动停服；全程无终端窗口（错误用系统弹窗提示）。
#  首选端口被占用时自动换用备用端口；已在候选端口运行的服务会被复用。
#  单实例互斥：启动过程中再双击时，第二个实例只等待复用，不重复启动。
#  "关窗停服"只针对由本启动器管理的服务（通过 $TMPDIR/DSH-Server.pid
#  识别归属；手动启动的服务不会被停掉）。
#  日志：$TMPDIR/DSH-Server.log（上一次运行保留为 .old）
#  新版 dsh web 启用浏览器 token 认证：打开前从日志解析本次进程的
#  启动 token 拼到地址后面（不带 token 访问会返回 401"需要认证"页）。
#  应用窗口用独立浏览器配置目录（~/Library/Application Support/
#  DSH-Launcher/chrome-profile 或 edge-profile）：同 profile 下 --app
#  新进程可能被浏览器的单例机制转交给日常实例后自己退出，独立 profile
#  才能保证窗口真正独立常驻，"关窗停服"和去重看护都依赖这一点；顺带让
#  token 换来的会话 Cookie 不受日常浏览器清 Cookie 影响。同时带上
#  --disable-background-mode：Chrome 的后台模式若被打开，关窗后进程可能
#  不退出，导致关窗看护的 pgrep 永远匹配到、"关窗停服"失效。
#  上述看护/去重的 pgrep 匹配串故意不带 token（token 含 ? 在 ERE 里是
#  量词而非字面量，且带 token 匹配会因两个启动器实例读取时机不同而误判）。
# =====================================================================
set -uo pipefail

PORT=3080
PORT_FALLBACK="8080 18080 18081 30800 33080"   # 首选端口被占用时依次尝试
LOG="${TMPDIR:-/tmp}/DSH-Server.log"
MARKER="${TMPDIR:-/tmp}/DSH-Server-Exited.tmp"
PIDFILE="${TMPDIR:-/tmp}/DSH-Server.pid"
LOCK="${TMPDIR:-/tmp}/DSH-Launcher.lock"
TIMEOUT=600
STOP_ON_CLOSE=1          # 1=关窗自动停服；0=常驻后台

alert() {  # alert <标题> <内容>
  local title="$1" msg="$2"
  msg=$(printf '%s' "$msg" | tr '"' "'" | tr '\n' ' ' | cut -c1-500)
  osascript -e "display alert \"$title\" message \"$msg\"" >/dev/null 2>&1 || true
}

log_tail() { tail -n 10 "$LOG" 2>/dev/null || true; }

launch_token() {  # 新版 dsh web（0.1.2-rc.1 起）的浏览器 token 认证：每个服务
                  # 进程启动时随机生成 token，只打印在日志 "dsh web:" 行里；
                  # 不带 token 访问根路径返回 401（"需要认证"页）。解析不到
                  # 就返回空（此前换过 30 天会话 Cookie 时仍能直接打开）。
  local port="${1:-$PORT}" i tok=""
  for i in 1 2 3; do   # 日志落盘可能略晚于端口就绪，最多重试 3 次
    tok=$(grep -Eo "127\.0\.0\.1:$port/\?token=[A-Za-z0-9_-]+" "$LOG" 2>/dev/null | tail -n 1 | sed -E 's/.*token=//')
    [ -n "$tok" ] && { printf '%s' "$tok"; return 0; }
    [ "$i" -lt 3 ] && sleep 0.5
  done
}

token_valid() {  # 陈旧 token 兜底：服务是手动起的（token 没进启动器日志）或
                  # 日志里混进了旧进程残留的 token 时，带错误 token 反而可能
                  # 连原本能用的会话 Cookie 都绕不过。发一次独立请求验证，
                  # 401 判定为无效；请求本身失败（超时等）不因此丢弃 token。
  local url="$1" code
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null)
  # curl 本身失败（超时/连接被拒等，http_code 为空或 000）不因此丢弃 token
  if [ -z "$code" ] || [ "$code" = "000" ]; then return 0; fi
  [ "$code" != "401" ]
}

port_open() { nc -z 127.0.0.1 "${1:-$PORT}" >/dev/null 2>&1; }

dsh_on_port() {   # 端口上确实是 DeepSeek Harness（而不是别的服务）
  curl -fsS --max-time 3 "http://127.0.0.1:${1:-$PORT}/" 2>/dev/null | grep -qi 'DeepSeek Harness' && return 0
  # 页面文案改版时的兜底：监听进程的命令行属于 dsh 也算
  lsof -nP -iTCP:"${1:-$PORT}" -sTCP:LISTEN -t 2>/dev/null |
    while read -r pid; do ps -p "$pid" -o command= 2>/dev/null; done |
    grep -qi 'deepseek-ai.*dsh'
}

kill_tree() {
  local pid="${1:-}" c
  [ -n "$pid" ] || return 0
  for c in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$c"; done
  kill "$pid" 2>/dev/null || true
}

# ---- 0) 单实例互斥：已有实例在启动/管理服务时，本实例只等待复用 ----
lock_acquired=0
if mkdir "$LOCK" 2>/dev/null; then
  lock_acquired=1
  echo $$ > "$LOCK/pid"
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
else
  lp=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$lp" ] && ! kill -0 "$lp" 2>/dev/null; then
    # 锁是崩溃残留的：持锁进程已死，清理后接管
    rm -rf "$LOCK"
    if mkdir "$LOCK" 2>/dev/null; then
      lock_acquired=1
      echo $$ > "$LOCK/pid"
      trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
    fi
  fi
fi

# ---- 0b) Node.js 检查（只有主实例需要）----
if [ "$lock_acquired" -eq 1 ] && ! command -v npx >/dev/null 2>&1; then
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

if [ "$lock_acquired" -ne 1 ]; then
  # 第二个实例：等主实例把服务拉起来后复用
  deadline=$(( $(date +%s) + TIMEOUT ))
  while [ -z "$chosen" ]; do
    for p in $candidates; do
      if port_open "$p" && dsh_on_port "$p"; then chosen="$p"; break; fi
    done
    [ -n "$chosen" ] && break
    if [ "$(date +%s)" -ge "$deadline" ]; then
      alert "另一个启动器正在启动服务" "等待超时（${TIMEOUT}s），请稍后再双击一次。"
      exit 1
    fi
    sleep 1
  done
fi

# 1b) 主实例：在第一个空闲端口上启动；起不来就试下一个
if [ "$lock_acquired" -eq 1 ] && [ -z "$chosen" ]; then
  # 之前超时被保留的服务可能仍在启动中（pid 文件有效）→ 先等它
  op=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$op" ] && kill -0 "$op" 2>/dev/null && ps -p "$op" -o command= 2>/dev/null | grep -qi 'deepseek-ai.*dsh'; then
    deadline=$(( $(date +%s) + TIMEOUT ))
    while [ -z "$chosen" ]; do
      for p in $candidates; do
        if port_open "$p" && dsh_on_port "$p"; then chosen="$p"; break; fi
      done
      [ -n "$chosen" ] && break
      kill -0 "$op" 2>/dev/null || break
      if [ "$(date +%s)" -ge "$deadline" ]; then
        alert "后台服务仍在启动" "等待超时（${TIMEOUT}s），请稍后再双击一次。"
        exit 1
      fi
      sleep 1
    done
  fi
fi

if [ "$lock_acquired" -eq 1 ] && [ -z "$chosen" ]; then
  started=1
  rm -f "$MARKER"
  [ -f "$LOG" ] && mv -f "$LOG" "$LOG.old" 2>/dev/null || true
  deadline=$(( $(date +%s) + TIMEOUT ))
  for p in $candidates; do
    port_open "$p" && continue
    chosen="$p"
    rm -f "$MARKER"
    # --no-open：新版 dsh web 默认自动打开系统默认浏览器，与启动器
    # 用 --app 打开的独立窗口重复；关掉它，只保留应用窗口。
    nohup npx --yes @deepseek-ai/dsh web --no-open --port "$p" >>"$LOG" 2>&1 &
    server_pid=$!
    echo "$server_pid" > "$PIDFILE"
    ok=0
    while :; do
      if port_open "$p"; then ok=1; break; fi
      if [ -f "$MARKER" ] || ! kill -0 "$server_pid" 2>/dev/null; then
        last_log="$(log_tail)"
        break
      fi
      if [ "$(date +%s)" -ge "$deadline" ]; then
        # 超时不停服：可能正在下载最新版，留它继续启动（pid 文件标记归属）
        alert "等待服务超时（${TIMEOUT}s）" "服务仍在后台继续启动（可能在下载最新版），稍后再双击一次即可直接打开。日志：$(log_tail)"
        exit 1
      fi
      sleep 0.8
    done
    [ "$ok" -eq 1 ] && break
    kill_tree "$server_pid"
    rm -f "$PIDFILE"
    server_pid=""
    chosen=""    # 失败端口不可复用，重置后试下一个
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
# 新版 dsh web 的浏览器认证：拼上本次服务进程的启动 token 换取会话 Cookie。
# 注意 URL（不带 token）单独留着给下面的 pgrep 去重/看护用——带 token 的话
# ?  在 ERE 里是量词不是字面量，且主/次实例读到 token 的时机不保证一致，
# 用带 token 的串做匹配会引入误判（重复开窗）。实际打开浏览器用 OPEN_URL。
TOKEN=$(launch_token "$chosen")
# 陈旧 token 兜底：服务是手动起的（token 没进日志）或日志里混进旧进程
# 残留的 token 时，带错误 token 反而可能连原本能用的会话 Cookie 都绕不过
[ -n "$TOKEN" ] && ! token_valid "$URL/?token=$TOKEN" && TOKEN=""
OPEN_URL="$URL"
[ -n "$TOKEN" ] && OPEN_URL="$URL/?token=$TOKEN"

# pgrep -f 按正则匹配整条命令行；只锚定协议+IP+端口，且用 [^0-9] 卡住
# 端口号尾部（避免 3080 误匹配到 30800 这类以它为前缀的端口）。macOS
# 的 BSD 正则不支持 \b，所以用字符类模拟"数字边界"。
PORT_PAT="http://127\\.0\\.0\\.1:${chosen}([^0-9]|\$)"

# 已有应用窗口（如主实例刚打开）时，第二个实例直接退出，不重复开窗
if [ "$lock_acquired" -ne 1 ] && pgrep -f -- "--app=$PORT_PAT" >/dev/null 2>&1; then
  exit 0
fi

# 服务归属：复用场景下读 pid 文件判断是否由本启动器管理
OWNED_PID=""
if [ "$started" -eq 1 ] && [ -n "$server_pid" ]; then
  OWNED_PID="$server_pid"
else
  op=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$op" ] && kill -0 "$op" 2>/dev/null && ps -p "$op" -o command= 2>/dev/null | grep -qi 'deepseek-ai.*dsh'; then
    OWNED_PID="$op"
  fi
fi

# ---- 2) 用应用模式打开（优先 Chrome，其次 Edge）----
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
EDGE="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
BROWSER=""
for b in "$CHROME" "$EDGE"; do
  if [[ -x "$b" ]]; then BROWSER="$b"; break; fi
done
if [[ -z "$BROWSER" ]]; then
  open "$OPEN_URL"   # 没有 Chrome/Edge 就用默认浏览器打开
  # 默认浏览器无法感知关窗，服务会保持运行（已知取舍）
  exit 0
fi
APPNAME=""
PROFILE_DIR=""
case "$BROWSER" in
  *"Google Chrome"*) APPNAME="Google Chrome"; PROFILE_DIR="$HOME/Library/Application Support/DSH-Launcher/chrome-profile" ;;
  *"Microsoft Edge"*) APPNAME="Microsoft Edge"; PROFILE_DIR="$HOME/Library/Application Support/DSH-Launcher/edge-profile" ;;
esac
# 独立浏览器配置目录：同 profile 下 --app 新进程可能被 Chrome 的
# ProcessSingleton 转交给已在运行的日常实例后自己退出，导致 pgrep 看护
# 落空、关窗停服失效；独立 profile 才能保证 --app 进程真正独立常驻，
# 同时让 token 换来的 30 天会话 Cookie 不受日常浏览器清 Cookie 影响。
mkdir -p "$PROFILE_DIR"
open -na "$APPNAME" --args --app="$OPEN_URL" --user-data-dir="$PROFILE_DIR" --no-first-run --disable-background-mode
sleep 3
if ! pgrep -f -- "--app=$PORT_PAT" >/dev/null 2>&1; then
  open "$OPEN_URL"   # 应用窗口没起来（如被拦截），退回默认浏览器
  exit 0
fi

# ---- 3) 应用窗口关闭后，停掉由本启动器管理的服务 ----
if [[ -n "$OWNED_PID" && $STOP_ON_CLOSE -eq 1 ]]; then
  while pgrep -f -- "--app=$PORT_PAT" >/dev/null 2>&1; do
    sleep 2
  done
  sleep 1
  kill_tree "$OWNED_PID"
  rm -f "$PIDFILE"
  # 兜底：进程树没杀干净时，直接关掉监听当前端口的进程
  if port_open "$chosen"; then
    lsof -ti tcp:"$chosen" 2>/dev/null | xargs kill 2>/dev/null || true
  fi
fi
