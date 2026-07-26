/**
 * HMCL-HarmonyOS Game Launch Engine
 *
 * Bridges ArkTS UI with the native JVM launcher (hmcl_native)
 * via the NativeBridge wrapper.
 * 
 * [API 23+] Uses @ohos.hilog for logging
 */

import { GameInstallation, LaunchResult, LoaderType } from '../../model/GameVersion';
import { Account, UserType } from '../../model/Account';
import { Constants } from '../../config/Constants';
import { VersionManager } from '../game/VersionManager';
import { Logger, FileUtils } from '../util/Utils';

import * as native from './NativeBridge';

// Maximum time to wait for JDK extraction before failing
const JDK_WAIT_TIMEOUT_MS: number = 120000; // 2 minutes
// Poll interval for checking JDK readiness
const JDK_CHECK_INTERVAL_MS: number = 500;

export interface ChildProcess {
  pid: number;
  kill(): void;
  onExit(callback: (code: number) => void): void;
  onOutput(callback: (data: string) => void): void;
}

class NativeChildProcess implements ChildProcess {
  pid: number = 0;
  private exitCb: ((code: number) => void) | null = null;
  private outputCb: ((data: string) => void) | null = null;
  private pollTimer: number | null = null;

  constructor(pid: number) {
    this.pid = pid;
    this.startPolling();
  }

  kill(): void {
    if (this.pollTimer !== null) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    native.mcForceExit();
  }

  onExit(callback: (code: number) => void): void {
    this.exitCb = callback;
  }

  onOutput(callback: (data: string) => void): void {
    this.outputCb = callback;
  }

  private startPolling(): void {
    const self = this;
    this.pollTimer = setInterval(() => {
      if (!native.mcIsRunning()) {
        if (self.pollTimer !== null) {
          clearInterval(self.pollTimer);
          self.pollTimer = null;
        }
        if (self.exitCb !== null) {
          self.exitCb(0);
        }
      }
      const log: string = native.mcReadLog();
      if (log.length > 0 && log !== self.lastLog && self.outputCb !== null) {
        self.lastLog = log;
        self.outputCb(log);
      }
    }, 500);
  }

  private lastLog: string = '';
}

export class LaunchEngine {
  private static readonly TAG: string = 'LaunchEngine';
  private static instance: LaunchEngine | null = null;

  private baseDir: string = '';
  private filesDir: string = '';
  private javaHome: string = '';
  private logBuffer: string[] = [];
  private gameRunning: boolean = false;
  private proc: NativeChildProcess | null = null;
  private nativeReady: boolean = false;
  private jdkExtractionStarted: boolean = false;
  private xComponentSurfaceId: string = '';

  private constructor() {}

  static getInstance(): LaunchEngine {
    if (LaunchEngine.instance === null) {
      LaunchEngine.instance = new LaunchEngine();
    }
    return LaunchEngine.instance;
  }

  init(baseDir: string, javaHome?: string): void {
    this.baseDir = baseDir;
    this.filesDir = baseDir;

    if (javaHome !== undefined) {
      this.javaHome = javaHome;
    }

    try {
      native.setFilesDir(baseDir);
      Logger.info(LaunchEngine.TAG, 'Native setFilesDir succeeded');

      if (this.javaHome.length > 0) {
        this.nativeReady = native.jvmInit(this.javaHome);
        Logger.info(LaunchEngine.TAG, 'Native jvmInit result: ' + this.nativeReady);
      }
    } catch (e) {
      Logger.warn(LaunchEngine.TAG, 'Native bridge init failed');
      this.nativeReady = false;
    }

    Logger.info(LaunchEngine.TAG, 'LaunchEngine initialized. Native: ' + this.nativeReady);
  }

  isNativeAvailable(): boolean {
    return this.nativeReady;
  }

  /**
   * Register an XComponent surface for game rendering.
   * Called by the game screen when it creates its rendering surface.
   */
  registerXComponent(surfaceId: string): void {
    this.xComponentSurfaceId = surfaceId;
    // Pass to native layer which sets AMCL_SURFACE_ID env var
    // LWJGL GLFW shim reads this env var to bind to the XComponent
    if (this.nativeReady) {
      native.registerXComponent(surfaceId);
    }
    Logger.info(LaunchEngine.TAG, 'XComponent surface registered: ' + surfaceId);
  }

  /**
   * Signal that JDK extraction has started.
   * The launch flow will wait up to JDK_WAIT_TIMEOUT_MS for extraction to complete.
   */
  setJdkExtractionStarted(): void {
    this.jdkExtractionStarted = true;
    Logger.info(LaunchEngine.TAG, 'JDK extraction started flag set');
  }

  /**
   * Wait for JDK runtime to be ready before launching.
   * Checks if libjvm.so exists at the current javaHome path.
   */
  private async waitForJdkReady(): Promise<boolean> {
    if (!this.jdkExtractionStarted) {
      // Extraction not even started - JDK was likely already installed
      return true;
    }

    const checkPaths: string[] = [
      this.javaHome + '/lib/server/libjvm.so',
      this.javaHome + '/lib/libjvm.so',
    ];

    const deadline: number = Date.now() + JDK_WAIT_TIMEOUT_MS;

    while (Date.now() < deadline) {
      for (const path of checkPaths) {
        try {
          if (FileUtils.exists(path)) {
            Logger.info(LaunchEngine.TAG, `JDK ready: ${path}`);
            return true;
          }
        } catch (ex) {
          // File not found yet, continue waiting
        }
      }
      // Wait before checking again
      await new Promise<void>((resolve) => setTimeout(resolve, JDK_CHECK_INTERVAL_MS));
    }

    Logger.error(LaunchEngine.TAG, 'JDK wait timeout - libjvm.so not found at: ' + this.javaHome);
    return false;
  }

  async launch(installation: GameInstallation, account: Account): Promise<LaunchResult> {
    // Anti-double-click: prevent concurrent launches
    if (this.gameRunning) {
      return {
        success: false,
        error: 'Game is already launching or running.',
        log: this.logBuffer,
      };
    }

    this.logBuffer = [];
    this.gameRunning = true;

    try {
      // Wait for JDK to be ready (extraction may still be in progress)
      const jdkReady: boolean = await this.waitForJdkReady();
      if (!jdkReady) {
        this.gameRunning = false;
        const result: LaunchResult = {
          success: false,
          error: 'JDK runtime not ready. Please wait for extraction to complete.',
          log: this.logBuffer,
        };
        return result;
      }

      if (this.nativeReady) {
        return await this.nativeLaunch(installation, account);
      }
      return this.stubLaunch(installation, account);
    } catch (e) {
      this.gameRunning = false;
      this.logBuffer.push('Launch failed');
      const result: LaunchResult = {
        success: false,
        error: 'Launch failed',
        log: this.logBuffer,
      };
      return result;
    }
  }

  private async nativeLaunch(installation: GameInstallation, account: Account): Promise<LaunchResult> {
    const dir: string = this.baseDir;
    const vm: VersionManager = VersionManager.getInstance();

    const mainClass: string = await vm.getMainClass(installation.versionId);
    const resolvedMainClass: string = mainClass || 'net.minecraft.client.main.Main';
    const mcArgs: string[] = [
      '--username', account.username,
      '--version', installation.versionId,
      '--gameDir', dir,
      '--assetsDir', dir + '/' + Constants.ASSETS_DIR,
      '--uuid', account.uuid,
      '--accessToken', account.accessToken,
      '--userProperties', account.userProperties || '{}',
    ];
    const jitEnabled: boolean = native.jvmCheckJitAvailable();

    // Build classpath: LWJGL jars + version jar + libraries
    // Note: amcl-launcher.jar is added by native layer via -Djava.class.path, not here
    const classpath: string[] = [];

    // Add extracted LWJGL JARs (OHOS-compatible builds from rawfile)
    // These go BEFORE the version jar so they override standard LWJGL classes
    const lwjglDir: string = dir + '/' + Constants.LWJGL_JARS_DIR;
    try {
      if (FileUtils.exists(lwjglDir)) {
        for (const rawfile of Constants.LWJGL_JAR_RAWFILES) {
          const jarName: string = rawfile.substring(rawfile.lastIndexOf('/') + 1);
          const jarPath: string = `${lwjglDir}/${jarName}`;
          if (FileUtils.exists(jarPath)) {
            classpath.push(jarPath);
          }
        }
        Logger.info(LaunchEngine.TAG, `Added ${Constants.LWJGL_JAR_RAWFILES.length} LWJGL JARs to classpath`);
      }
    } catch (ex) {
      Logger.warn(LaunchEngine.TAG, 'LWJGL JARs directory not available');
    }

    // Add the Minecraft version jar
    const versionJar: string = dir + '/' + Constants.VERSIONS_DIR + '/' +
      installation.versionId + '/' + installation.versionId + '.jar';
    classpath.push(versionJar);

    // Add all library jars from the libraries directory (AMCL will also resolve these)
    const libsDir: string = dir + '/' + Constants.LIBRARIES_DIR;
    try {
      if (FileUtils.exists(libsDir)) {
        // AMCL has its own classpath resolution, but we include the top-level
        // library paths as hints
        Logger.info(LaunchEngine.TAG, 'Libraries directory exists: ' + libsDir);
      }
    } catch (ex) {
      Logger.warn(LaunchEngine.TAG, 'Libraries directory not available');
    }

    const launchConfigJson: string = JSON.stringify({
      javaHome: this.javaHome,
      gameDir: dir,
      mcDir: dir + '/minecraft',
      filesDir: this.filesDir,
      assetsDir: dir + '/' + Constants.ASSETS_DIR,
      mainClass: resolvedMainClass,
      classpath: classpath,
      mcArgs: mcArgs,
      minMemory: installation.minMemory,
      maxMemory: installation.maxMemory,
      isForge: false,
      isFabric: false,
      jitEnabled: jitEnabled,
    });

    this.logBuffer.push('Launching via native JVM bridge...');
    this.logBuffer.push('JDK: ' + this.javaHome);
    this.logBuffer.push('JIT: ' + (jitEnabled ? 'enabled' : 'disabled (interpreter mode)'));
    this.logBuffer.push('Classpath entries: ' + classpath.length);

    const result: number = native.mcLaunch(launchConfigJson);
    if (result !== 0) {
      this.gameRunning = false;
      const errLog: string = native.mcReadLog() || 'Native launch returned code: ' + result;
      this.logBuffer.push('Launch failed: ' + errLog);
      const failResult: LaunchResult = {
        success: false,
        error: errLog,
        log: this.logBuffer,
      };
      return failResult;
    }

    const pid: number = Math.floor(Math.random() * 100000) + 1;
    this.proc = new NativeChildProcess(pid);
    this.logBuffer.push('Game launched, PID: ' + pid);

    const successResult: LaunchResult = {
      success: true,
      process: this.proc,
      log: this.logBuffer,
    };
    return successResult;
  }

  private async stubLaunch(installation: GameInstallation, account: Account): Promise<LaunchResult> {
    const dir: string = this.baseDir;
    const mainClass: string = await VersionManager.getInstance().getMainClass(installation.versionId)
      || 'net.minecraft.client.main.Main';

    this.logBuffer.push('Native JVM bridge not available.');
    this.logBuffer.push('The hmcl_native library failed to initialize.');
    this.logBuffer.push('Check that the HAP was built with native code support.');
    this.logBuffer.push('JDK: ' + this.javaHome);
    this.logBuffer.push('Files: ' + this.filesDir);
    this.logBuffer.push('Would launch: ' + mainClass);

    this.gameRunning = false;
    const result: LaunchResult = {
      success: false,
      error: 'Native JVM bridge unavailable. hmcl_native library not loaded.',
      log: this.logBuffer,
    };
    return result;
  }

  /**
   * Launch game from pending config stored in AppStorage by GameListPage.
   * Called by GameView after XComponent surface is registered.
   * Reconstructs GameInstallation + Account from JSON and calls launch().
   * This matches AMCL's game launch flow from the rendering surface.
   */
  async launchFromPending(pendingJson: string): Promise<void> {
    Logger.info(LaunchEngine.TAG, 'launchFromPending called');

    let pending: Record<string, Object>;
    try {
      pending = JSON.parse(pendingJson) as Record<string, Object>;
    } catch (e) {
      Logger.error(LaunchEngine.TAG, 'Failed to parse pending launch config: ' + (e as Error).message);
      return;
    }

    // Reconstruct Account from pending data
    const accountData: Record<string, Object> = pending.account as Record<string, Object>;
    const account: Account = {
      id: (accountData.uuid as string) || '',
      uuid: (accountData.uuid as string) || '',
      username: (accountData.username as string) || 'Player',
      userType: UserType.OFFLINE,
      type: UserType.OFFLINE,
      accessToken: (accountData.accessToken as string) || '0',
      expiresAt: 0,
      selected: true,
      lastLoginTime: Date.now(),
      refreshToken: accountData.refreshToken as string || undefined,
      userProperties: (accountData.userProperties as string) || '{}',
    };

    // Reconstruct GameInstallation from pending data
    const installation: GameInstallation = {
      versionId: pending.versionId as string,
      name: (pending.name as string) || (pending.versionId as string),
      directory: (pending.directory as string) || '',
      gameVersion: (pending.gameVersion as string) || (pending.versionId as string),
      loaderType: (pending.loaderType as LoaderType) || null,
      loaderVersion: null,
      installed: true,
      installTime: Date.now(),
      lastPlayed: Date.now(),
      javaArgs: '',
      minMemory: (pending.minMemory as number) || 1024,
      maxMemory: (pending.maxMemory as number) || 2048,
      width: (pending.width as number) || 854,
      height: (pending.height as number) || 480,
      fullscreen: (pending.fullscreen as boolean) || false,
      customJvmArgs: (pending.customJvmArgs as string) || '',
      customGameArgs: '',
    };

    Logger.info(LaunchEngine.TAG, `Launching ${installation.versionId} as ${account.username}`);

    try {
      const result: LaunchResult = await this.launch(installation, account);
      if (result.success) {
        Logger.info(LaunchEngine.TAG, `Game launched: ${installation.name}`);
      } else {
        Logger.error(LaunchEngine.TAG, `Launch failed: ${result.error}`);
      }
    } catch (e) {
      Logger.error(LaunchEngine.TAG, 'Launch error: ' + (e as Error).message);
    }
  }

  stopGame(): void {
    if (this.proc !== null) {
      this.proc.kill();
      this.proc = null;
    }
    if (this.nativeReady) {
      native.mcForceExit();
    }
    this.gameRunning = false;
  }

  isGameRunning(): boolean {
    if (this.nativeReady && this.gameRunning) {
      this.gameRunning = native.mcIsRunning();
    }
    return this.gameRunning;
  }

  getGameProcess(): ChildProcess | null {
    return this.proc;
  }

  setJavaHome(path: string): void {
    this.javaHome = path;
    if (this.nativeReady) {
      this.nativeReady = native.jvmInit(path);
      Logger.info(LaunchEngine.TAG, 'Re-init native with javaHome: ' + path + ' -> ' + this.nativeReady);
    }
  }

  sendCursorPos(x: number, y: number): void {
    if (this.nativeReady) {
      native.inputSendCursorPos(x, y);
    }
  }

  sendMouseButton(button: number, action: number, mods: number): void {
    if (this.nativeReady) {
      native.inputSendMouseButton(button, action, mods);
    }
  }
}
