# 原生 Linux 桌面开发环境配置与踩坑指南

本文档记录在原生物理机 Linux 桌面系统（以 **Linux Mint 22 / Ubuntu 24.04 noble 底座** 为例）上，复刻部署本仓库开发环境、四层 Shell 分层、开发工具链及 AI Agent 基础设施时的关键配置细节与踩坑取证结论。

---

## 零、物理机 Linux 桌面与 WSL2 的环境共性与差异

本仓库原本围绕 **Windows 11 + WSL2** 体系构建。在原生 Linux 桌面（如 Linux Mint 22）上迁移部署时，核心架构体系完全通用，但有若干环境假定发生变化：

1. **四层 Shell 配置分层完全通用**（原件与分层说明在 [`../shell/`](../shell/)）：
   - `~/.zshenv`（轻量非交互入口）
   - `~/.shell_wslfn`（互操作函数定义，内置 `/proc/version` 早退守卫）
   - `~/.shell_common`（环境变量、PATH、代理、输入法、Keyring 的唯一真相来源）
   - `~/.zshrc` / `~/.bashrc`（专属交互配置）
   在非 WSL 的原生 Linux 环境下，`~/.shell_wslfn` 与 `~/.shell_common` 会自动跳过 Windows 路径探测与 `.exe` 桥接，保持环境绝对纯净。
2. **WSL2 虚拟化机制不必部署**：
   - Windows 宿主端的 `%USERPROFILE%\.wslconfig`
   - Linux 侧虚拟化配置文件 `/etc/wsl.conf`
   - Windows 固定盘跨文件系统挂载 `/etc/fstab`（`/mnt/c`、`/mnt/d`、`/mnt/e`）
   - `systemd-binfmt` 与 `/mnt/wsl` 共享守护服务
   原生物理机拥有独立的 ext4 根文件系统与完整的内核命名空间，上述规避 WSL 虚拟化陷阱的组件无需配置。
3. **输入法与图形环境**：
   - 原生桌面直接运行 X11 / Wayland 与系统的 Fcitx / Fcitx5 守护进程，无需 WSLg 桥接与 Weston 窗口规则。

---

## 一、镜像源与工具链配置规范

### 1. 软件源与镜像策略
- **npm / pnpm**：使用 `npmmirror`（`https://registry.npmmirror.com/`），在 `~/.npmrc` 中全局固化。
- **Python (uv / pip)**：使用清华大学 TUNA 镜像源（`https://pypi.tuna.tsinghua.edu.cn/simple`），分别配置于 `~/.config/uv/uv.toml` 与 `~/.config/pip/pip.conf`。
- **Node (nvm)**：使用清华源 release 镜像（`https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/`），由 `~/.shell_common` 导出 `NVM_NODEJS_ORG_MIRROR`。
- **APT 软件包**：使用清华 TUNA 镜像。

### 2. Python 隔离纪律
严格遵循 PEP 668：
- 系统 `/usr/bin/python3` 专属于 OS 与 apt 基础包，严禁使用 `pip` 全局安装或 `--break-system-packages`。
- 业务与日常开发统一通过 `uv python install 3.12` 进行旁路管理。
- 在 `~/.config/uv/.python-version` 中写入 `3.12`，统一使用 `uv run --python 3.12` 执行。

### 3. pnpm 安装规范
- 默认直接通过官方独立脚本 `curl -fsSL https://get.pnpm.io/install.sh | sh -` 安装最新版 pnpm 12 二进制。
- 独立二进制落地于 `$PNPM_HOME/bin/pnpm`（即 `~/.local/share/pnpm/bin/pnpm`）。
- 绝不通过 npm 全局安装，完全保持与 Node 版本的生命周期解耦。

### 4. 终端仿真器与 Shell 交互增强规范
- **终端仿真器**：推荐使用现代化 GPU 加速终端 **Ghostty**，原生完整支持 ANSI OSC 52 剪贴板协议与 Kitty Graphics 行内图像渲染协议。
- **按键解绑与重映射规范**：在 `~/.config/ghostty/config` 中将默认劫持全屏的 `Ctrl+Enter` 解绑透传（`ctrl+enter=unbind`），并将全屏切换改绑为 Linux 通用键（`f11=toggle_fullscreen`）。
- **文件管理器上下文菜单（右键在 Ghostty 中打开）**：在 Nemo 文件管理器中通过 Nemo Action 机制，配置 `open_in_ghostty.nemo_action`（右键选中文件夹）与 `open_in_ghostty_bg.nemo_action`（右键当前目录空白处），实现与桌面文件管理器的无缝右键集成。
- **Shell 插件**：在 Oh-My-Zsh 中启用 `git`、`zsh-autosuggestions`（智能补全）与 `zsh-syntax-highlighting`（实时语法高亮），注意语法高亮插件必须置于插件列表末位。

### 5. 中文输入法体系规范（Fcitx 5 现代化框架）
- **框架选型**：全面采用现代化 **Fcitx 5** 替代老旧 Fcitx 4 与 IBus，确保 GTK 4 原生模块（`fcitx5-frontend-gtk4`）就绪，打通 Ghostty 等现代终端与应用。
- **环境接管**：通过 `im-config -n fcitx5` 接管桌面输入法框架。
- **按键冲突防范**：在 `~/.config/fcitx5/conf/chttrans.conf` 中置空简繁转换热键，避免 `Ctrl+Shift+F` 劫持全局搜索。

---

## 二、新装系统踩坑索引与根因排查

### 2.1 桌面会话下 `chsh` 切换默认 Shell 后重启终端窗口仍为 Bash

#### 症状
执行 `sudo chsh -s $(which zsh) <your-linux-user>` 成功修改系统登录 Shell，核对 `/etc/passwd` 已更新为 `/usr/bin/zsh`。但关闭 GNOME Terminal 窗口再次重新打开时，依然进入原来的 Bash 环境。

#### 根因剖析
Linux 图形桌面会话（X11 / Wayland，由 LightDM / GDM 等 Display Manager 管理）具有**环境变量固化传播机制**与终端**Client/Server 长驻架构**的双重阻隔：
1. **PAM 会话固化**：Display Manager 引导桌面时，读取 `/etc/passwd` 并向整个桌面会话树（包括 X11 根会话、systemd user session、D-Bus 会话总线）固化注入了 `SHELL=/bin/bash`。
2. **GNOME Terminal 守护进程长驻**：GNOME Terminal 并不是一个独立的瞬时进程，其核心是后台长驻的 `/usr/libexec/gnome-terminal-server`。当关闭最后一个终端窗口时，该服务端进程依然在内存中存活，并一直缓存着启动时的 `SHELL=/bin/bash` 环境变量。
3. **重新打开终端窗口只是向长驻 Server 发起 RPC 请求**：Server 派生新 Tab/Window 时，直接使用自身环境中的 `SHELL` 变量，因此不会重新查询 `/etc/passwd`。

#### 解决方案
- **彻底生效路径**：注销当前图形桌面会话（Log Out）并重新登录，或重启计算机。
- **免注销即时生效方案（无需重启）**：
  1. 更新 systemd 与 D-Bus 会话总线环境变量：
     ```bash
     systemctl --user set-environment SHELL=/usr/bin/zsh
     dbus-update-activation-environment --systemd SHELL=/usr/bin/zsh
     ```
  2. 配置 GNOME Terminal 默认 Profile 显式启用 Zsh：
     ```bash
     PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
     gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:${PROFILE_ID}/ use-custom-command true
     gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:${PROFILE_ID}/ custom-command '/usr/bin/zsh'
     gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:${PROFILE_ID}/ login-shell true
     ```
  完成配置后，在终端按 `Ctrl + Shift + T` 或新开窗口即可即时进入 Zsh。

---

### 2.2 Clash Verge 桌面系统代理对 CLI 穿透失效及 ureq socks5h 陷阱

#### 症状
在 Linux 桌面启动 Clash Verge Rev 后，Firefox 等桌面浏览器能够正常访问外网，但原生终端内执行 `curl`、`git clone` 或 `uv` 下载却无法访问；而若在终端强行设置 `ALL_PROXY=socks5h://127.0.0.1:<proxy-port>`，单二进制搜索工具 `bx`（Brave Search CLI）直接崩溃报错：
```
error: io: Connection refused
exit 5
```

#### 根因剖析
1. **桌面系统代理模式 vs TUN 虚拟网卡**：
   Clash Verge 在 Linux 上默认以「系统代理」模式运行，即通过 GSettings 设置 GNOME 桌面网络代理。GUI 浏览器会主动读取桌面配置，而 Linux 原生命令行程序（CLI）与子进程并不监听桌面 GSettings，必须依赖环境变量（`http_proxy`、`https_proxy`）。
2. **Rust `ureq` 对 `socks5h` 协议的不兼容性**：
   `bx` 由 Rust 编写，底层 HTTP 客户端基于 `ureq`。官方构建时未启用 SOCKS 特性，且 `socks5h://` 为 curl 专属协议头，`ureq` 解析该协议头失败后会**静默回退为直接连接（Direct）**，直接连接触发网络阻断返回 Connection Refused。

#### 解决方案
1. **环境变量多层固化**：
   在 `~/.shell_common` 中规范导出 HTTP 代理入口与精确的 `NO_PROXY` 白名单：
   ```sh
   export host_ip="127.0.0.1"
   export proxy_port="<proxy-port>"
   export HTTP_PROXY="http://${host_ip}:${proxy_port}"
   export HTTPS_PROXY="http://${host_ip}:${proxy_port}"
   export http_proxy="http://${host_ip}:${proxy_port}"
   export https_proxy="http://${host_ip}:${proxy_port}"
   export ALL_PROXY="socks5h://${host_ip}:${proxy_port}"
   export all_proxy="socks5h://${host_ip}:${proxy_port}"
   export NO_PROXY="localhost,127.0.0.1,::1,.local"
   export no_proxy="localhost,127.0.0.1,::1,.local"
   ```
2. **`bx` 专用 Wrapper 隔离**：
   在 `~/.local/bin/bx` 构建 Wrapper 拦截器，将真实二进制重命名为 `bx-bin`，在子进程内执行时动态清除 `ALL_PROXY`，使 `ureq` 安全回退走 `HTTPS_PROXY`（详见 `agent/brave-search/bx-cli.md`）。
3. **全局流量无死角覆盖**：
   若需接管原生不读取代理变量的守护程序或复杂容器流量，在 Clash Verge 客户端中显式开启 **TUN Mode**。

---

### 2.3 Linux Mint 22 (noble) 官方软件源结构与 Ubuntu 换源差异

#### 症状
按传统 Ubuntu 24.04 指南修改 `/etc/apt/sources.list.d/ubuntu.sources` 后，执行 `apt update` 报错或发现 Linux Mint 自身的桌面组件（Cinnamon、mintupdate、mintinstall 等）无法获取更新或提示包冲突。

#### 根因剖析
Linux Mint 22 虽然以 Ubuntu 24.04 (noble) 为底层，但其包管理器架构与 Ubuntu 原厂有显著区别：
1. Ubuntu 24.04 官方已全面转向 `deb822` 格式（即 `.sources` 格式）。
2. Linux Mint 22 仍使用传统 one-line-style list 格式，且将源统一收敛在 `/etc/apt/sources.list.d/official-package-repositories.list`。
3. 该文件内明确拆分为两套源：
   - **Mint 主仓库**：`packages.linuxmint.com wilma main upstream import backport`
   - **Ubuntu 上游仓库**：`archive.ubuntu.com/ubuntu noble main restricted universe multiverse` 等
如果仅覆写 Ubuntu 仓库，Mint 仓库未换源仍会受限于海外连接速度；若误删或覆盖该文件，则会导致 Mint 专属桌面套件脱落。

#### 解决方案
直接编辑 `/etc/apt/sources.list.d/official-package-repositories.list`，将其双轨重定向至清华大学 TUNA 镜像：
```list
deb https://mirrors.tuna.tsinghua.edu.cn/linuxmint wilma main upstream import backport

deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble-backports main restricted universe multiverse

deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble-security main restricted universe multiverse
```

---

### 2.4 安装脚本对 Shell rc 文件的追加污染与防线

#### 症状
执行 `pnpm setup` 或 `nvm` 安装脚本后，`~/.bashrc` 尾部被强制注入了若干重复的 `export PNPM_HOME` 与 `PATH` 修改块，破坏了配置的分层单一性。

#### 根因剖析
主流工具安装程序（pnpm、nvm、conda 等）默认假定用户采用「所有配置堆在单个 `.bashrc`」的反模式，因此在执行安装或初始化时会自动探测并向 rc 文件的末尾追加 PATH 与环境变量代码。

#### 解决方案
1. **安装参数防御**：
   - Oh-My-Zsh：使用 `--unattended --keep-zshrc` 参数执行安装脚本，防止其强行覆盖预置的 `~/.zshrc`。
2. **集中收敛至 `~/.shell_common`**：
   - `PNPM_HOME` 与 `NVM_DIR` 统一在 `~/.shell_common` 中通过 `_path_prepend` 幂等注入 PATH。
   - 工具安装完毕后，主动检查并清理 `~/.bashrc` 或 `~/.zshrc` 尾部的自动注入残留，确保配置文件的纯粹性与可维护性。

---

### 2.5 CLI Agent / 终端快捷键粘贴（Ctrl+V / Alt+V）报错 `no supported clipboard tool found`

#### 症状
在 Claude Code、Antigravity 等终端 CLI Agent 中按 `Ctrl+V` 或 `Alt+V` 粘贴剪贴板文本或图片时，终端报出警告：
```text
no supported clipboard tool found (install wl-clipboard or xclip)
```

#### 根因剖析
1. **WSL2 与原生 Linux 剪贴板生态差异**：
   - 在 WSL2 环境下，Linux 默认没有独立的物理显示会话与剪贴板服务，剪贴板由宿主 Windows 管理。本仓库通过 `shell_wslfn` 将 `clip` 桥接至 `/mnt/c/Windows/System32/clip.exe`，或者通过 `powershell.exe Get-Clipboard` 跨界传递。
   - 在原生 Linux 物理机桌面下，不存在 Windows 宿主与任何 `.exe` 桥接。终端进程直接依附于本地 X11 或 Wayland 显示服务（Linux Mint 22 默认使用 X11，`$XDG_SESSION_TYPE` 为 `x11`）。
2. **现代 CLI 工具的剪贴板探测机制**：
   - 现代 CLI Agent（如 Claude Code 内置的富文本/图片粘贴模块）在 Linux 平台下检测系统剪贴板时，硬编码依赖系统级 CLI 工具：X11 下调用 `xclip`（或 `xsel`），Wayland 下调用 `wl-clipboard`（`wl-paste` / `wl-copy`）。
   - Linux 发行版的基础桌面镜像通常不会默认预装这些底层 CLI 工具，导致终端交互层触发按键时探测失败。

#### 解决方案
安装原生剪贴板工具链（同时兼顾 X11 与 Wayland 环境）：
```bash
sudo apt-get install -y xclip xsel wl-clipboard
```
- Linux Mint 22 默认 X11 环境下 `xclip` / `xsel` 负责接管剪贴板读写。
- 补全 `wl-clipboard` 确保未来无论切换至 Wayland 会话还是跨环境运行均能无缝兼容。

> **[!IMPORTANT] 进程生命周期陷阱**：
> 如果 CLI Agent（如 `agy`）在执行 `apt install` 之前就已经在终端中运行，由于 Go 语言底层剪贴板库（如 `atotto/clipboard`）在进程引导的 `init()` 阶段仅探测一次 `exec.LookPath` 并固化在进程内存中，后装的命令无法被当前运行中的进程动态感知，调用 `/copy` 依然会报无可用剪贴板。**必须退出当前会话并重新启动 CLI（例如重启 `agy` 后通过 `/resume` 恢复）**，新进程初始化即可完美调通。

---

### 2.6 CLI `/copy` 命令提示复制成功但系统剪贴板无内容（GNOME Terminal 静默丢弃 OSC 52）

#### 症状
在 Antigravity CLI 等现代终端工具中执行 `/copy` 命令，界面正常显示 `Copied ... to clipboard.`，但在系统外部程序（浏览器、编辑器）中按 `Ctrl+V`，剪贴板依然为空或保持上一次复制的内容。

#### 根因剖析
1. **读写分离与协议脱节**：
   - 终端工具读取剪贴板（如按 `Ctrl+V` 粘贴图片/文本）通常直接调用本地系统的 `xclip` 或 `wl-paste` 进程；
   - 但向系统剪贴板写入（如 `/copy`）为了兼容 SSH 远程跳转等无本地 X11 的场景，通常采用 ANSI **OSC 52** 控制转义码（`\033]52;c;<base64>\007`），请求宿主终端仿真器协助将数据写入宿主系统的剪贴板。
2. **GNOME Terminal (libvte) 长期缺乏 OSC 52 写入支持**：
   - Linux Mint 与 Ubuntu 默认的 GNOME Terminal 底层基于 GNOME 虚拟终端库 `libvte`。
   - VTE 社区长年因安全策略考虑（防止恶意脚本在终端中静默覆盖用户剪贴板）一直未实现 OSC 52 写入协议（Issue #2495 至今未合入）。
   - 当 `agy` 向标准输出发送 OSC 52 转义码时，向 PTY 写字符永远返回成功，因此 CLI 报复制成功；但 GNOME Terminal 遇到未实现的转义序列直接**静默丢弃**。

#### 解决方案
1. **拥抱现代终端仿真器 Ghostty（强烈推荐）**：
   采用 Mitchell Hashimoto 开发的现代化终端 **Ghostty**，原生完整支持 OSC 52 剪贴板读写与 Kitty Graphics 图像协议：
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
   ```
   安装后 Ghostty 自动挂载系统的默认 Zsh 与 Oh-My-Zsh 配置，`/copy` 原生直达系统剪贴板。
2. **GNOME Terminal 兼容方案（CLI_CLIPBOARD_FILE 桥接）**：
   若必须在 GNOME Terminal 中使用，可利用 `agy` 内置的逃逸变量 `export CLI_CLIPBOARD_FILE="$HOME/.cache/agy_clipboard"`，并配合系统 `systemd --user` 路径监听自动将写入内容通过 `xclip` 刷入剪贴板。

---

### 2.7 多设备历史命令迁移冷启动与 Zsh `corrupt history file` 崩溃

#### 症状
为了让新系统的 `zsh-autosuggestions` 获得旧工作机（如台式机 WSL、笔记本）的完整肌肉记忆，直接将各处的 `.bash_history` 与 `.zsh_history` 拷贝或拼接至新系统的 `~/.zsh_history`，启动 Zsh 时报错：
```text
zsh: corrupt history file /home/<user>/.zsh_history
```

#### 根因剖析
1. **截断与空字节（NULL bytes）污染**：
   在 WSL 异常终止、非正常关机或跨文件系统归档传输时，历史文件末尾或特定行常产生连续的 `\x00` 空字节。C 语言底层字符串以 `\0` 为终止符，Zsh 的 `readhistline()` 遇到 `\x00` 解析结构断裂，立即将整个历史文件判定为 Corrupt。
2. **Bash 纯文本与 Zsh 扩展格式冲突**：
   Oh-My-Zsh 默认启用 `setopt extended_history`，要求历史文件符合严格的 `: <timestamp>:0;<command>` 规范；若混入原始未加时间戳的 Bash 行，可能造成解析错乱。

#### 解决方案
在迁移多设备历史时，编写 Python 脚本清洗合并：
1. 过滤全部 `\x00` 字节；
2. 提取并归一化为标准的 `: <timestamp>:0;<command>` 格式；
3. 去重并按时间戳升序排序，确保最近使用的命令在历史末尾，最优先触发 `autosuggestions` 灰色幽灵词推荐；
4. 权限设为 `chmod 600 ~/.zsh_history`。

---

### 2.8 `sudo` 清洗代理环境变量导致 APT 与海外源超时（`env_reset` 陷阱）

#### 症状
终端用户 Shell 中已经正常配置并导出了 `http_proxy` 与 `https_proxy`，普通命令（如 `curl -I https://downloads.typora.io/...`）能正常秒连，Clash Verge 也处于运行中；但一旦执行 `sudo apt update` 或 `sudo apt install`，拉取海外源（如 Typora `downloads.typora.io`、Google Chrome 等）时频繁报连接超时：
```text
Err:9 https://downloads.typora.io/linux ./ InRelease
  Could not connect to downloads.typora.io:443 (31.13.95.18), connection timed out
W: Failed to fetch https://downloads.typora.io/linux/./InRelease Could not connect to downloads.typora.io:443 (...), connection timed out
```

#### 根因剖析
1. **`sudo` 的安全环境变量重置（`env_reset`）**：
   Linux `sudo` 出于最小特权与安全性考虑，默认启用了 `env_reset` 策略。当普通用户切换到 root 权限执行命令时，`sudo` 会自动剥离绝大多数环境变量，其中包括 `http_proxy`、`https_proxy`、`all_proxy` 等。通过 `sudo env | grep -i proxy` 验证可发现输出为空。
2. **APT 缺乏专属代理配置时的直连回退**：
   APT 拥有独立的网络配置（`/etc/apt/apt.conf.d/`）。当 APT 既没有在专用配置中指定代理、外部环境变量又被 `sudo` 剥离为空时，APT 会直接回退为底层 TCP 直连模式（DIRECT），从而撞上 GFW 阻断导致连接超时。

#### 解决方案
- **方案 A（全局推荐：配置 `sudoers` 环境变量白名单）**：
  在 `/etc/sudoers.d/proxy` 中显式指定保留代理环境变量，使所有 `sudo` 命令（`sudo apt`、`sudo git`、`sudo curl` 等）无感继承当前用户的代理设置：
  ```bash
  echo 'Defaults env_keep += "http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY"' | sudo tee /etc/sudoers.d/proxy
  sudo chmod 0440 /etc/sudoers.d/proxy
  sudo visudo -cf /etc/sudoers.d/proxy
  ```
- **方案 B（APT 专属持久化代理配置）**：
  在 `/etc/apt/apt.conf.d/99proxy` 中写入 APT 专属代理（配合 Clash Verge 规则模式，国内清华源命中 DIRECT，海外源命中 PROXY）：
  ```apt
  Acquire::http::Proxy "http://127.0.0.1:7897";
  Acquire::https::Proxy "http://127.0.0.1:7897";
  ```
- **方案 C（单次临时透传）**：
  执行 `sudo -E apt update`（`-E` 参数指示 sudo 临时保留当前环境变量）。

---

### 2.9 Fcitx 5 全新安装后默认 Profile 缺失拼音引擎导致打不出中文

#### 症状
按规范安装 `fcitx5` 与 `fcitx5-chinese-addons` 并通过 `im-config -n fcitx5` 切换重启后，系统后台 `fcitx5 -d` 正常运行，`im-config -m` 也确认当前为 `fcitx5`。但在任何应用程序中按下 `Ctrl+Space` 或 `Shift` 均毫无反应，无法唤出中文输入法候选框。

#### 根因剖析
1. **Fcitx 5 首次初始化的默认组陷阱**：
   Fcitx 5 在首次被用户拉起时，自动在 `~/.config/fcitx5/profile` 生成初始配置。但默认模版**仅将 `keyboard-us`（美式英文键盘）填入了活动输入法组**：
   ```ini
   [Groups/0]
   Name=Default
   Default Layout=us
   DefaultIM=keyboard-us

   [Groups/0/Items/0]
   Name=keyboard-us
   Layout=
   ```
2. 虽然底层 `fcitx5-pinyin` 二进制和词库均已就绪（`fcitx5-remote -m pinyin` 可正确返回），但由于未加入 `[Groups/0/Items]` 激活列表，输入法切换快捷键仅仅在单个英文键盘内部循环，导致输入法看似彻底失效。

#### 解决方案
1. **修改 Profile 或调用 D-Bus 补充拼音引擎**：
   在 `~/.config/fcitx5/profile` 的 `[Groups/0]` 节点下追加拼音条目：
   ```ini
   [Groups/0/Items/1]
   Name=pinyin
   Layout=
   ```
   或直接通过 D-Bus 接口即时写入：
   ```bash
   gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
     --method org.fcitx.Fcitx.Controller1.SetInputMethodGroupInfo "Default" "us" "[('keyboard-us', ''), ('pinyin', '')]"
   gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
     --method org.fcitx.Fcitx.Controller1.Save
   ```
2. **解除 `Ctrl+Shift+F` 简繁转换热键劫持**：
   Fcitx 5 默认将 `Ctrl+Shift+F` 绑定为简繁中文切换，会拦截 VS Code 与终端的全局文件/历史搜索。在 `~/.config/fcitx5/conf/chttrans.conf` 中显式置空解除占用：
   ```ini
   # Translate engine
   Engine=OpenCC

   [Hotkey]
   ```
   随后执行 `gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller --method org.fcitx.Fcitx.Controller1.ReloadAddonConfig "chttrans"` 即可热生效。

---

### 2.10 Ghostty 终端默认 `Ctrl+Enter` 劫持全屏阻断多行输入 / 改绑 `F11` 规范

#### 症状
在 Ghostty 终端中进行日常操作，尤其是在 AI Agent CLI（如 Antigravity / Claude Code）或多行代码编辑中按下 `Ctrl+Enter` 期望插入换行或提交指令时，Ghostty 窗口意外切换为全屏显示。

#### 根因剖析
Ghostty 在 Linux 平台的官方默认快捷键表（通过 `ghostty +list-keybinds` 可核对）中，将 `Ctrl+Enter` 默认绑定为了 `toggle_fullscreen`：
```text
ctrl + enter = toggle_fullscreen
```
这导致任何向子进程发送 `Ctrl+Enter` 控制字符的交互均被终端仿真器截获并转为全屏切换。

#### 解决方案
在 Ghostty 配置文件 `~/.config/ghostty/config` 中，显式将 `ctrl+enter` 解绑透传，并将全屏功能重定向到 Linux 通用的 `F11` 键位：
```ini
keybind = ctrl+enter=unbind
keybind = f11=toggle_fullscreen
```
- **`unbind` 的作用**：移除 Ghostty 自身对按键的拦截，将其原样透传给终端内部运行的 Shell 或 CLI 程序。
- **配置生效**：在已打开的 Ghostty 窗口内按下 **`Ctrl+Shift+,`**（逗号）即可免重启即刻热重载生效，或新开终端窗口生效。

---

### 2.11 Nemo 文件管理器右键添加「Open in Ghostty」上下文菜单规范

#### 场景与诉求
在原生 Linux Mint (Cinnamon) 桌面环境中，系统默认文件管理器为 **Nemo**。默认右键菜单仅有「在终端中打开」（指向系统默认终端）。若日常主力切换为现代化终端 **Ghostty**，需要能在文件管理器中右键任意目录或当前窗口空白处直接拉起 Ghostty 并定位到对应工作目录。

#### 机制剖析：Nemo Actions 扩展模型
Nemo 提供了比传统 `.desktop` 快捷方式更优雅、粒度更细的扩展机制 —— **Nemo Action**（位于 `~/.local/share/nemo/actions/`）。
与 Nautilus 脚本或全局服务相比，Nemo Action 具备以下特征：
1. **右键目标严格区分**：
   - **右键选中的文件夹**：需要设置 `Selection=s`（单选），`Extensions=dir;`（仅对目录生效），并通过变量 `%F` 传入选中对象的绝对路径。
   - **右键当前窗口空白处**：需要设置 `Selection=none`（未选中任何项），`Extensions=any;`，并通过变量 `%P` 传入当前所在父目录的绝对路径。
2. **免重启热生效**：Nemo 会使用 inotify 监听 `~/.local/share/nemo/actions/` 目录，放置 `.nemo_action` 文件后无需重启文件管理器进程，下一次右键即刻加载生效。

#### 解决方案与配置文件

在 `~/.local/share/nemo/actions/` 下部署两个 action 文件（仓库原件见 [`linux-desktop/files/nemo/actions/`](files/nemo/actions/)）：

1. **右键选中文件夹打开**：`~/.local/share/nemo/actions/open_in_ghostty.nemo_action`
   ```ini
   [Nemo Action]
   Name=Open in Ghostty
   Name[zh_CN]=在 Ghostty 中打开
   Comment=Open Ghostty terminal in the selected folder
   Comment[zh_CN]=在选中的文件夹中打开 Ghostty 终端
   Exec=ghostty --working-directory=%F
   Icon-Name=com.mitchellh.ghostty
   Selection=s
   Extensions=dir;
   Quote=double
   ```

2. **右键当前目录空白背景打开**：`~/.local/share/nemo/actions/open_in_ghostty_bg.nemo_action`
   ```ini
   [Nemo Action]
   Name=Open in Ghostty
   Name[zh_CN]=在 Ghostty 中打开
   Comment=Open Ghostty terminal in current folder
   Comment[zh_CN]=在当前文件夹中打开 Ghostty 终端
   Exec=ghostty --working-directory=%P
   Icon-Name=com.mitchellh.ghostty
   Selection=none
   Extensions=any;
   Quote=double
   ```

- **参数细节**：
  - `Exec=ghostty --working-directory=%F`：%F 展开为选中的文件/文件夹路径（由 `Quote=double` 自动引号转义防空格）。
  - `Exec=ghostty --working-directory=%P`：%P 展开为当前窗口打开的主目录路径。
  - `Icon-Name=com.mitchellh.ghostty`：自动关联 Ghostty 官方桌面图标，右键菜单显示美观一致。




