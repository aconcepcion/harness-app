<p align="center"><img src="docs/img/icon-256.png" width="128" alt="Harness.app icon — a whale tail on green"></p>

# Harness.app

**[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的原生 macOS 启动器。运行*你自己*安装的 dsh，在真正的 Mac 窗口里，关窗即停。约 1200 行 Objective-C。没有 Electron，不内置 dsh 副本，没有托盘常驻进程。**

双击 → 启动*你自己安装的* `dsh web` → 在原生窗口中显示官方界面 → 关闭窗口即停止服务。

> 非官方社区项目，与 DeepSeek 无关。`dsh` 是他们的；这只是一个窗口加一个进程管理器。

> ### 🤖 不想读这么多？把你的智能体指过来。
> 如果你在用编程智能体 —— **Claude Code、Codex、OpenCode、Hermes、Grok Bot 等** —— 把下面这段贴给它，然后去泡杯咖啡：
>
> ```
> 请严格按照 https://github.com/aconcepcion/harness-app#for-ai-agents 在这台 Mac 上安装并配置 Harness.app。逐步验证；如果缺少 dsh，用其中给出的准确命令安装；运行起来后告诉我。
> ```
> 它会检查前置条件、在你没有 `dsh` 时（带正确参数）安装它、安装 Harness，并确认已运行。它遵循的是下面的[给 AI 智能体](#给-ai-智能体)一节 —— 为逐字执行而写，每一步都可验证。

[English](README.md) · [Español](README.es.md) · [给 AI 智能体 ↓](#给-ai-智能体) · [安装 ↓](#安装)

## 我为什么做这个

dsh 发布当天我就装了。它很好用，但它是一条终端命令，然后打开一个浏览器标签页。用一小时没问题，用一周就烦：标签页淹没在五十个标签中间，服务在某个你忘掉的终端里一直跑着，你没法像对待其他每天用的应用那样点一下 Dock 图标就打开。

于是我给自己写了一个小小的原生启动器。然后我去看别人做了什么 —— 三天之内出现了*九个*"DeepSeek Harness Desktop"仓库。它们几乎都做了同样的选择：用 Electron 或 Tauri 包一层网页界面，**在应用里内置一份自己的 dsh**，关窗后隐藏到菜单栏托盘，然后给你一个 300–500 MB 的二进制去安装。其中最精致的那个确实做得很好 —— 但它是一个*产品*，有自己的发版节奏、自己的更新服务器、以及一份落后于上游的 dsh。

对于一个每周都在变的工具来说，这是本末倒置。dsh 是开发者预览版，新的 RC 不断落地，而且 dsh 最好的特性之一是**它能修改自己** —— 让它支持一种它还不认识的文件类型，它会把插件装进自己的 profile。一个锁定自带 dsh、或在上面叠一层自定义 profile 的封装，恰恰挡在这条路上。

Harness.app 有意在每一点上选择相反的立场：

| | Harness.app | 常见封装 |
|---|---|---|
| 运行哪个 dsh | **你用 npm 安装的那个。** 上游出新 RC = 一条命令；应用本身无需更新 | 包内锁定的副本；等作者发版 |
| 体积 / 技术栈 | 不到 400 KB 的通用二进制，AppKit + 系统 WebKit，一条 `clang` 命令 | 300–500 MB Electron/Tauri，内置 Chromium 或 Rust 工具链 |
| 信任 | 半小时读完全部代码；`brew` 在*你的*机器上编译 | 陌生人提供的（可能未公证的）二进制 |
| 关闭窗口 | **停止服务**（可选保持运行；无托盘、无常驻） | 隐藏到托盘；服务继续运行 |
| 网络 | localhost + 两个明示、可关闭的版本检查 | 更新服务器，有时还有计数下载端点 |
| dsh 的插件自我修改能力 | 完全不受影响 —— 同一个 `~/.dsh`，同样的 profile，你的登录 shell PATH | 常常叠加一个自定义 profile |

想要带插件市场的托盘应用，用别的 —— 它们擅长那个。想要自己的 dsh 在一个像文档一样行为的原生窗口里，就是这个。

## 为什么这些是好事（如果你不是 Mac 开发者）

- **"运行你自己的 npm dsh"** —— dsh 由 npm（Node 的包管理器）安装。Harness 不带副本，它启动的是你机器上那一份。所以 DeepSeek 发新版时，你敲一条命令就用上了 —— Harness 自己什么都不用发布。你永远不用等中间人。
- **"约 1200 行 Objective-C，没有 Electron"** —— Electron 应用为了画一个窗口要内置一整个 Chrome 浏览器（这就是它们 300–500 MB、吃内存的原因）。Harness 通过 Apple 自家的 AppKit 使用 macOS 内置的浏览器引擎。结果：不到 400 KB 的应用，一秒左右打开，原生手感，而且小到任何好奇的人都能读完*全部*代码 —— 没有任何地方能藏东西。Homebrew 甚至直接在你自己的 Mac 上从源码编译它。
- **"没有托盘、没有常驻"** —— 很多桌面封装在你关窗之后仍留在菜单栏里，服务继续跑。Harness 像一份文档：关掉窗口，它就没了，什么都不剩。（如果你*希望*服务在两次使用之间保持运行，有一个复选框 —— 默认关闭。）
- **"两个明示、可关闭的版本检查"** —— 除了和你自己机器上的 dsh 通信，唯一的网络流量是到 npm 查一次 dsh 版本、到 GitHub 查一次 Harness 版本。两者都在设置里可见、可关闭。没有遥测，没有回传。
- **"绝不限制 dsh"** —— 应用不会插在你和 dsh 的插件系统之间。你的 `~/.dsh`、你的 profile、你的 PATH。dsh 在终端里能做的一切，在 Harness 里同样能做。

## 安装

**Homebrew（本地编译约 2 秒，无 Gatekeeper 提示）：**
```sh
brew install aconcepcion/tap/harness-app
cp -R "$(brew --prefix)/opt/harness-app/Harness.app" /Applications/
```
**或从源码：**
```sh
git clone https://github.com/aconcepcion/harness-app && cd harness-app && make install
```
要求：macOS 13+、Xcode Command Line Tools（`xcode-select --install`），以及通过 npm 安装的 `dsh` —— **或者不装也行**：找不到 dsh 时，Harness 会显示准确的安装命令并替你打开 Terminal。

## 首次运行

1. 打开 Harness。它通过你的登录 shell 查找 `dsh`（Homebrew、nvm、volta、fnm 都可以）。
2. 如果 dsh 缺失、Node 版本不对、或 dsh 的 shell 工具损坏（见"坑"），它会准确告诉你该运行什么 —— 在 Terminal 里可见地运行，没有任何隐藏操作。
3. 官方 dsh 网页界面加载。照常在 Settings → Models 输入 API 密钥。
4. 关闭窗口：它启动的服务随之停止。（如果想让服务留着，打开 **Server ▸ Keep Server Running After Close**；下次启动会立即接管。）

## 给 AI 智能体

如果你是一个 AI 智能体（Claude Code、Codex、Cursor、Copilot、Hermes、甚至 dsh 本身……），被要求在 Mac 上安装或操作 Harness.app，请逐字执行本节。每一步都有可验证的结果。

**前置条件（检查，不要假设）**
```sh
sw_vers -productVersion            # 需要 13.0 或更新
xcode-select -p                    # 必须输出路径；否则：xcode-select --install
which brew                         # 可选；有它就能一行安装
which dsh && dsh --version         # 可选；缺失时 Harness 会引导用户
node --version                     # dsh 需要 ^22.19.0 || >=24.0.0（23.x 不支持）
```

**安装（二选一）**
```sh
# A. Homebrew tap —— 本地编译，无 Gatekeeper 提示
brew install aconcepcion/tap/harness-app && cp -R "$(brew --prefix)/opt/harness-app/Harness.app" /Applications/
# B. 从源码
git clone https://github.com/aconcepcion/harness-app ~/harness-app && make -C ~/harness-app install
```

**验证**
```sh
/Applications/Harness.app/Contents/MacOS/Harness --version      # 输出 3.0.0
/Applications/Harness.app/Contents/MacOS/Harness --check-env     # 退出码 0 = 找到 dsh；1 = 缺失（报告说明原因）
open -a Harness                                                  # 启动；约 5 秒内界面在 http://127.0.0.1:3080
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/  # 就绪时为 200
```

**如果 `--check-env` 报告 `dsh: not found`，安装 dsh（就是这条命令；npm ≥ 11 下 `--allow-scripts` 部分是必需的）：**
```sh
npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest
```
如果报告 `node-pty: BROKEN`，运行同一条命令（它会修复缺失的 macOS 预编译文件）。

**配置（全部可选；在 Server ▸ Restart Server 或下次启动时生效）**
```sh
defaults write com.arnoldoconcepcion.harness-app Port -int 3080
defaults write com.arnoldoconcepcion.harness-app Workspace "$HOME/projects"
defaults write com.arnoldoconcepcion.harness-app KeepServerRunning -bool NO
defaults write com.arnoldoconcepcion.harness-app CheckForDshUpdates -bool YES
defaults write com.arnoldoconcepcion.harness-app CheckForAppUpdates -bool YES
open -a Harness "$HOME/projects"        # 或：带工作目录启动
```

**运行 / 诊断**
- 日志：`~/Library/Logs/Harness.app/harness-app.log`（Harness 自身的行以 `[harness-app …]` 开头，其后是 dsh 的输出）。
- 退出 = `osascript -e 'quit app "Harness"'` 或向 `Harness` 进程发 SIGTERM；除非 `KeepServerRunning` 为 YES，否则它启动的 dsh 服务随之停止。
- Harness 绝不修改 `~/.dsh`，绝不安装自己的 profile，并把用户的登录 shell 环境（`$SHELL -ilc env`）交给 dsh。dsh 在终端里能做的，在这里都能做。
- 卸载：`rm -rf /Applications/Harness.app; defaults delete com.arnoldoconcepcion.harness-app`（若通过 tap 安装则再 `brew uninstall harness-app`）。dsh 本身不受影响。

参与开发的智能体：构建、测试与代码约定见 [`AGENTS.md`](AGENTS.md)。

## 它实际做了什么

- **接管或启动。** 端口上已经有服务在响应（比如你在终端里启动的 `dsh web`），Harness 就接管它，绝不杀掉。否则在你的工作目录中启动 `dsh web --port <Port>`，独立进程组，日志写到 `~/Library/Logs/Harness.app/`。
- **就绪 = HTTP 200**，而不是"端口开了"。界面真正可用之前显示占位页。
- **停止 = 向进程组发 SIGTERM → 5 秒 → SIGKILL。** 不会留下孤儿 `node-pty` shell 或 `sandbox-exec` 子进程。
- **崩溃策略。** dsh 退出则自动重启一次；一分钟内再次退出，弹出带日志尾部的错误面板 —— 绝不出现空白窗口。
- **导航守卫。** 非 `127.0.0.1` 的链接一律在默认浏览器中打开。
- **Dock 拖放。** 把文件夹拖到图标上（或 `open -a Harness ~/project`）即以其为工作目录。
- **Profile。** Server ▸ Profile 列出 `~/.dsh/profiles/`；切换会重启服务。Harness 绝不注入自己的 profile。
- **Update dsh… / Repair Shell Tools…** 打开 Terminal 运行下面这条准确的命令。Harness 无法得知 Terminal 何时完成，所以只会提醒你：Server ▸ Restart Server。

## 更新 dsh

```sh
npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest
```
就这么简单：dsh 归 npm 管，不归我们管。Harness 启动时查询 npm，有新版时在窗口副标题显示"dsh x.y.z available"。你的 `~/.dsh` profile 与插件绝不会被触碰（新 RC 需要时自行 `dsh plugin update`）。

## 设置

Cmd-, 或 `defaults write com.arnoldoconcepcion.harness-app <Key> <value>`：

| 键 | 默认 | 含义 |
|---|---|---|
| `Port` | `3080` | 接管 / 启动所用端口 |
| `Workspace` | `$HOME` | 启动 `dsh web` 的工作目录 |
| `Profile` | `web` | `web` 用 `dsh web`，其他用 `dsh --profile <name>` |
| `DshPath` | （自动） | 覆盖登录 shell PATH 查找 |
| `KeepServerRunning` | `NO` | 关窗后保留服务 |
| `CheckForDshUpdates` | `YES` | 启动时 `npm view @deepseek-ai/dsh version` |
| `CheckForAppUpdates` | `YES` | 启动时查询 GitHub 最新 release |

端口 / 工作目录 / profile / dsh 路径在 **Server ▸ Restart Server** 时生效。

## 隐私与网络

Harness 只与三处通信：`127.0.0.1`（dsh）、通过 `npm view` 访问 `registry.npmjs.org`（dsh 更新检查）、`api.github.com`（自身更新检查）。两项检查在设置中可见并可关闭。它在启动时捕获一次你的登录 shell 环境（`$SHELL -ilc env`，并设置 `HA_ENV_CAPTURE=1` 以便你的 rc 文件跳过耗时操作），然后把该环境交给 dsh —— 不会发送到任何地方。

## 这个应用知道的坑

- **npm ≥ 11 默认跳过安装脚本**，所以裸 `npm install -g @deepseek-ai/dsh` 会让 node-pty 缺少 macOS 预编译文件 → dsh 的 shell/PTY 工具悄悄失效。因此上面每条命令都带 `--allow-scripts=…`。Harness 能检测该损坏状态（`node_modules/node-pty/prebuilds/darwin-<arch>/` 缺失）并提供修复。
- **Node 23.x 落在 dsh `engines` 的排除区间**（`^22.19.0 || >=24.0.0`）。Node 版本不受支持时 Harness 会告诉你。
- **dsh 仍是开发者预览版**（rc.x），RC 之间可能有破坏性变更。这正是 Harness 不锁定版本的原因 —— 何时更新由你决定。

## 构建与测试

```sh
make            # 在 build/ 生成通用二进制 Harness.app
make test       # 单元测试（环境发现、semver、用假 dsh 测服务生命周期）
make smoke      # 端到端：冷启动、接管、保持运行、SIGKILL 升级
make install    # 复制到 /Applications（ad-hoc 签名）
```
只需要 Command Line Tools。有意不提供公证下载：本地编译的应用没有隔离标记，而一个 400 KB 的启动器也不值得让你去信任一个二进制。

## 路线图 / 非目标

- 可能的 v4：面向任意本地网页工具（Open WebUI、ComfyUI……）的通用模式 —— 配置已经是命令/端口/名称驱动。
- 不计划：托盘图标、内置 Node、Windows/Linux、自动下载更新。

## 许可

Harness.app 以 **MIT 许可证**发布 —— 现存最宽松的开源许可证之一，也是 Homebrew、GitHub 和大多数公司都已经熟悉如何处理的一种。用大白话说：

- **你可以**出于任何目的（商业或非商业）、无论是否修改，使用、复制、修改、合并、发布、分发、再授权和出售本软件的副本，无需征求许可。
- **你必须**在分发的任何副本或实质部分中保留版权声明和许可证文本。这是唯一的条件。
- **不提供保证。** 软件按"原样"提供；作者不对使用它所导致的任何后果负责。

完整文本见 [`LICENSE`](LICENSE)。贡献以同一许可证接收 —— 提交 pull request 即表示你同意你的贡献与其余部分一样采用 MIT 许可。

Harness.app 没有第三方依赖：它只链接 Apple 的系统框架（AppKit、WebKit、Foundation），因此没有需要转载的第三方声明。

**商标。** "DeepSeek" 及 DeepSeek 鲸鱼标志是 DeepSeek 的商标。本项目与其无关、未获其背书，也未使用二者；这里的 "Harness" 指软件类别，而非任何 DeepSeek 产品。`dsh` 是 DeepSeek 的软件，以其自身的许可证发布（撰写本文时为 MIT），并不随本应用分发。

© 2026 Arnoldo Concepcion。
