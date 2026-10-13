import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import window from '@ohos.window';
import resourceManager from '@ohos.resourceManager';
import { BusinessError } from '@ohos.base';
import { Logger, FileUtils } from '../core/util/Utils';
import { GameDirectory } from '../core/game/GameDirectory';
import { VersionManager } from '../core/game/VersionManager';
import { LaunchEngine } from '../core/launch/LaunchEngine';
import { JdkManager } from '../core/launch/JdkManager';
import { JdkExtractor } from '../core/launch/JdkExtractor';
import { PreferencesManager } from '../core/storage/PreferencesManager';
import { ModLoaderInstaller } from '../core/game/ModLoaderInstaller';
import { NativesManager } from '../core/launch/NativesManager';
import { Constants } from '../config/Constants';
import deviceInfo from '@ohos.deviceInfo';

interface BundledJdk {
  rawfile: string;
  dirName: string;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info('EntryAbility', 'onCreate');
  }

  onDestroy(): void {
    Logger.info('EntryAbility', 'onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Get the application context and files directory
    const context = this.context;
    const filesDir = context.filesDir;

    Logger.info('EntryAbility', `Files dir: ${filesDir}`);

    // 沙箱根目录 + CPU 架构注入（旧代码把沙箱路径硬编码成已废弃的 bundleName）
    Constants.appDir = filesDir.endsWith('/') ? filesDir.substring(0, filesDir.length - 1) : filesDir;
    Constants.osArch = EntryAbility.resolveOsArch();
    Logger.info('EntryAbility', `appDir=${Constants.appDir}, osArch=${Constants.osArch}`);

    // 日志目录
    Logger.init(`${filesDir}/${Constants.LOGS_DIR}`);

    // Initialize PreferencesManager for persistent storage
    // Must be done before any other initialization that uses settings
    const prefsManager = PreferencesManager.getInstance();
    prefsManager.setContext(context);
    await prefsManager.init(filesDir);
    Logger.info('EntryAbility', 'PreferencesManager initialized');

    // 铺好完整的 .minecraft 骨架。
    // 之前是「用到才建」，装完游戏只有 versions/libraries/assets，
    // 用户想自己丢模组、光影、截图时不知道往哪放。
    const mcDir = VersionManager.getInstance().getMinecraftDir();
    GameDirectory.ensureSkeleton(mcDir);
    Logger.info('EntryAbility', `游戏目录骨架：${mcDir}`);

    // Initialize the ModLoaderInstaller with base directory
    const modLoaderInstaller = ModLoaderInstaller.getInstance();
    modLoaderInstaller.init(filesDir);
    Logger.info('EntryAbility', 'ModLoaderInstaller initialized');

    // Initialize the NativesManager for native .so library extraction
    const nativesManager = NativesManager.getInstance();
    nativesManager.init(filesDir, context.resourceManager);
    Logger.info('EntryAbility', 'NativesManager initialized');

    // Initialize the JDK manager with resource manager for rawfile extraction
    const jdkManager = JdkManager.getInstance();
    jdkManager.init(filesDir, context.resourceManager);

    // Initialize the launch engine with native bridge
    const launchEngine = LaunchEngine.getInstance();
    launchEngine.init(filesDir);

    // 提取设备兼容层（缺失不致命：native 侧探测不到就以原版行为启动）
    await EntryAbility.extractDeviceCompatJar(context.resourceManager, filesDir);

    // Extract LWJGL JARs in background (for OHOS compatibility)
    EntryAbility.extractLwjglJars(context.resourceManager, filesDir);

    // 3. Extract bundled JDKs in background (UI loads in parallel)
    EntryAbility.extractBundledJdks(context.resourceManager, filesDir).finally(() => {
      Logger.info('EntryAbility', 'Bundled JDK extraction background task completed');
    });

    // Set default JDK path (extraction is still in progress, LaunchEngine handles waiting)
    launchEngine.setJavaHome(filesDir + '/' + Constants.JDK_DIR + '/' + Constants.JDK_17_DIR);

    // Mark that extraction has started so LaunchEngine knows to wait
    launchEngine.setJdkExtractionStarted();

    // Load the main page
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.error('EntryAbility', 'Failed to load content', err);
        return;
      }
      Logger.info('EntryAbility', 'Main page loaded');
    });
  }

  /** deviceInfo.abiList（如 "arm64-v8a,x86_64"）→ 归一化架构名 */
  private static resolveOsArch(): string {
    try {
      const abi = deviceInfo.abiList;
      if (abi && abi.length > 0) {
        const first = abi.split(',')[0].trim().toLowerCase();
        if (first.indexOf('arm64') >= 0 || first.indexOf('aarch64') >= 0) {
          return 'aarch64';
        }
        if (first.indexOf('x86') >= 0) {
          return 'x86_64';
        }
        if (first.indexOf('arm') >= 0) {
          return 'arm';
        }
      }
    } catch (e) {
      Logger.warn('EntryAbility', `abiList 读取失败: ${(e as Error).message}`);
    }
    return 'aarch64';
  }

  onWindowStageDestroy(): void {
    Logger.info('EntryAbility', 'onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.info('EntryAbility', 'onForeground');
  }

  onBackground(): void {
    Logger.info('EntryAbility', 'onBackground');
  }

  /**
  /**
   * 提取设备兼容层 jar（源码见 third_party/amcl-compat/）。
   *
   * 它替换系统类加载器并对特定类做字节码改写，以适配鸿蒙 GPU 上的地形渲染。
   * 提取失败不阻断启动 —— native 侧探测不到文件就不启用这一层。
   */
  private static async extractDeviceCompatJar(
    mgr: resourceManager.ResourceManager,
    filesDir: string,
  ): Promise<void> {
    const jarPath: string = `${filesDir}/${Constants.DEVICE_COMPAT_JAR}`;
    if (FileUtils.exists(jarPath)) {
      Logger.info('EntryAbility', 'device compat jar already in sandbox');
      return;
    }
    Logger.info('EntryAbility', 'Extracting device compat jar from rawfile...');
    const ok: boolean = await JdkExtractor.extractRawFile(
      mgr, Constants.DEVICE_COMPAT_JAR, jarPath);
    if (ok) {
      Logger.info('EntryAbility', 'device compat jar extracted');
    } else {
      Logger.warn('EntryAbility',
        'device compat jar not in rawfile; 将以原版行为启动（地形渲染可能异常）');
    }
  }

  /**
   * Extract LWJGL JARs from rawfile to lwjgl_jars/ directory.
   * These are the OHOS-compatible LWJGL builds that override
   * standard LWJGL JARs from the Minecraft libraries.
   * Non-blocking: runs in background while UI loads.
   */
  private static async extractLwjglJars(
    mgr: resourceManager.ResourceManager,
    filesDir: string,
  ): Promise<void> {
    const targetDir: string = `${filesDir}/${Constants.LWJGL_JARS_DIR}`;
    FileUtils.mkdirs(targetDir);

    for (const rawfileName of Constants.LWJGL_JAR_RAWFILES) {
      // Extract jar filename from path (e.g. 'lwjgl/lwjgl-glfw.jar' -> 'lwjgl-glfw.jar')
      const jarName: string = rawfileName.substring(rawfileName.lastIndexOf('/') + 1);
      const targetPath: string = `${targetDir}/${jarName}`;

      if (FileUtils.exists(targetPath)) {
        continue; // Already extracted
      }

      try {
        const ok: boolean = await JdkExtractor.extractRawFile(mgr, rawfileName, targetPath);
        if (ok) {
          Logger.info('EntryAbility', `LWJGL JAR extracted: ${jarName}`);
        }
      } catch (ex) {
        Logger.warn('EntryAbility', `Failed to extract LWJGL JAR ${rawfileName}: ${(ex as Error).message}`);
      }
    }

    Logger.info('EntryAbility', 'LWJGL JAR extraction complete');
  }

  /**
   * Extract all bundled JDK runtimes from HAP rawfile to app sandbox.
   * Non-blocking: runs in background while the UI loads.
   */
  private static async extractBundledJdks(
    mgr: resourceManager.ResourceManager,
    filesDir: string,
  ): Promise<void> {
    const bundledJdks: BundledJdk[] = [
      { rawfile: Constants.JDK_8_RAWFILE, dirName: Constants.JDK_8_DIR },
      { rawfile: Constants.JDK_17_RAWFILE, dirName: Constants.JDK_17_DIR },
      { rawfile: Constants.JDK_21_RAWFILE, dirName: Constants.JDK_21_DIR },
    ];

    for (const jdk of bundledJdks) {
      const jdkPath: string = `${filesDir}/${Constants.JDK_DIR}/${jdk.dirName}`;

      // Skip if already installed
      const libJvmPaths: string[] = [
        `${jdkPath}/lib/server/libjvm.so`,
        `${jdkPath}/lib/libjvm.so`,
      ];
      let alreadyInstalled: boolean = false;
      for (const p of libJvmPaths) {
        try {
          if (FileUtils.exists(p)) {
            alreadyInstalled = true;
            break;
          }
        } catch (ex) {
          // check error, skip
        }
      }
      if (alreadyInstalled) {
        Logger.info('EntryAbility', `JDK ${jdk.dirName} already in sandbox, skipping extract`);
        continue;
      }

      // Check if rawfile exists and extract
      try {
        const exists: boolean = await JdkExtractor.rawfileExists(mgr, jdk.rawfile);
        if (exists) {
          Logger.info('EntryAbility', `Extracting bundled JDK: ${jdk.rawfile}`);
          await JdkExtractor.extractFromRawfile(mgr, jdk.rawfile, jdkPath);
          Logger.info('EntryAbility', `Bundled JDK extracted: ${jdk.dirName}`);
        } else {
          Logger.info('EntryAbility', `Rawfile ${jdk.rawfile} not bundled, will download on demand`);
        }
      } catch (ex) {
        const err: Error = ex as Error;
        Logger.warn('EntryAbility', `Failed to extract ${jdk.rawfile}: ${err.message}`);
      }
    }
  }
}
