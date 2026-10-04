# ABCL 功能补齐路线图（对齐 HMCL）

> 目标：ABCL 不是「HMCL 外观的壳」，而是**鸿蒙上真正的 HMCL 移植版**。
> 本文档给出当前真实完成度、HMCL 功能全清单、以及分阶段补齐计划。
>
> 依据：本地 HMCL 源码树 `C:/xm/.research/HMCL`（966 个 Java 文件，含 HMCLCore）。

---

## 一、当前真实完成度（2026-10-04 实测）

| 模块 | 状态 | 说明 |
|---|---|---|
| HMCL 外观 UI | ✅ 真实 | Material3 `blue.css` 色板、Decorator 外壳、md-list-cell、launch-pane |
| 原版游戏下载安装 | ✅ 真实 | 版本清单→元数据→client.jar→libraries→natives→logging→assets(5147)，SHA-1 全通过 |
| Fabric / Quilt 安装 | ✅ 真实 | 官方 meta API，端到端装成功（fabric-loader-0.19.5-26.3） |
| Forge / NeoForge 安装 | ⚠️ 到 processors | installer.jar 解包+52 库+版本 JSON 全通；processors 需 arm64 真机（模拟器 x86 无法加载 aarch64 libjvm） |
| 版本列表 / 实例列表 | ✅ 真实 | 扫描 versions/，展示加载器与目录 |
| 模组管理（本地） | ✅ 真实（本轮修复） | 读 mods/ 目录、.jar↔.jar.disabled 启停、删除、解析 fabric.mod.json / mods.toml / mcmod.info |
| 模组下载（Modrinth） | ✅ 真实（本轮新增） | 搜索 + 版本筛选 + SHA-1 校验 + 装入 mods/ |
| 下载中心 | ✅ 真实（本轮修复） | 游戏/模组/资源包/光影/整合包 五个 Tab（后三个待接数据源） |
| 账户 | ✅ 真实（离线 + Microsoft OAuth 代码齐） | Microsoft client id 仍是占位符，需注册 Azure 应用 |
| 启动器设置 | 🟡 部分 | 内存/Java 路径/JVM 参数/下载源可改；缺 i18n、主题切换、代理、下载线程 |
| 世界管理 | ❌ 假数据 | `generateMockWorlds()` |
| 整合包 | ❌ 假数据 | `generateMockModpacks()` |
| 资源包 / 光影包 | ❌ 未实现 | 只有 Tab 壳 |
| Java 管理 | 🟡 部分 | 有 JdkManager（内置 JDK 解压），缺多 Java 扫描/下载/选择 |
| 日志查看器 / 崩溃报告 | ❌ 未实现 | Logger 有内存环形缓冲，但没有 UI |
| i18n | ❌ 未实现 | 全中文硬编码 |
| 自动更新 | ❌ 未实现 | |
| 主题 / 个性化 | ❌ 未实现 | |

---

## 二、HMCL 的功能面（来自本地源码）

### 2.1 下载域（`HMCLCore/.../download/`）

| 子包 | 文件数 | 对应功能 |
|---|---|---|
| `game/` | 13 | 原版游戏本体、资源索引、日志配置、版本 JSON 合并 |
| `forge/` | 10 | Forge（含旧版 installer、processor、universal） |
| `liteloader/` | 8 | LiteLoader |
| `java/` | 5 | **自动下载/安装 JDK**（多发行版、多平台） |
| `fabric/` | 4 | Fabric + Fabric API |
| `quilt/` | 4 | Quilt |
| `legacyfabric/` | 4 | Legacy Fabric（1.8~1.13） |
| `neoforge/` | 3 | NeoForge |
| `optifine/` | 2 | OptiFine |
| `cleanroom/` | 2 | Cleanroom |

另：模组/资源包/光影/世界/数据包的远端源（Modrinth / CurseForge）在 `HMCLCore/.../addon/`、
UI 向导在 `HMCL/src/main/java/org/jackhuang/hmcl/ui/download/`（DownloadPage / VersionsPage /
InstallersPage / ModpackPage / RemoteModpackPage / LocalModpackPage / OptionalFilesPage）。

### 2.2 UI 页面清单（`ui/`，29 个实例管理页 + 14 个主页面）

`ui/instances/`（29 个）：GameListPage / GameInstancePage / ModListPage / ResourcePackListPage /
WorldListPage / WorldManagePage / WorldBackupsPage / WorldExportPage / DataPackListPage /
SchematicsPage / AddonUpdatesPage / GameAdvancedListItem / GameListPopupMenu / InstallerListPage …

右键/管理项：启动测试、生成启动脚本、实例设置、重命名、复制、删除、导出整合包、重新下载资源、
模组/资源包/世界/数据包/存档备份。

`ui/main/`：SettingsPage / LauncherSettingsPage / DownloadSettingsPage / JavaManagementPage /
JavaDownloadDialog / JavaInstallPage / JavaRestorePage / PersonalizationPage /
ThemePackManagementPage / AboutPage / HelpPage / FeedbackPage。

`ui/` 顶层：LogWindow、CrashWindow、GameCrashWindow、UpgradeDialog、WebPage、MemoryStatusBar。

---

## 三、分阶段补齐计划

### P0 —— 让「HMCL 有的」最常用的部分真的能用

| # | 任务 | 依赖 | 验收 |
|---|---|---|---|
| P0-1 | 资源包 / 光影包 管理（扫描 resourcepacks/ shaderpacks/，启停、删除、详情） | 纯文件系统 | 页面上能看到真实文件 |
| P0-2 | Modrinth 资源包 / 光影 / 整合包 下载（复用 ModrinthClient） | Modrinth API | 能从下载页装进对应目录 |
| P0-3 | 世界管理真实化（扫描 saves/，读 level.dat 的名称与游戏模式、删除、备份 zip） | 文件系统 + NBT 解析（最小实现） | 列出真实世界 |
| P0-4 | 整合包真实化：本地 zip 导入（解包 → 读 manifest.json / curse manifest → 装到新实例） | zlib + 版本安装链路 | 能导入一个 CurseForge/Modrinth 整合包 |
| P0-5 | 日志查看器（Logger 环形缓冲 → 可滚动页面 + 过滤） | 无 | 能看运行日志 |
| P0-6 | 实例右键菜单补全：复制实例、重命名、打开目录、导出整合包 | 文件系统 | 每项可用 |
| P0-7 | 下载源 / 并发数 / 代理 设置项真正生效 | 无 | 切换 BMCLAPI/官方后下载走对应源 |

### P1 —— 补齐 HMCL 的主力功能

| # | 任务 | 依赖 | 备注 |
|---|---|---|---|
| P1-1 | CurseForge 接入（需 API Key；或先只做 Modrinth） | API Key | 用户需自行申请 |
| P1-2 | Java 管理：扫描设备上所有已解压 JDK、按 MC 版本自动选择、缺 JDK 时按需下载 | JdkManager | 目前只用内置 3 个 |
| P1-3 | 版本隔离（每实例独立 gameDir，HMCL 的「版本隔离」设置） | 文件系统 | 影响 mods/saves 归属 |
| P1-4 | OptiFine / LiteLoader / Cleanroom 安装器 | 各自站点 | OptiFine 有反爬 |
| P1-5 | i18n：简体中文 / English 双语，设置里可切 | 资源文件 | HMCL 有 20+ 语言，先做 2 个 |
| P1-6 | 主题切换（浅色/深色/跟随系统）+ 主题包 | 无 | HmclTheme 已抽出色板，改成可切换 |
| P1-7 | 崩溃报告窗口（捕获 JS/Native 异常 + 一键复制） | 无 | |
| P1-8 | 实例设置页（内存、JVM 参数、窗口尺寸、启动前命令、游戏参数） | 无 | |

### P2 —— 长尾与打磨

- OptiFine / 数据包 / 蓝图（Schematics）管理
- 世界备份与导出（zip）
- 整合包导出
- 模组依赖检查与更新检查
- 皮肤 / 披风预览
- 自动更新（检查 GitHub Release）
- 内存状态栏、下载历史、下载任务面板（HMCL 的 FAB + 任务抽屉）
- 代理与镜像自定义

---

## 四、工程约束（必须记住）

1. **不要用访问器（getter）给 `ForEach` 当数据源** —— ArkUI V1 不做可靠依赖追踪，
   首帧未读到的 @State 变化不会触发重绘（下载列表为空就是这么来的）。
   一律显式维护派生 `@State` 数组。
2. **`ForEach` 的 key 必须包含所有可变字段** —— 原地修改对象后 key 不变，ArkUI 会复用旧节点
   （模组元数据不显示就是这么来的）。
3. **`cryptoFramework.Md.update(DataBlob)` 是异步的**，必须 await，否则哈希随机错。
4. **app 沙箱路径必须用 `context.filesDir` 拼接**，不要硬编码 bundle 路径。
5. **native 模块用 ES import `'libhmcl_native.so'`**，`requireNapi` 返回空对象。
6. 每个大改动都要在模拟器上截屏 + 查 app 日志验证（`/data/app/el2/100/base/com.abcmouren.abcl/haps/entry/files/logs/`）。
