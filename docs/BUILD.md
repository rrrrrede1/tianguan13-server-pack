# 构建说明

本文面向维护者，说明发布包是如何产生的。玩家只需阅读根目录的 [README](../README.md)。

这个仓库不包含游戏源码，只保存打包脚本与启动器。每次构建都从源码仓库拉取指定的 commit，编译、组装、启动验证，然后打包发布。

---

## 一、触发方式

| 方式 | 结果 |
|---|---|
| 同步节点 `repository_dispatch`（`event_type` 为 `source-updated`，payload 携带完整 sha） | 构建并发布 `server-<短sha>` 版本 |
| Actions 手动运行，`ref` 填分支 / tag / 完整或短 sha，`release_tag` 留空 | 仅上传 Artifact，不发布版本 |
| Actions 手动运行并填写 `release_tag` | 构建并发布到指定 tag |
| 向本仓库推送 `server-*` 形式的 tag | 构建并发布，源码 ref 取 `main` |

手动运行且不填 `release_tag` 时不会产生版本记录，适合验证改动。

手动运行时另有一个 `debug_lobby` 选项，默认关闭。开启后会在构建期向大厅代码注入诊断日志，并将生成的大厅页面写入 `data/tg_lobby_debug.html`，用于排查大厅界面的显示问题。

---

## 二、上游同步

### 2.1 同步节点

构建不使用 GitHub 的 `schedule` 定时触发。该机制在当前网络环境下未能稳定生效，因此上游变更由一台独立的同步节点探测。

同步节点（下称 CT124）是维护者自建的内网 LXC 容器，运行在 Proxmox 宿主机上，Debian 12，1 核 / 512 MB，由 DHCP 分配地址，不对外提供任何入站服务。它属于维护者的私人基础设施，与本项目相互独立，其他部署方无需具备。

### 2.2 每轮执行的动作

容器内以 root crontab 每 10 分钟调度一次 `tianguan-sync.sh`，调度器提供文件锁与运行日志。每轮依次执行：

1. **读取上游最新提交**：优先请求 `api.github.com`，公开的 atom feed 作为兜底。该网络环境下 `github.com` 的连接不稳定，而 API 端点正常。
2. **同步 fork**：若与记录的 `last-upstream-sha` 不一致，调用 `merge-upstream` 使 fork 快进到上游，效果等同于网页端的 Sync fork。fork 因此长期与上游保持一致。
3. **触发构建**：若与记录的 `last-dispatched-sha` 不一致，向本仓库发送 `repository_dispatch`，事件类型为 `source-updated`，payload 携带完整的 40 位 sha。工作流据此检出对应提交。

### 2.3 状态与重试

两个 sha 分别记录在 `last-upstream-sha` 与 `last-dispatched-sha` 中：

- 派发失败时不写入 `last-dispatched-sha`，下一轮自动重试
- 派发成功后两者一致，不会重复触发构建
- 同步冲突（HTTP 409）同样不记录状态，下一轮重试；日志中会注明该情况需要人工介入一次

### 2.4 凭据

同步节点使用一个 fine-grained token，仅存放于容器内 `/root/.config/tianguan-sync/token`（`0600`，root 所有），有效期 90 天。所需权限为两个仓库的 `Contents: write`：更新 fork 与发送 `repository_dispatch` 均依赖该权限。宿主机其他目录不保存任何凭据。

### 2.5 脚本

`scripts/tianguan-sync.sh` 即上述同步脚本的实现，随仓库保留，便于复刻同一套自动化流程。脚本中的仓库地址、状态目录与凭据路径均可由环境变量覆盖，默认值为当前部署所使用的取值。

该脚本不参与构建，也不会进入发布包。不具备同步节点时，通过 Actions 手动运行或自行实现第 2、3 步即可完成同样的触发。

---

## 三、构建流程

| 步骤 | 说明 |
|---|---|
| 解析源码 ref | `actions/checkout` 不接受短 sha，先经 API 补全为完整 sha |
| 检出源码 | `fetch-depth: 1`。仓库历史约 3.5 GB，全量拉取不现实 |
| 读取工具链版本 | BYOND 与 Bun 的版本取自 `dependencies.sh`，避免硬编码在版本升级后失效 |
| 获取 BYOND | 带缓存，并对 byond.com 的限流做重试 |
| 准备 x86 VC++ 运行库 | 安装器可能返回 1638（已存在更新版本），因此还需从 `SysWOW64` 与 Visual Studio 的 `VC\Redist` 目录中定位所需 DLL |
| 构建 tgui 与 tgfont | 直接执行构建脚本，跳过 `biome-install`。该步骤只服务于代码检查，却是 tgui 目标的硬依赖，且曾因压缩包损坏导致构建中断 |
| 应用大厅补丁 | 见第四章 |
| 编译 DM | 通过 `tools/build/build.ts dm` 驱动，内部完成图标切割、行为树生成与带 `-DCBT` 的编译。直接调用 `dm.exe` 会遗漏前置步骤 |
| 组装运行目录 | 执行 `tools/deploy.sh`，生成官方最小运行清单 |
| 补入运行库 | 将 VC++ 运行库与 DirectX 9 的 `d3dx9_43.dll`、`D3DCompiler_43.dll` 放入 `byond\bin`，详见第五章 |
| 补入运行时资源 | 见第五章 |
| 审计磁盘资源 | 扫描源码中全部 `file("...")` 字面路径，与产物逐一比对，缺失则中断构建 |
| 启动验证 | 实际启动服务器，直至出现 `Initializations complete`，未通过则不产出发布包 |
| 打包与校验 | 生成运行包、源码包与 `SHA256SUMS.txt` |
| 上传与发布 | Artifact 每次上传；版本发布依触发方式决定 |

---

## 四、大厅界面

上游的 `tgstation.dme` 编译了三份标题界面实现，且定义了同名的过程，后编译者覆盖先编译者：

```
modular_skyrat/modules/title_screen/...          天关定制大厅，564 行
modular_zubbers/.../title_screen_subsystem.dm
modular_zzplurt/.../new_player/title_screen_html.dm   最后编译
```

`modular_zzplurt` 中的这份实现仅五行，重新定义了 `get_title_html()`，会整段覆盖天关大厅的界面代码；其中的 `..()` 只能解析到父类型 `/mob`，该类型并无此过程，于是返回空值，大厅页面因此渲染为空白。编译器对此不产生任何警告，构建仍报告 `0 errors`。

`scripts/patch-lobby.ps1` 在编译前修改工作区内的 `src/`，不涉及源码仓库：

1. 将 `modular_zzplurt` 中的定义更名为 `tg_lobby_suppressed()`，保留其"启动阶段或载入画面显示期间不展示大厅"的原意，并在天关版 `get_title_html()` 开头调用该判断
2. 移除侧栏展示图。天关仓库中没有横幅尺寸的素材，仅有一枚 32×32 的标志，原逻辑会回落到 SPLURT 的加载图
3. 主菜单背景改为纯色黑，替代原先使用的 SPLURT 背景图

脚本可重复执行，第二次运行会跳过已完成的部分，并在结束时自检改动结果。

---

## 五、运行时资源

`tools/deploy.sh` 生成的是最小运行清单，覆盖编译产物、地图、图标、音效与 tgui 界面。另有一批文件由代码在运行期通过 `file()` 与 `fexists()` 从磁盘读取，需要单独补入：

| 目录 | 缺失后的表现 |
|---|---|
| `html/` | 右上状态面板空白，缺少「状态 / 管理 / IC / OOC」等标签（面板脚本 `statbrowser` 的三份文件位于其中） |
| `modular_tianguan/modules/tg_lobby/{icons,sound}` | 大厅侧栏图标与按钮音效缺失 |
| `modular_skyrat/modules/title_screen/icons` | 大厅载入图缺失 |
| `interface/fonts/`、`modular_zh/modules/i18n/fonts/`、`tgui/packages/tgui-escape-menu/styles/` | 字体与样式缺失 |

构建中的 `Audit runtime disk files` 步骤会扫描源码中所有 `file("...")` 字面路径，凡是源码仓库存在而产物中缺失的，直接判定构建失败。上游新增同类资源时，构建会在该步骤报出，而不是发布一个功能不完整的包。

---

## 六、已知问题与处理

**守护进程在无图形界面的构建机上无法运行**

`dreamdaemon.exe` 为图形界面程序，在无显示环境的构建机上启动后无输出、不写日志，进程长期驻留。同一份产物中的 `dd.exe` 为控制台版本，启动后 23 秒即完成世界加载。启动验证因此使用 `dd.exe`；面向玩家的启动脚本仍使用图形界面版本，以便在桌面环境下查看窗口日志。

**BYOND 安装包不含运行时库**

`dreamdaemon.exe` 依赖 `mfc140u.dll`（x86 VC++ 运行库），`byondwin.dll` 又依赖 `d3d9.dll` 与 `d3dx9_43.dll`（DirectX 9）。任一缺失都会使进程以 `0xC0000135` 立即退出。开发机通常已安装这些运行库，因此该问题只在干净环境中出现。构建时将它们放入 `byond\bin`，运行环境无需另行安装。

**管道提前关闭导致下载失败**

在 `set -o pipefail` 下使用 `curl | grep -m1`，`grep` 命中后立即退出，`curl` 因写入失败返回错误码 23，整步中断。改用 shell 内的正则匹配，不经过管道。

**源码归档路径错误**

`git -C src archive -o <相对路径>` 会先切换到 `src/` 再执行，归档文件被写入该目录，而命令返回成功。现已改用绝对路径，并对产物是否存在做校验。

**运行时文件被占用导致打包失败**

启动验证结束后，服务器仍持有 `tgstation.dyn.rsc` 与日志文件，压缩时报告文件被占用。现在验证脚本会终止进程、等待退出并清理运行时产物，压缩步骤另设三次重试。

**PowerShell 语法兼容性**

`for (...) { } | Tee-Object` 不是合法的管道写法；`? :` 属于 PowerShell 7 语法，在 Windows PowerShell 5.1 下无法解析。

---

## 七、本地复现

```powershell
# 假定源码已检出到 .\src
$env:DM_EXE = "C:\path\to\byond\bin\dm.exe"
bun tools/build/build.ts dm
bash tools/deploy.sh ../out/TianGuan13_Server
./scripts/smoke-test.ps1 -PackageDir out/TianGuan13_Server
```

编译必须带 `-DCBT`，且该参数需位于 `tgstation.dme` 之前，否则编译器会静默忽略，产物中电脑与控制台图标显示为错误占位图。`launcher/build_server.bat` 已按正确顺序编写。

---

## 八、目录结构

```
.github/workflows/package-windows.yml   构建流水线
docs/BUILD.md                           本文
scripts/patch-lobby.ps1                 编译前的大厅补丁
scripts/smoke-test.ps1                  启动验证脚本
scripts/tianguan-sync.sh                上游同步脚本（不参与构建）
launcher/start_server.bat               启动服务器并跟踪日志
launcher/stop_server.bat                停止服务器与 BYOND 后台进程
launcher/setup_admin.bat                添加管理员
launcher/build_server.bat               修改源码后重新编译
```
