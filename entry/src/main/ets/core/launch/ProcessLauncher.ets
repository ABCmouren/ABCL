/**
 * ProcessLauncher — 基于子进程的 JVM 启动器（Stub 模式）
 *
 * 在 HarmonyOS 上，JVM 启动通过 native bridge (hmcl_native NAPI 模块)
 * 直接加载 libjvm.so 创建 JVM，不需要子进程方式。
 *
 * ProcessLauncher 作为 fallback 层提供接口定义和 stub 实现，
 * 当 native bridge 不可用时，LaunchEngine 会降级到 stubLaunch。
 *
 * @ohos.process 子进程 API 在 ArkTS 严格模式下受限，
 * 且 @ohos.process 在 API 26+ 中不支持 Java 进程启动，
 * 因此本模块保持为接口定义 + stub 模式。
 */

import { Constants } from '../../config/Constants';
import { Logger, FileUtils } from '../util/Utils';

export interface ProcessOptions {
  javaHome: string;
  mainClass: string;
  classpath: string[];
  mcArgs: string[];
  minMemory: number;
  maxMemory: number;
  gameDir: string;
  filesDir: string;
  customJvmArgs: string;
  isForge: boolean;
  isFabric: boolean;
}

export interface ProcessHandle {
  pid: number;
  kill(): void;
  onExit(callback: (code: number) => void): void;
  onOutput(callback: (data: string) => void): void;
  onError(callback: (data: string) => void): void;
}

/**
 * ProcessHandleImpl — 实现 ProcessHandle 接口
 * 使用类而非对象字面量，以兼容 ArkTS 严格模式
 */
class ProcessHandleImpl implements ProcessHandle {
  pid: number = 0;
  private killFn: () => void = () => {};
  private onExitFn: (callback: (code: number) => void) => void = () => {};
  private onOutputFn: (callback: (data: string) => void) => void = () => {};
  private onErrorFn: (callback: (data: string) => void) => void = () => {};

  setKill(fn: () => void): void {
    this.killFn = fn;
  }
  setOnExit(fn: (callback: (code: number) => void) => void): void {
    this.onExitFn = fn;
  }
  setOnOutput(fn: (callback: (data: string) => void) => void): void {
    this.onOutputFn = fn;
  }
  setOnError(fn: (callback: (data: string) => void) => void): void {
    this.onErrorFn = fn;
  }

  kill(): void {
    this.killFn();
  }
  onExit(callback: (code: number) => void): void {
    this.onExitFn(callback);
  }
  onOutput(callback: (data: string) => void): void {
    this.onOutputFn(callback);
  }
  onError(callback: (data: string) => void): void {
    this.onErrorFn(callback);
  }
}

export class ProcessLauncher {
  private static readonly TAG = 'ProcessLauncher';
  private static instance: ProcessLauncher;

  private constructor() {}

  static getInstance(): ProcessLauncher {
    if (!ProcessLauncher.instance) {
      ProcessLauncher.instance = new ProcessLauncher();
    }
    return ProcessLauncher.instance;
  }

  /**
   * 检查 Java 可执行文件是否存在
   */
  async checkJavaAvailable(javaHome: string): Promise<boolean> {
    const javaBin = this.getJavaBinPath(javaHome);
    return FileUtils.exists(javaBin);
  }

  /**
   * 获取 Java 可执行文件路径
   */
  private getJavaBinPath(javaHome: string): string {
    return javaHome + '/bin/java';
  }

  /**
   * 构建 JVM 命令行参数（供日志和调试使用）
   */
  buildJvmArgs(opts: ProcessOptions): string[] {
    const args: string[] = [];

    // Memory settings
    args.push('-Xms' + opts.minMemory + 'm');
    args.push('-Xmx' + opts.maxMemory + 'm');

    // GC settings
    args.push('-XX:+UnlockExperimentalVMOptions');
    args.push('-XX:+UseG1GC');
    args.push('-XX:+UnlockDiagnosticVMOptions');
    args.push('-XX:-UseCompressedOops');
    args.push('-XX:-UsePerfData');
    args.push('-XX:+DisableAttachMechanism');
    args.push('-XX:+DisablePrimordialThreadGuardPages');
    args.push('-XX:ActiveProcessorCount=8');
    args.push('-XX:TieredStopAtLevel=1');

    // System properties
    args.push('-Djava.awt.headless=true');
    args.push('-Damcl.platform.ohos=true');
    args.push('-Dfile.encoding=UTF-8');
    args.push('-Dsun.jnu.encoding=UTF-8');
    args.push('-Djava.security.egd=file:/dev/./urandom');
    args.push('-Dorg.lwjgl.glfw.checkThread0=false');
    args.push('-Dlog4j2.formatMsgNoLookups=true');
    args.push('-Dsodium.checks.issue2561=false');

    // Paths
    args.push('-Damcl.mc.dir=' + opts.gameDir);
    args.push('-Duser.dir=' + opts.gameDir);
    args.push('-Duser.home=' + opts.gameDir);
    args.push('-Djava.io.tmpdir=' + opts.filesDir + '/tmp');
    args.push('-Djava.library.path=' + opts.javaHome + '/lib:' + opts.filesDir + '/natives');
    args.push('-Djava.home=' + opts.javaHome);
    args.push('-Dsun.boot.library.path=' + opts.javaHome + '/lib');
    args.push('-Dorg.lwjgl.shaderc.libname=shaderc');
    args.push('-Dorg.lwjgl.spvc.libname=spirv-cross');
    args.push('-Dorg.lwjgl.vulkan.libname=libvulkan.so');

    if (opts.isFabric) {
      args.push('-Dfabric.noGui=true');
    }
    if (opts.isForge) {
      args.push('-Dfml.earlyprogresswindow=false');
      args.push('-Dforge.enableGameTest=false');
    }

    // Build classpath
    let cp = opts.filesDir + '/' + Constants.AMCL_LAUNCHER_JAR;
    for (const entry of opts.classpath) {
      cp = cp + ':' + entry;
    }
    args.push('-Djava.class.path=' + cp);

    // Custom JVM args
    if (opts.customJvmArgs.length > 0) {
      const customParts = opts.customJvmArgs.split(/\s+/);
      for (const part of customParts) {
        if (part.length > 0) {
          args.push(part);
        }
      }
    }

    // Main class
    args.push(opts.mainClass);

    // Minecraft arguments (JSON string)
    const launchConfigStr = JSON.stringify({
      mainClass: opts.mainClass,
      classpath: opts.classpath,
      mcArgs: opts.mcArgs,
      gameDir: opts.gameDir,
      mcDir: opts.gameDir + '/minecraft',
      filesDir: opts.filesDir,
      assetsDir: opts.gameDir + '/' + Constants.ASSETS_DIR,
      isForge: opts.isForge,
      isFabric: opts.isFabric,
    });
    args.push(launchConfigStr);

    return args;
  }

  /**
   * 启动 Java 进程
   *
   * HarmonyOS 上 JVM 启动通过 native bridge (hmcl_native NAPI 模块)
   * 直接加载 libjvm.so 实现，不走子进程方式。
   * 此方法始终返回 stub handle，由 LaunchEngine 的 nativeLaunch 处理实际启动。
   */
  async launchJava(opts: ProcessOptions): Promise<ProcessHandle> {
    const javaBin = this.getJavaBinPath(opts.javaHome);
    Logger.info(ProcessLauncher.TAG,
      'ProcessLauncher stub: would launch Java at ' + javaBin +
      ' mainClass=' + opts.mainClass);

    return this.createStubHandle();
  }

  /**
   * 创建 stub ProcessHandle
   */
  private createStubHandle(): ProcessHandle {
    const stubPid = Math.floor(Math.random() * 100000) + 1;
    const handle = new ProcessHandleImpl();
    handle.pid = stubPid;
    return handle;
  }
}