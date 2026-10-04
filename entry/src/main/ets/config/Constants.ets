/**
 * Constants and configuration for HMCL-HarmonyOS
 */

export class Constants {
  // Microsoft OAuth endpoints
  static readonly MICROSOFT_AUTHORIZE_ENDPOINT = 'https://login.live.com/oauth20_authorize.srf';
  static readonly MICROSOFT_TOKEN_ENDPOINT = 'https://login.live.com/oauth20_token.srf';
  static readonly MICROSOFT_DEVICE_CODE_ENDPOINT = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode';
  static readonly XBOX_LIVE_AUTH_ENDPOINT = 'https://user.auth.xboxlive.com/user/authenticate';
  static readonly XSTS_AUTHORIZE_ENDPOINT = 'https://xsts.auth.xboxlive.com/xsts/authorize';
  static readonly MINECRAFT_AUTH_ENDPOINT = 'https://api.minecraftservices.com/authentication/login_with_xbox';
  static readonly MINECRAFT_PROFILE_ENDPOINT = 'https://api.minecraftservices.com/minecraft/profile';
  static readonly MINECRAFT_STORE_ENDPOINT = 'https://api.minecraftservices.com/entitlements/mcstore';

  // Microsoft OAuth client ID
  // HMCL uses a registered Azure app for Device Code + Auth Code flow.
  // For production use, register your own app at https://portal.azure.com:
  //   1. App registrations → New registration (Mobile/Desktop platform)
  //   2. Redirect URI: https://login.live.com/oauth20_desktop.srf
  //   3. Grant: "XboxLive.signin" and "offline_access"
  // The default below works for testing with Device Code flow only.
  static readonly MICROSOFT_CLIENT_ID = '00000000-0000-0000-0000-000000000000';
  // Alias for backward compatibility
  static readonly AZURE_CLIENT_ID = Constants.MICROSOFT_CLIENT_ID;

  // Microsoft OAuth redirect URI
  static readonly MICROSOFT_REDIRECT_URI = 'https://login.live.com/oauth20_desktop.srf';

  // Microsoft OAuth scopes
  static readonly MICROSOFT_SCOPES = 'XboxLive.signin offline_access';

  // Auth endpoints (aliases used by AuthService)
  static readonly XBL_AUTHENTICATE = 'https://user.auth.xboxlive.com/user/authenticate';
  static readonly XSTS_AUTHORIZE = 'https://xsts.auth.xboxlive.com/xsts/authorize';
  static readonly MINECRAFT_AUTH = 'https://api.minecraftservices.com/authentication/login_with_xbox';
  static readonly MINECRAFT_PROFILE = 'https://api.minecraftservices.com/minecraft/profile';

  // Mojang / BMCLAPI endpoints
  static readonly MOJANG_VERSION_MANIFEST = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
  static readonly BMCLAPI_VERSION_MANIFEST = 'https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json';
  static readonly MOJANG_RESOURCES_BASE = 'https://resources.download.minecraft.net';
  static readonly BMCLAPI_RESOURCES_BASE = 'https://bmclapi2.bangbang93.com/assets';
  static readonly MOJANG_LIBRARIES_BASE = 'https://libraries.minecraft.net';
  static readonly BMCLAPI_LIBRARIES_BASE = 'https://bmclapi2.bangbang93.com/maven';
  static readonly MOJANG_VERSION_BASE = 'https://piston-meta.mojang.com';
  static readonly BMCLAPI_VERSION_BASE = 'https://bmclapi2.bangbang93.com';

  // Forge / Fabric / Quilt / NeoForge endpoints
  static readonly FORGE_MAVEN = 'https://maven.minecraftforge.net';
  static readonly BMCLAPI_FORGE_MAVEN = 'https://bmclapi2.bangbang93.com/forge';
  static readonly FABRIC_MAVEN = 'https://maven.fabricmc.net';
  // BMCLAPI 没有 fabric 镜像（实测 404），Fabric 必须走官方 maven
  static readonly BMCLAPI_FABRIC_MAVEN = 'https://maven.fabricmc.net';
  static readonly QUILT_MAVEN = 'https://maven.quiltmc.org/repository/release';
  // NeoForge 的 maven 根带 /releases 前缀（旧代码漏了，导致 NeoForge 全部 404）
  static readonly NEO_FORGE_MAVEN = 'https://maven.neoforged.net/releases';

  // Mod platform APIs
  // Fabric / Quilt 官方 meta API（BMCLAPI 没有镜像，必须走官方）
  static readonly FABRIC_META = 'https://meta.fabricmc.net';
  static readonly QUILT_META = 'https://meta.quiltmc.org';

  static readonly MODRINTH_API = 'https://api.modrinth.com/v2';
  static readonly CURSEFORGE_API = 'https://api.curseforge.com/v1';

  // Preferences storage keys
  static readonly PREF_KEY_ACCOUNTS = 'hmcl_accounts';
  static readonly PREF_KEY_SELECTED_ACCOUNT = 'hmcl_selected_account';
  static readonly PREF_KEY_INSTALLATIONS = 'hmcl_installations';
  static readonly PREF_KEY_LAUNCH_SETTINGS = 'hmcl_launch_settings';
  static readonly PREF_KEY_DOWNLOAD_SOURCE = 'hmcl_download_source';

  // 应用沙箱根目录：由 EntryAbility 在启动时用 context.filesDir 注入。
  // 旧代码把它硬编码成 '/data/app/el2/100/base/com.hmcl.launcher/'，
  // 而 AppScope 的 bundleName 早已改成 com.abcmouren.HMCL_HarmonyOS，
  // 该路径在设备上不存在 → 所有默认游戏目录都写不进去。
  static appDir: string = '';
  static readonly MINECRAFT_DIR = 'minecraft';

  /** 拼接沙箱根与子路径（避免 files + minecraft = filesminecraft 的经典错误） */
  static joinRoot(root: string, leaf: string): string {
    if (root.length === 0) {
      return leaf;
    }
    return root.endsWith('/') ? root + leaf : root + '/' + leaf;
  }

  /** 默认的 .minecraft 目录：<sandbox>/minecraft */
  static baseDir(): string {
    return Constants.joinRoot(Constants.appDir, Constants.MINECRAFT_DIR);
  }
  /** 运行设备的 CPU 架构（'aarch64' / 'x86_64'），由 EntryAbility 从 deviceInfo.abiList 注入 */
  static osArch: string = 'aarch64';

  // 下载并发（AMCL 的 native 引擎默认 6~8；assets 多而小，可以更高）
  static readonly DOWNLOAD_CONCURRENCY = 8;
  static readonly ASSET_CONCURRENCY = 12;

  // Game directories
  static readonly GAME_DIR = 'minecraft';
  static readonly VERSIONS_DIR = 'versions';
  static readonly ASSETS_DIR = 'assets';
  static readonly LIBRARIES_DIR = 'libraries';
  static readonly MODS_DIR = 'mods';
  static readonly RESOURCE_PACKS_DIR = 'resourcepacks';
  static readonly RESOURCEPACKS_DIR = 'resourcepacks';
  static readonly SHADER_PACKS_DIR = 'shaderpacks';
  static readonly CRASH_REPORTS_DIR = 'crash-reports';
  static readonly LOGS_DIR = 'logs';
  static readonly CONFIG_DIR = 'config';
  static readonly SCREENSHOTS_DIR = 'screenshots';
  static readonly SAVES_DIR = 'saves';

  // Default JVM arguments
  static readonly DEFAULT_JVM_ARGS = [
    '-XX:+UnlockExperimentalVMOptions',
    '-XX:+UseG1GC',
    '-XX:G1NewSizePercent=20',
    '-XX:G1ReservePercent=20',
    '-XX:MaxGCPauseMillis=50',
    '-XX:G1HeapRegionSize=32M',
  ];

  // Default game window size
  static readonly DEFAULT_WIDTH = 854;
  static readonly DEFAULT_HEIGHT = 480;

  // JDK Runtime (AMCL's mc-ohos-resources GPL-2.0 builds)
  static readonly JDK_RELEASES_BASE = 'https://github.com/LZZLHY/mc-ohos-resources/releases/download';

  // JDK 17 - Stable (MC 1.18-1.20.4)
  static readonly JDK_17_TAG = 'v17.0.13-ohos-5';
  static readonly JDK_17_ASSET = 'jdk17-ohos-full-v5.zip';
  static readonly JDK_17_SHA256 = '0e26b0dece38156838456cfb12058d863aa9856cdd8fd648f06f9bc5e91f8ecd';
  static readonly JDK_17_URL = `${Constants.JDK_RELEASES_BASE}/${Constants.JDK_17_TAG}/${Constants.JDK_17_ASSET}`;

  // JDK 21 - Experimental (MC 1.20.5-1.21.x)
  static readonly JDK_21_TAG = 'v21.0.5-ohos-7';
  static readonly JDK_21_ASSET = 'jdk21-ohos-full-v7.zip';
  static readonly JDK_21_SHA256 = '21556d0d4fc5eea09ba27068cf8a96803bb1667b35adbc8495fdc5f831316275';
  static readonly JDK_21_URL = `${Constants.JDK_RELEASES_BASE}/${Constants.JDK_21_TAG}/${Constants.JDK_21_ASSET}`;

  // JDK 25 - Latest (MC 26.1+)
  static readonly JDK_25_TAG = 'v25.0.4-ohos-2';
  static readonly JDK_25_ASSET = 'jdk25-ohos-full-v2.zip';
  static readonly JDK_25_SHA256 = 'd8e31df5d199a9b34d6d13c188b71af19c2fb1738da7bf3c6eeaed89a0a37538';
  static readonly JDK_25_URL = `${Constants.JDK_RELEASES_BASE}/${Constants.JDK_25_TAG}/${Constants.JDK_25_ASSET}`;

  // JDK 8 - Legacy (MC 1.0-1.16.5)
  static readonly JDK_8_TAG = 'v8u452-ohos-4';
  static readonly JDK_8_ASSET = 'jdk8-ohos-full-v4.zip';
  static readonly JDK_8_SHA256 = '02c2cedb3539682de3df3d7870b855bfefaac1f4cfe53951cfe90b0dea3d3a63';
  static readonly JDK_8_URL = `${Constants.JDK_RELEASES_BASE}/${Constants.JDK_8_TAG}/${Constants.JDK_8_ASSET}`;

  // Local JDK storage paths (relative to app sandbox)
  static readonly JDK_DIR = 'jdk_runtimes';
  static readonly JDK_17_DIR = 'jdk17';
  static readonly JDK_21_DIR = 'jdk21';
  static readonly JDK_25_DIR = 'jdk25';
  static readonly JDK_8_DIR = 'jdk8';

  // Rawfile asset names for bundled JDKs (must match filenames in resources/rawfile/)
  static readonly JDK_8_RAWFILE = 'jdk8-ohos-full-v4.zip';
  static readonly JDK_17_RAWFILE = 'jdk17-ohos-full-v5.zip';
  static readonly JDK_21_RAWFILE = 'jdk21-ohos-full-v7.zip';

  // Amcl launcher JAR (bundled in rawfile or downloaded)
  static readonly AMCL_LAUNCHER_JAR = 'amcl-launcher.jar';

  // GLFW native lib for HarmonyOS (reuse from AMCL build)
  static readonly GLFW_LIB_NAME = 'libglfw.so';
  
  // Native libraries that need to be extracted for LWJGL
  static readonly NATIVE_LIBS: string[] = [
    'libglfw.so',
    'liblwjgl.so',
    'liblwjgl_opengl.so',
    'liblwjgl_stb.so',
    'liblwjgl_tinyfd.so',
    'libopenal.so',
    'libc++_shared.so',
  ];

  // LWJGL JARs bundled in rawfile (AMCL's OHOS-compatible build)
  // Extracted at startup to lwjgl_jars/ dir and added to classpath
  static readonly LWJGL_JAR_RAWFILES: string[] = [
    'lwjgl/lwjgl.jar',
    'lwjgl/lwjgl-egl.jar',
    'lwjgl/lwjgl-freetype.jar',
    'lwjgl/lwjgl-glfw.jar',
    'lwjgl/lwjgl-jemalloc.jar',
    'lwjgl/lwjgl-openal.jar',
    'lwjgl/lwjgl-opengl.jar',
    'lwjgl/lwjgl-opengles.jar',
    'lwjgl/lwjgl-shaderc.jar',
    'lwjgl/lwjgl-spvc.jar',
    'lwjgl/lwjgl-stb.jar',
    'lwjgl/lwjgl-tinyfd.jar',
    'lwjgl/lwjgl-vma.jar',
    'lwjgl/lwjgl-vulkan.jar',
  ];
  // Where LWJGL JARs are extracted in sandbox
  static readonly LWJGL_JARS_DIR = 'lwjgl_jars';

  // MC version → JDK mapping
  // MC version format: "1.x.y" or "x.y" for newer releases
  static getJdkForMcVersion(mcVersion: string): string {
    const versionNum = mcVersion.split('.');
    const major = parseInt(versionNum[0]) || 0;
    const minor = parseInt(versionNum[1]) || 0;
    const patch = parseInt(versionNum[2]) || 0;

    // Minecraft 26.1+ → JDK 25 (Java 25)
    if (major >= 26) return Constants.JDK_25_URL;

    // Minecraft 1.21.x → JDK 21
    if (major == 1 && minor == 21) return Constants.JDK_21_URL;

    // Minecraft 1.20.5+ → JDK 21
    if (major == 1 && minor == 20 && patch >= 5) return Constants.JDK_21_URL;

    // Minecraft 1.18-1.20.4 → JDK 17
    if (major == 1 && minor >= 18) return Constants.JDK_17_URL;

    // Minecraft 1.17 → JDK 17 (recommended 16, use 17 as it's compatible)
    if (major == 1 && minor == 17) return Constants.JDK_17_URL;

    // Minecraft 1.13-1.16.5 → JDK 8
    if (major == 1 && minor >= 13) return Constants.JDK_8_URL;

    // Minecraft ≤1.12.2 → JDK 8
    if (major == 1) return Constants.JDK_8_URL;

    // Default: JDK 17
    return Constants.JDK_17_URL;
  }

  // Get JDK directory name from URL
  static getJdkDirName(jdkUrl: string): string {
    if (jdkUrl.includes(Constants.JDK_17_ASSET)) return Constants.JDK_17_DIR;
    if (jdkUrl.includes(Constants.JDK_21_ASSET)) return Constants.JDK_21_DIR;
    if (jdkUrl.includes(Constants.JDK_25_ASSET)) return Constants.JDK_25_DIR;
    if (jdkUrl.includes(Constants.JDK_8_ASSET)) return Constants.JDK_8_DIR;
    return Constants.JDK_17_DIR;
  }

  // Get rawfile asset name for a bundled JDK by URL
  static getJdkRawfileName(jdkUrl: string): string {
    if (jdkUrl.includes(Constants.JDK_17_ASSET)) return Constants.JDK_17_RAWFILE;
    if (jdkUrl.includes(Constants.JDK_21_ASSET)) return Constants.JDK_21_RAWFILE;
    if (jdkUrl.includes(Constants.JDK_8_ASSET)) return Constants.JDK_8_RAWFILE;
    return '';
  }
}