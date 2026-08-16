# Harness.app

**[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的原生 macOS 启动器 —— 约 700 行 Objective-C，没有 Electron，不内置 dsh 副本，没有托盘常驻进程。**

双击 → 启动*你自己安装的* `dsh web` → 在原生窗口中显示官方界面 → 关闭窗口即停止服务。

> 非官方社区项目，与 DeepSeek 无关。`dsh` 是他们的；这只是一个窗口加一个进程管理器。

[English](README.md)

## 为什么做这个

dsh 发布几天内出现了九个"桌面版"封装 —— Electron/Tauri 应用，**内置各自锁定版本的 dsh**，关窗后隐藏到托盘，并要求你把 API 密钥和 shell 权限交给一个 300–500 MB 的第三方二进制。Harness.app 在每一点上都选择了相反的立场：

| | Harness.app | 常见封装 |
|---|---|---|
| 运行哪个 dsh | **你用 npm 安装的那个。** 上游出新 RC = 一条命令；应用本身无需更新 | 包内锁定的副本；等作者发版 |
| 体积 / 技术栈 | 约 100 KB 二进制，AppKit + 系统 WebKit，一条 `clang` 命令 | 300–500 MB Electron/Tauri，内置 Chromium 或 Rust 工具链 |
| 信任 | 五分钟读完全部代码；`brew` 在*你的*机器上编译 | 陌生人提供的（可能未公证的）二进制 |
| 关闭窗口 | **停止服务**（可选保持运行；无托盘、无常驻） | 隐藏到托盘；服务继续运行 |
| 网络 | localhost + 两个明示、可关闭的版本检查 | 更新服务器，有时还有计数下载端点 |
| dsh 的插件自我修改能力 | 完全不受影响 —— 同一个 `~/.dsh`，同样的 profile，你的登录 shell PATH | 常常叠加一个自定义 profile |

想要带插件市场的托盘应用，用别的 —— 它们擅长那个。想要自己的 dsh 在一个像文档一样行为的原生窗口里，就是这个。

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
只需要 Command Line Tools。有意不提供公证下载：本地编译的应用没有隔离标记，而一个 100 KB 的启动器也不值得让你去信任一个二进制。

## 路线图 / 非目标

- 可能的 v4：面向任意本地网页工具（Open WebUI、ComfyUI……）的通用模式 —— 配置已经是命令/端口/名称驱动。
- 不计划：托盘图标、内置 Node、Windows/Linux、自动下载更新。

## 许可

MIT © Arnoldo Concepcion。图标为鲸鱼 emoji；DeepSeek 的名称与标志归 DeepSeek 所有。
