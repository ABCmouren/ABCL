# HMCL-HarmonyOS 🚀

> **Hello Minecraft! Launcher — 鸿蒙原生版**
>
> 在 HarmonyOS NEXT 上原生运行 Minecraft Java Edition

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform: HarmonyOS NEXT](https://img.shields.io/badge/Platform-HarmonyOS%20NEXT-red.svg)](https://developer.huawei.com)
[![API: 26+](https://img.shields.io/badge/API-26%2B-brightgreen.svg)](https://developer.huawei.com)
[![Build: Hvigor](https://img.shields.io/badge/Build-Hvigor-9cf)](https://developer.huawei.com)

> ⚠️ **免责声明：本项目未经充分测试，仍处于实验性阶段，如遇到问题请在 Issue 反馈。**

---

## 📋 概述

HMCL-HarmonyOS 是 [HMCL](https://github.com/HMCL-dev/HMCL)（Hello Minecraft! Launcher）的鸿蒙原生移植版，基于 [AMCL](https://github.com/LZZLHY/amcl/releases)（纯血鸿蒙原生 Minecraft 启动器）的启动架构。它使用 **ArkTS + ArkUI** 构建 UI，通过 **NAPI C++ 桥接层** 直接加载 `libjvm.so` 创建 JVM 来运行 Minecraft Java Edition。

### 为什么需要这个项目？

HarmonyOS NEXT 是纯血鸿蒙系统，**不内置 JVM**。要在鸿蒙设备上运行 Minecraft Java 版，需要解决：

1. ✅ **JDK 运行时** — 内置 JDK 8/17/21（OHOS 编译版）从 HAP rawfile 中提取
2. ✅ **JVM 创建** — 通过 NAPI C++ 桥接层直接调用 `JNI_CreateJavaVM`
3. ✅ **渲染表面** — 使用 XComponent 提供 `OH_NativeWindow`，LWJGL GLFW shim 绑定渲染
4. ✅ **输入转发** — 触摸/键盘/鼠标事件通过 NAPI → JNI 转发到 LWJGL CallbackBridge
5. ✅ **模组加载器** — 支持 Forge / NeoForge / Fabric / Quilt 自动安装

---

## ✨ 功能特性

### 启动器功能
| 功能 | 状态 |
|------|------|
| 🎮 游戏版本管理 | ✅ 下载/安装/删除 Minecraft 版本 |
| 🔐 账号系统 | ✅ 离线模式、Microsoft OAuth 设备码登录、Authlib-Injector |
| 📦 模组加载器 | ✅ Forge / NeoForge / Fabric / Quilt 一键安装 |
| 📥 资源包管理 | ✅ Asset 自动下载（BMCLAPI 镜像加速） |
| ⚙️ 设置 | ✅ 内存 / JVM 参数 / 游戏目录 / 下载源 / 主题 |
| 🌍 世界管理 | ✅ 浏览/删除存档 |
| 🔧 Mod 管理 | ✅ 扫描/启用/禁用/删除 Mod |
| 💾 设置持久化 | ✅ 使用 `@ohos.data.preferences` 自动保存 |

### 引擎层
| 模块 | 说明 |
|------|------|
| 🧩 **Native Bridge** | `libhmcl_native.so` 通过 NAPI 暴露 `jvmInit`、`mcLaunch` 等接口 |
| 🏗️ **JVM 启动** | 三阶段降级：Native Bridge → Process Launch → Stub |
| 🖼️ **XComponent 渲染** | LWJGL GLFW shim 绑定到 XComponent 表面 |
| ⌨️ **输入桥接** | ArkTS 触摸/鼠标/键盘事件 → NAPI → JNI → LWJGL |
| 🚀 **JIT 支持** | 自动检测 JIT 可用性，不可用时降级到解释器模式 |
| 📦 **JDK 管理** | 内置 JDK 8/17/21，从 rawfile 提取或网络下载 fallback |

---

## 🏗️ 架构设计

### 三层架构

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: ArkTS UI 线程                              │
│                                                     │
│  EntryAbility                                        │
│    ├─ 初始化 PreferencesManager                     │
│    ├─ 初始化 JdkManager / JdkExtractor              │
│    ├─ 初始化 ModLoaderInstaller                     │
│    ├─ 初始化 AssetsManager / NativesManager         │
│    ├─ 初始化 LaunchEngine                           │
│    └─ 加载 UI 页面                                  │
│                                                     │
│  GameAbility                                         │
│    └─ 全屏横屏窗口 → GameView (XComponent)          │
│                                                     │
│  GameView (XComponent)                               │
│    ├─ onSurfaceCreated → registerXComponent()        │
│    └─ launchFromPending() → 触发 JVM 启动            │
└──────────────────────┬──────────────────────────────┘
                       │ NAPI (requireNapi)
                       ▼
┌─────────────────────────────────────────────────────┐
│ Layer 2: Native C++ 桥接层 (libhmcl_native.so)      │
│                                                     │
│  napi_init.cpp    — NAPI 入口，注册所有原生函数      │
│  jvm_launcher.cpp — JNI_CreateJavaVM, AmclLauncher  │
│  elf_loader.cpp   — 自定义 ELF 加载器 (JIT bypass)  │
│  input_bridge.cpp — 输入事件转发到 JNI               │
│  log.cpp          — 日志桥接                         │
└──────────────────────┬──────────────────────────────┘
                       │ JNI / dlopen
                       ▼
┌─────────────────────────────────────────────────────┐
│ Layer 3: JVM 独立线程 (Minecraft 运行环境)           │
│                                                     │
│  libjvm.so (JDK)                                    │
│    ├─ JNI_CreateJavaVM                              │
│    ├─ AmclLauncher.main(configJson)                  │
│    └─ net.minecraft.client.main.Main                 │
│                                                      │
│  LWJGL (HarmonyOS 兼容版)                            │
│    ├─ GLFW shim → XComponent surface                 │
│    ├─ OpenGL ES 渲染                                 │
│    └─ 输入事件回调                                    │
└─────────────────────────────────────────────────────┘
```

### 启动流程

```
用户点击「启动」
    │
    ▼
GameListPage 设置启动参数 → AppStorage('pendingGameLaunch')
    │
    ▼
startAbility(GameAbility) → 全屏横屏窗口
    │
    ▼
GameAbility.onCreate → 转发参数到 AppStorage('gameLaunchParams')
    │
    ▼
GameView (XComponent) 创建渲染表面
    │
    ▼
onSurfaceCreated → surfaceId 注册到 LaunchEngine
    │
    ▼
launchFromPending() → 调用 LaunchEngine.launch()
    │
    ├─ waitForJdkReady() → 等待 JDK 提取完成
    │
    ├─ Native Bridge 可用? → nativeLaunch()
    │   ├─ jvmInit(javaHome) → dlopen libjvm.so
    │   ├─ 构建 classpath + mcArgs + launchConfigJson
    │   └─ mcLaunch(configJson) → JNI_CreateJavaVM → AmclLauncher.main()
    │
    └─ 不可用? → processLaunch() → @ohos.process fallback
                   └─ 否则 → stubLaunch() (日志模式)
```

---

## 📁 项目结构

```
HMCL-HarmonyOS/
├── entry/
│   └── src/
│       └── main/
│           ├── cpp/                          # 原生 C++ 代码
│           │   ├── napi_init.cpp             # NAPI 函数注册入口
│           │   ├── jvm_launcher.cpp/h        # JVM 创建与启动
│           │   ├── elf_loader.cpp/h          # 自定义 ELF 加载器
│           │   ├── input_bridge.cpp/h         # 输入事件桥接
│           │   ├── log.cpp/h                 # 日志工具
│           │   ├── CMakeLists.txt            # 构建配置
│           │   └── include/jni_md.h          # JNI 类型定义
│           ├── ets/                          # ArkTS 源码
│           │   ├── entryability/
│           │   │   └── EntryAbility.ets      # 应用入口：初始化各模块
│           │   ├── gameability/
│           │   │   └── GameAbility.ets       # 游戏渲染窗口
│           │   ├── pages/
│           │   │   ├── game/GameView.ets     # XComponent 渲染表面
│           │   │   ├── main/GameListPage.ets # 游戏列表主页
│           │   │   ├── download/DownloadPage.ets  # 版本下载页
│           │   │   ├── account/AccountPage.ets    # 账号管理页
│           │   │   ├── settings/SettingsPage.ets  # 设置页
│           │   │   ├── mod/ModPage.ets       # Mod 管理页
│           │   │   ├── modpack/ModpackPage.ets    # 整合包页
│           │   │   └── world/WorldPage.ets   # 世界管理页
│           │   ├── core/
│           │   │   ├── launch/
│           │   │   │   ├── LaunchEngine.ets  # 启动引擎（核心）
│           │   │   │   ├── NativeBridge.ets  # NAPI 模块封装
│           │   │   │   ├── JdkManager.ets    # JDK 版本管理
│           │   │   │   ├── JdkExtractor.ets  # rawfile → 沙箱提取
│           │   │   │   ├── NativesManager.ets # .so 原生库管理
│           │   │   │   └── ProcessLauncher.ets # 子进程启动 fallback
│           │   │   ├── game/
│           │   │   │   ├── VersionManager.ets # 版本管理+继承链解析
│           │   │   │   ├── ModLoaderInstaller.ets # Forge/Fabric/Quilt 安装
│           │   │   │   └── AssetsManager.ets # 资源包下载管理
│           │   │   ├── auth/
│           │   │   │   └── AuthService.ets   # 账号认证服务
│           │   │   ├── network/
│           │   │   │   └── HttpClient.ets    # HTTP 客户端
│           │   │   ├── storage/
│           │   │   │   └── PreferencesManager.ets # 设置持久化
│           │   │   ├── AppStore.ets          # 全局状态管理
│           │   │   └── util/Utils.ets        # 工具函数
│           │   ├── config/
│           │   │   └── Constants.ets         # 全局常量配置
│           │   └── model/
│           │       ├── GameVersion.ets       # 游戏版本模型
│           │       ├── Account.ets           # 账号模型
│           │       ├── LauncherConfig.ets    # 配置模型
│           │       └── DownloadTask.ets      # 下载任务模型
│           └── resources/
│               └── rawfile/                  # HAP 内置资源
│                   ├── amcl-launcher.jar     # AMCL 启动入口（~11KB）
│                   ├── cacert.pem            # CA 证书
│                   ├── stub-objc-bridge.jar  # ObjC 桥接桩（~54KB）
│                   ├── jdk8-ohos-full.zip    # JDK 8 (~38MB)
│                   ├── jdk17-ohos-full-v4.zip # JDK 17 (~109MB)
│                   ├── jdk21-ohos-full.zip   # JDK 21 (~112MB)
│                   └── lwjgl/                # LWJGL JARs（~12MB）
│                       ├── lwjgl.jar
│                       ├── lwjgl-glfw.jar
│                       ├── lwjgl-opengl.jar
│                       └── ...
├── AppScope/app.json5                        # 应用配置
├── build-profile.json5                       # 构建配置
├── hvigorfile.ts / hvigorw                   # 构建脚本
├── oh-package.json5                          # 依赖管理
├── LICENSE                                   # GPL-3.0
└── README.md                                 # 本文件
```

---

## 🛠️ 构建指南

### 环境要求

| 组件 | 版本 |
|------|------|
| DevEco Studio | 5.0+ |
| HarmonyOS SDK | API 26+ (HarmonyOS 5.0+) |
| 目标设备 | HarmonyOS NEXT 手机/平板/PC/2-in-1 |
| 构建主机 | Windows 10/11 |

### 构建步骤

```bash
# 1. 设置环境变量（根据你的 DevEco Studio 安装路径调整）
export DEVECO_SDK_HOME="D:/HarmonyOS/DevEco Studio/sdk"
export OHOS_SDK_NATIVE="$DEVECO_SDK_HOME/default/openharmony/native"
export NODE_OPTIONS="--max-old-space-size=4096"

# 2. 同步依赖并构建（debug 模式，未签名）
bash hvigorw --no-daemon --sync assembleHap
```

构建产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`

### 安装到设备

构建产物为 HAP 包，直接使用鸿蒙系统的标准安装步骤安装到设备即可。

> 注意：HAP 默认未签名，如需安装到真机请在 DevEco Studio 中配置签名证书。

---

## 📦 内置资源

### JDK 运行时

| JDK 版本 | 对应 MC 版本 | 源文件 | 大小 |
|----------|-------------|--------|------|
| JDK 8 | MC 1.0 ~ 1.16.5 | `jdk8-ohos-full.zip` | ~38MB |
| JDK 17 | MC 1.17 ~ 1.20.4 | `jdk17-ohos-full-v4.zip` | ~109MB |
| JDK 21 | MC 1.20.5 ~ 1.21.x | `jdk21-ohos-full.zip` | ~112MB |
| JDK 25 | MC 26.1+ | 网络下载（暂未内置） | — |

JDK 源码：https://github.com/LZZLHY/mc-ohos-resources

### LWJGL JARs

HarmonyOS 兼容的 LWJGL 3.x 构建，包含 14 个 JAR 文件（~12MB），覆盖：
- `lwjgl.jar`（核心）
- `lwjgl-glfw.jar`（窗口/输入 — GLFW shim）
- `lwjgl-opengl.jar` / `lwjgl-opengles.jar`（渲染）
- `lwjgl-openal.jar`（音频）
- `lwjgl-stb.jar`（图像处理）
- `lwjgl-vulkan.jar`（Vulkan 支持）
- 等

---

## 🧩 模组加载器支持

| 加载器 | 状态 | 安装方式 |
|--------|------|---------|
| **Forge** | ✅ 支持 | 下载 install_profile.json → 解析版本 → 下载 libraries + 继承链 |
| **NeoForge** | ✅ 支持 | 同 Forge 流程 |
| **Fabric** | ✅ 支持 | 获取 launcherMeta → 生成 version.json → 下载 libraries |
| **Quilt** | ✅ 支持 | 同 Fabric 流程（使用 Quilt Maven） |

所有下载均支持 **BMCLAPI 镜像加速**，自动 fallback 到 Mojang 官方源。

---

## 🔐 权限声明

`module.json5` 中声明的权限：

| 权限 | 用途 |
|------|------|
| `ohos.permission.INTERNET` | 下载游戏文件、登录 |
| `ohos.permission.GET_NETWORK_INFO` | 网络状态检测 |
| `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` | 下载文件管理 |
| `ohos.permission.MICROPHONE` | 游戏语音（可选） |
| `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY` | **JIT 编译必需** |

---

## 📊 项目状态

| 模块 | 状态 | 备注 |
|------|------|------|
| ArkTS UI 页面 | ✅ 完成 | 所有页面构建通过，0 错误 |
| Native Bridge (libhmcl_native.so) | ✅ 完成 | arm64-v8a + x86_64 双架构 |
| JVM 创建与启动 | ✅ 完成 | dlopen → JNI_CreateJavaVM → AmclLauncher.main() |
| JDK 提取 (rawfile → sandbox) | ✅ 完成 | 支持 ZIP 解压 + 自动展平 |
| LWJGL XComponent 绑定 | ✅ 完成 | 通过 AMCL_SURFACE_ID 环境变量 |
| 模组加载器安装 | ✅ 完成 | Forge / NeoForge / Fabric / Quilt |
| 设置持久化 | ✅ 完成 | `@ohos.data.preferences` 自动保存 |
| 资源包下载 | ✅ 完成 | Asset index + objects 下载，BMCLAPI 镜像 |
| 原生库管理 | ✅ 完成 | .so 库 rawfile 提取 + 网络下载 fallback |
| Microsoft OAuth 登录 | ✅ 完成 | 设备码流程，form-urlencoded 格式 |
| 游戏渲染端到端 | ⏳ 待验证 | 需真机实测 |
| 签名配置 | ⏳ 待配置 | 需在 build-profile.json5 中配置 |

---

## 🙏 致谢

- **[HMCL](https://github.com/HMCL-dev/HMCL)** — 上游启动器项目，GPL-3.0 许可
- **[AMCL](https://github.com/LZZLHY/amcl/releases)** — 鸿蒙原生 Minecraft 启动器，本项目参考了其原生启动架构（AmclLauncher、GLFW shim、AMCL_SURFACE_ID 约定）
- **[LZZLHY/mc-ohos-resources](https://github.com/LZZLHY/mc-ohos-resources)** — HarmonyOS 编译的 JDK 和 LWJGL 资源

---

## 📄 许可

**GPL-3.0** — 与上游 HMCL 项目一致。详见 [LICENSE](LICENSE)。

---

## 🤝 贡献

欢迎提交 Issue 和 PR！如果你在真机上测试了本项目，请分享你的经验和发现。

---

*让 Minecraft 在鸿蒙上自由奔跑 ⛏️*