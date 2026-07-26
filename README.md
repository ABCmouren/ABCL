# HMCL-HarmonyOS

> Hello Minecraft! Launcher ported to HarmonyOS NEXT (纯血鸿蒙)

A port of [HMCL](https://github.com/HMCL-dev/HMCL) — the most popular Minecraft Java Edition launcher — to HarmonyOS NEXT. Built with ArkTS + ArkUI, running Minecraft via an embedded JVM through a native NAPI bridge.

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform: HarmonyOS NEXT](https://img.shields.io/badge/Platform-HarmonyOS%20NEXT-red.svg)](https://developer.huawei.com)
[![API Level: 12+](https://img.shields.io/badge/API-12%2B-green.svg)](https://developer.huawei.com)

---

## What is this

HarmonyOS NEXT (API 12+) is a Linux-based OS that ships no JVM. Running Minecraft Java Edition requires:

1. A bundled OHOS-patched JDK (extracted from HAP rawfile on first launch)
2. A native C++ bridge (`libhmcl_native.so`) that calls `JNI_CreateJavaVM` via `dlopen`
3. An AMCL-compatible launcher entry point (`amcl-launcher.jar`) that loads and runs Minecraft's main class
4. An `XComponent` rendering surface that LWJGL's GLFW shim binds to via `OH_NativeWindow_CreateNativeWindowFromSurfaceId`

This project implements all of that, with the launch module faithfully matching AMCL's architecture.

---

## Architecture

```
ArkTS (UI)                          Native C++ (JVM)
──────────────────────────────────  ────────────────────────────────
EntryAbility                        libhmcl_native.so (NAPI)
  └─ extract JDK + amcl-launcher      └─ jvmInit()  → dlopen libjvm.so
  └─ LaunchEngine.init()              └─ registerXComponent(surfaceId)
                                           setenv("AMCL_SURFACE_ID", ...)
GameListPage                        └─ mcLaunch(configJson)
  └─ AppStorage ← launch config           JNI_CreateJavaVM
  └─ startAbility(GameAbility)            AmclLauncher.main(configJson)
                                           └─ loadClass(mainClass)
GameAbility                               └─ method.invoke() ← Minecraft
  └─ forward params → gameLaunchParams
                                    LWJGL GLFW shim
GameView (XComponent surface)         reads AMCL_SURFACE_ID env var
  └─ registerXComponent(surfaceId)    OH_NativeWindow_CreateNativeWindowFromSurfaceId()
  └─ launchFromPending(json)          Minecraft renders to XComponent
```

**LaunchConfig JSON** (passed to `AmclLauncher.main()`):
```json
{
  "mainClass": "net.minecraft.client.main.Main",
  "classpath": ["...lwjgl.jar", "...minecraft.jar", "..."],
  "mcArgs": ["--username", "Player", "--version", "1.20.1", "..."],
  "gameDir": "/data/storage/el2/base/.minecraft",
  "mcDir": "/data/storage/el2/base/.minecraft",
  "filesDir": "/data/storage/el2/base",
  "assetsDir": "/data/storage/el2/base/assets",
  "isForge": false,
  "isFabric": false
}
```

---

## Features

- **Game list** — scan installed Minecraft versions, show loader badges (Forge / Fabric / Quilt / NeoForge)
- **Download** — fetch version manifest from Mojang / BMCLAPI mirror, install client + libraries + assets
- **Accounts** — offline mode, Microsoft OAuth (device code flow), Authlib-Injector
- **Mods** — scan mod JARs, enable/disable, search Modrinth / CurseForge
- **Settings** — memory, JVM args, game directory, download mirror, theme
- **Worlds / Modpacks** — browse saves, modpack import (WIP)
- **Bundled JDK** — JDK 8 / 17 / 21 (OHOS build) extracted from HAP rawfile on first launch
- **JIT support** — detects HarmonyOS NEXT JIT availability, falls back to interpreter mode

---

## Requirements

| Component | Version |
|-----------|---------|
| DevEco Studio | 5.0+ |
| HarmonyOS SDK | API 12+ |
| Target device | HarmonyOS NEXT (phone / tablet / PC / 2-in-1) |
| Host OS (build) | Windows 10/11 |

---

## Build

```bash
# Set environment (adjust paths to your DevEco Studio installation)
export DEVECO_SDK_HOME="D:/HarmonyOS/DevEco Studio/sdk"
export OHOS_SDK_NATIVE="$DEVECO_SDK_HOME/default/openharmony/native"
export NODE_OPTIONS="--max-old-space-size=4096"

# Sync + build (debug, unsigned)
bash hvigorw --no-daemon --sync assembleHap
```

Output: `entry/build/default/outputs/default/entry-default-unsigned.hap`

> **Note on Windows Defender**: The OHOS clang++ toolchain creates temporary `.o.tmp` files during CMake configuration. Windows Defender's real-time protection can lock these files and cause `Permission denied` rename failures. Disable real-time protection or add `C:\xm` (your project root) to exclusions before building.

To install on device:
```bash
hdc app install entry/build/default/outputs/default/entry-default-unsigned.hap
```

---

## Project structure

```
HMCL-HarmonyOS/
├── AppScope/
│   └── app.json5                   # bundleName: com.hmcl.launcher
├── entry/src/main/
│   ├── cpp/
│   │   ├── napi_init.cpp           # NAPI entry, registers all native functions
│   │   ├── jvm_launcher.cpp        # JNI_CreateJavaVM, AmclLauncher.main() invocation
│   │   ├── jvm_launcher.h
│   │   ├── elf_loader.cpp          # Custom ELF loader for JIT support
│   │   ├── input_bridge.cpp        # Touch/keyboard → GLFW input events
│   │   └── CMakeLists.txt
│   └── ets/
│       ├── entryability/
│       │   └── EntryAbility.ets    # App start: extract JDK, init LaunchEngine
│       ├── gameability/
│       │   └── GameAbility.ets     # Fullscreen landscape window, loads GameView
│       ├── pages/
│       │   ├── game/GameView.ets   # XComponent surface, triggers JVM launch
│       │   ├── main/GameListPage.ets
│       │   ├── download/DownloadPage.ets
│       │   ├── account/AccountPage.ets
│       │   ├── settings/SettingsPage.ets
│       │   ├── mod/ModPage.ets
│       │   └── world/WorldPage.ets
│       ├── core/
│       │   ├── launch/
│       │   │   ├── LaunchEngine.ets    # Main launch orchestrator
│       │   │   ├── NativeBridge.ets    # requireNapi('hmcl_native') wrapper
│       │   │   ├── JdkManager.ets      # JDK version selection
│       │   │   └── JdkExtractor.ets    # rawfile → sandbox extraction
│       │   ├── game/VersionManager.ets
│       │   ├── auth/AuthService.ets
│       │   ├── network/
│       │   └── util/Utils.ets
│       ├── config/Constants.ets        # JDK paths, rawfile names, dirs
│       └── model/                      # GameInstallation, Account, etc.
└── entry/src/main/resources/
    └── rawfile/
        ├── amcl-launcher.jar           # AMCL launcher entry point
        ├── jdk8-ohos-full.zip          # JDK 8 (OHOS build, ~38MB)
        ├── jdk17-ohos-full-v4.zip      # JDK 17 (OHOS build, ~109MB)
        └── jdk21-ohos-full.zip         # JDK 21 (OHOS build, ~112MB)
```

---

## Credits

- **[HMCL](https://github.com/HMCL-dev/HMCL)** — the original launcher this project is based on
- **[AMCL](https://github.com/AOF-Dev/AMCL)** — the Android Minecraft launcher whose native launch architecture (`AmclLauncher`, GLFW shim, `AMCL_SURFACE_ID`) this port follows
- **[PojavLauncher](https://github.com/PojavLauncherTeam/PojavLauncher)** — prior art for JVM-on-mobile approaches
- **Huawei DevEco / HarmonyOS NEXT team** — XComponent, NAPI, OH_NativeWindow APIs

---

## License

GPL-3.0 — same as the upstream HMCL project. See [LICENSE](LICENSE).

---

## Status

| Layer | Status |
|-------|--------|
| ArkTS UI (all pages) | Working, builds clean |
| Native JVM bridge (`libhmcl_native.so`) | Builds, JVM launch implemented |
| AmclLauncher integration | Implemented, matches AMCL spec |
| JDK extraction (rawfile → sandbox) | Implemented |
| LWJGL XComponent binding | Implemented (via `AMCL_SURFACE_ID` env) |
| Game rendering end-to-end | Pending real device validation |
| Forge / Fabric installer | Not yet implemented |
| Microsoft OAuth | Implemented (device code flow) |
