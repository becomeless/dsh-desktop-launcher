# DeepSeek Harness Desktop Launcher 🐳

Windows 与 macOS 的桌面启动器 for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)：**双击桌面图标 → 自动启动服务 → 弹出 Chrome 独立应用窗口**，全程没有任何命令行黑窗，关掉窗口即自动停服，再次双击无缝续聊。

![license](https://img.shields.io/badge/license-MIT-blue) ![platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20%C2%B7%20macOS%2011%2B-lightgrey)

## ✨ 特性

- 🖱 **一键启动**：双击桌面图标，自动完成「启动服务 → 等待就绪 → 打开应用窗口」三步
- 🪟 **零黑窗**：对 Windows Terminal / 服务窗口做了无窗口化处理，只出现浏览器窗口
- 🔁 **断点续聊**：会话保存在本机，重启服务后对话无缝继续
- 🧹 **关窗即停**：关闭应用窗口自动结束后台服务，不留残留进程
- 🩺 **友好报错**：缺 Node.js / 启动失败都会弹窗提示，日志写 `%TEMP%\DSH-Server.log`
- 🌐 **双浏览器**：优先 Chrome，没有自动回退 Edge
- 🍎 **macOS 支持**：同名 `.app` 版本，双击即用，逻辑与 Windows 版一致（已真机实测）
- 🚫 无需管理员权限，安装目录 `%LOCALAPPDATA%\DeepSeek-Harness-Launcher`（macOS 为 `~/Library/Application Support/DeepSeek-Harness-Launcher`）

## 🚀 一键安装

**PowerShell（推荐）：**

```powershell
[Net.ServicePointManager]::SecurityProtocol='Tls12'; iex ([System.Text.Encoding]::UTF8.GetString((New-Object Net.WebClient).DownloadData('https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install.ps1')).TrimStart([char]0xFEFF))
```

**CMD：**

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; iex ([System.Text.Encoding]::UTF8.GetString((New-Object Net.WebClient).DownloadData('https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install.ps1')).TrimStart([char]0xFEFF))"
```

没装 Node.js 时，安装脚本会询问是否用 winget 自动安装；不想装也可以手动去 [nodejs.org](https://nodejs.org) 装好后重跑。

**macOS（推荐 Homebrew）：**

```bash
brew tap becomeless/dsh-desktop-launcher
brew install --cask dsh-desktop-launcher
```

或一行脚本安装：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install-macos.sh | bash
```

安装完成后在「应用程序」里双击 **DeepSeek Harness** 即可；想放 Dock 就从 Finder 拖进去。没装 Node.js 时会引导用 Homebrew 自动安装。

> 国内访问 jsDelivr 不稳时，把命令里的 `https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install.ps1` 换成 `https://raw.githubusercontent.com/becomeless/dsh-desktop-launcher/main/install.ps1` 即可（安装脚本内部下载也会自动回退）。

## 📦 手动安装

1. 下载本仓库 zip 并解压
2. 右键 `install.ps1` →「使用 PowerShell 运行」

## 🗑 卸载

运行安装目录里的 `uninstall.ps1`（或 `%LOCALAPPDATA%\DeepSeek-Harness-Launcher\uninstall.ps1`）。不会删除 DSH 的会话数据（`~/.dsh`）。

## 🖱 使用

- 双击桌面 **DeepSeek Harness** 图标 → 等 Chrome 窗口弹出即可
- 关掉窗口 → 后台服务自动退出
- 与模型对话前需要配置 **DeepSeek API Key**，二选一：
  1. 系统环境变量设置 `DEEPSEEK_API_KEY`
  2. 打开页面后在「模型设置」里填写（只保存在本机）

## ⚙️ 配置项

编辑 `%LOCALAPPDATA%\DeepSeek-Harness-Launcher\DSH-Launcher.ps1` 顶部配置区：

| 变量 | 默认 | 说明 |
|---|---|---|
| `$StopServerWhenAppCloses` | `$true` | 关窗后是否自动停服；想常驻后台改成 `$false` |
| `$PreferredBrowser` | `'chrome'` | 首选浏览器，`'chrome'` / `'edge'`，找不到自动回退另一个 |
| `$StartupTimeoutSec` | `180` | 等待服务就绪的超时秒数（首次下载依赖时可放宽） |
| `$ServerWindowStyle` | `'Hidden'` | 服务窗口样式，`Hidden` / `Minimized` |
| `$DshUrl` / `$DshPort` | `http://127.0.0.1:3080` | 服务地址 |

## 🧱 系统要求

- Windows 10 / 11
- macOS 11+
- [Node.js](https://nodejs.org)（提供 npx）
- Chrome 或 Edge（Windows 自带 Edge；macOS 需自行安装其一）
- 网络（首次运行自动下载 DeepSeek Harness）

## ❓ FAQ

**双击没反应？** 看任务栏/通知，或查看日志 `C:\Users\<你>\AppData\Local\Temp\DSH-Server.log`。

**启动报错弹窗？** 弹窗里会带日志尾部内容；常见原因：没装 Node、网络问题、3080 端口被占用。

**怎么更新？** 重新跑一遍安装命令即可（会覆盖安装目录并刷新图标）。

**macOS 能用吗？** 可以，已经社区真机测试通过；遇到问题欢迎提 issue 并附上日志（`$TMPDIR/DSH-Server.log`）。

**和官方 DeepSeek Harness 什么关系？** 本工具只是官方的桌面入口，启动的仍是官方 `npx @deepseek-ai/dsh web`，不修改、不替代官方任何组件。

## 📁 项目结构

```
install.ps1          一键安装（下载 + 创建桌面图标）
install-macos.sh     macOS 一键安装
uninstall.ps1        卸载（Windows）
DSH-Launcher.vbs     无窗口启动入口（快捷方式指向它）
DSH-Launcher.ps1     启动器主逻辑
DSH-Server.ps1       静默后台服务进程
DeepSeek-blue.ico    桌面图标
mac/                 macOS 版素材（启动脚本 / Info.plist / AppIcon.icns）
```

## ⚠️ 商标与免责声明

图标取自 DeepSeek 官网 favicon（品牌蓝 #4D6BFE），商标归 DeepSeek 所有。本项目为社区工具，与 DeepSeek 官方无关；请自备 API Key，遵守 DeepSeek 的服务条款。

## License

[MIT](./LICENSE) © becomeless

---

## English

One-liner install on Windows (PowerShell):

```powershell
[Net.ServicePointManager]::SecurityProtocol='Tls12'; iex ([System.Text.Encoding]::UTF8.GetString((New-Object Net.WebClient).DownloadData('https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install.ps1')).TrimStart([char]0xFEFF))
```

Double-click the desktop icon it creates → DeepSeek Harness starts silently and opens in a Chrome app window. Close the window to stop the server; sessions persist locally and resume next launch. Requires Windows 10/11, Node.js, and a DeepSeek API key (`DEEPSEEK_API_KEY` or the in-app model settings). Uninstall via `uninstall.ps1` in the install directory. Community tool, not affiliated with DeepSeek.

macOS: `brew tap becomeless/dsh-desktop-launcher && brew install --cask dsh-desktop-launcher` — installs a double-clickable `.app` into Applications (community-tested). Script alternative: `curl -fsSL https://cdn.jsdelivr.net/gh/becomeless/dsh-desktop-launcher@main/install-macos.sh | bash`.
