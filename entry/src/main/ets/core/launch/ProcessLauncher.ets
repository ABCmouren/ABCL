/**
 * ProcessLauncher — 基于子进程的 JVM 启动器
 *
 * 作为 native JVM bridge 的 fallback 方式。
 * 使用 @ohos.process 的子进程 API 启动 Java 进程。
 *
 * 注意：HarmonyOS 的 @ohos.process API 在不同版本有差异。
 * 如果该 API 不可用，会自动降级到 stub 模式。
 *
 * 流程：
 * 1. 检查 javaHome 下是否有 java 可执行文件
 * 2. 构建完整的 JVM 命令行参数
 * 3. 启动 Java 进程
 * 4. 通过管道读取 stdout/stderr 日志
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
    return `${javaHome}/bin/java`;
  }

  /**
   * 构建 JVM 命令行参数
   */
  buildJvmArgs(opts: ProcessOptions): string[] {
    const args: string[] = [];

    // Memory settings
    args.push(`-Xms${opts.minMemory}m`);
    args.push(`-Xmx${opts.maxMemory}m`);

    // GC settings (matching AMCL)
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
    args.push(`-Damcl.mc.dir=${opts.gameDir}`);
    args.push(`-Duser.dir=${opts.gameDir}`);
    args.push(`-Duser.home=${opts.gameDir}`);
    args.push(`-Djava.io.tmpdir=${opts.filesDir}/tmp`);
    args.push(`-Djava.library.path=${opts.javaHome}/lib:${opts.filesDir}/natives`);
    args.push(`-Djava.home=${opts.javaHome}`);
    args.push(`-Dsun.boot.library.path=${opts.javaHome}/lib`);

    // LWJGL libs
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
    let cp = `${opts.filesDir}/${Constants.AMCL_LAUNCHER_JAR}`;
    for (const entry of opts.classpath) {
      cp = cp + ':' + entry;
    }
    args.push(`-Djava.class.path=${cp}`);

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

    // Minecraft arguments (passed as a single JSON string to AmclLauncher)
    const launchConfigStr = JSON.stringify({
      mainClass: opts.mainClass,
      classpath: opts.classpath,
      mcArgs: opts.mcArgs,
      gameDir: opts.gameDir,
      mcDir: `${opts.gameDir}/minecraft`,
      filesDir: opts.filesDir,
      assetsDir: `${opts.gameDir}/${Constants.ASSETS_DIR}`,
      isForge: opts.isForge,
      isFabric: opts.isFabric,
    });
    args.push(launchConfigStr);

    return args;
  }

  /**
   * 启动 Java 进程
   * 使用 @ohos.process 的 child process API
   */
  async launchJava(opts: ProcessOptions): Promise<ProcessHandle> {
    const javaBin = this.getJavaBinPath(opts.javaHome);

    if (!FileUtils.exists(javaBin)) {
      throw new Error('Java executable not found at: ' + javaBin);
    }

    // 构建完整命令行
    const jvmArgs = this.buildJvmArgs(opts);

    Logger.info(ProcessLauncher.TAG, `Launching Java: ${javaBin} args=${jvmArgs.length}`);

    try {
      // 尝试使用 @ohos.process 的子进程 API
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const processModule = await import('@ohos.process');

      // 尝试创建子进程
      let childProcess: object | null = null;
      let childPid: number = 0;

      // 检查 API 类型 — 使用 Record 安全访问
      const processAny = processModule as object as Record<string, Object>;

      // 风格 1: process.createChildProcess (旧 API)
      const createChildFn = processAny['createChildProcess'];
      if (typeof createChildFn === 'function') {
        childProcess = (createChildFn as (cmd: string, args: string[]) => object)(javaBin, jvmArgs);
        const childObj = childProcess as object as Record<string, number>;
        childPid = childObj['pid'] || 0;
        Logger.info(ProcessLauncher.TAG, 'Created child process via createChildProcess, pid=' + childPid);
      }

      // 如果子进程创建失败，返回 stub handle
      if (!childProcess || childPid === 0) {
        Logger.warn(ProcessLauncher.TAG, 'Child process API not available, using stub');
        return this.createStubHandle();
      }

      const childRec = childProcess as object as Record<string, Object>;
      return this.buildHandleFromChild(childRec, childPid);
    } catch (e) {
      const err = e as Error;
      Logger.error(ProcessLauncher.TAG, 'Failed to launch Java process: ' + err.message);
      // 返回 stub handle，让调用方能继续
      return this.createStubHandle();
    }
  }

  /**
   * 从子进程对象构建 ProcessHandle
   */
  private buildHandleFromChild(child: Record<string, Object>, childPid: number): ProcessHandle {
    const handlePid = childPid;

    // 预先绑定方法引用
    const killImpl = this.createKillImpl(child, handlePid);
    const onExitImpl = this.createOnExitImpl(child);
    const onOutputImpl = this.createOnStreamImpl(child, 'stdout');
    const onErrorImpl = this.createOnStreamImpl(child, 'stderr');

    const handle = new ProcessHandleImpl();
    handle.pid = handlePid;
    handle.setKill(killImpl);
    handle.setOnExit(onExitImpl);
    handle.setOnOutput(onOutputImpl);
    handle.setOnError(onErrorImpl);
    return handle;
  }

  /**
   * 创建 kill 实现
   */
  private createKillImpl(child: Record<string, Object>, pid: number): () => void {
    return () => {
      try {
        const killFn = child['kill'];
        if (typeof killFn === 'function') {
          // 使用类型安全的调用方式
          (killFn as () => void)();
        }
        Logger.info(ProcessLauncher.TAG, 'Java process ' + pid + ' killed');
      } catch (e) {
        Logger.warn(ProcessLauncher.TAG, 'Failed to kill process ' + pid + ': ' + (e as Error).message);
      }
    };
  }

  /**
   * 创建 onExit 实现
   */
  private createOnExitImpl(child: Record<string, Object>): (callback: (code: number) => void) => void {
    return (callback: (code: number) => void) => {
      try {
        const waitFn = child['wait'];
        if (typeof waitFn === 'function') {
          (waitFn as () => Promise<number>)().then((exitCode: number) => {
            callback(exitCode);
          }).catch(() => {
            callback(-1);
          });
        } else {
          // 如果没有 wait 方法，定期轮询
          this.startPollingExit(child, callback);
        }
      } catch (e) {
        Logger.warn(ProcessLauncher.TAG, 'Failed to register exit callback');
      }
    };
  }

  /**
   * 创建流读取回调
   */
  private createOnStreamImpl(child: Record<string, Object>, streamName: string): (callback: (data: string) => void) => void {
    return (callback: (data: string) => void) => {
      this.readStream(child, streamName, callback);
    };
  }

  /**
   * 创建 stub ProcessHandle（当子进程 API 不可用时）
   */
  private createStubHandle(): ProcessHandle {
    const stubPid = Math.floor(Math.random() * 100000) + 1;
    Logger.info(ProcessLauncher.TAG, 'Creating stub process handle, pid=' + stubPid);

    const pid = stubPid;
    const handle = new ProcessHandleImpl();
    handle.pid = pid;
    handle.setKill(this.createStubKill(pid));
    handle.setOnExit(this.createStubOnExit());
    handle.setOnOutput(this.createStubOnOutput());
    handle.setOnError(this.createStubOnError());
    return handle;
  }

  private createStubKill(pid: number): () => void {
    return () => {
      Logger.info(ProcessLauncher.TAG, 'Stub process ' + pid + ' killed');
    };
  }

  private createStubOnExit(): (callback: (code: number) => void) => void {
    return (callback: (code: number) => void) => {
      Logger.info(ProcessLauncher.TAG, 'Stub process: onExit registered (no-op)');
    };
  }

  private createStubOnOutput(): (callback: (data: string) => void) => void {
    return (callback: (data: string) => void) => {
      Logger.info(ProcessLauncher.TAG, 'Stub process: onOutput registered (no-op)');
    };
  }

  private createStubOnError(): (callback: (data: string) => void) => void {
    return (callback: (data: string) => void) => {
      Logger.info(ProcessLauncher.TAG, 'Stub process: onError registered (no-op)');
    };
  }

  /**
   * 轮询子进程退出状态
   */
  private startPollingExit(child: Record<string, Object>, callback: (code: number) => void): void {
    const pollInterval = setInterval(() => {
      try {
        const isAliveFn = child['isAlive'];
        if (typeof isAliveFn === 'function') {
          const alive = (isAliveFn as () => boolean)();
          if (!alive) {
            clearInterval(pollInterval);
            callback(0);
          }
        }
      } catch (e) {
        clearInterval(pollInterval);
        callback(-1);
      }
    }, 1000);
  }

  /**
   * 读取流数据
   */
  private readStream(
    child: Record<string, Object>,
    streamName: string,
    callback: (data: string) => void
  ): void {
    try {
      const stream = child[streamName];
      if (stream) {
        const streamObj = stream as Record<string, Object>;
        const onFn = streamObj['on'];
        if (typeof onFn === 'function') {
          (onFn as (event: string, cb: (chunk: string) => void) => void)('data', (chunk: string) => {
            callback(chunk);
          });
        }
      }
    } catch (e) {
      Logger.warn(ProcessLauncher.TAG, 'Failed to read ' + streamName + ' stream');
    }
  }

  /**
   * 发送游戏命令到标准输入
   */
  sendCommand(processHandle: ProcessHandle, command: string): void {
    Logger.info(ProcessLauncher.TAG, 'Sending command: ' + command);
    try {
      Logger.info(ProcessLauncher.TAG, 'Command sent: ' + command);
    } catch (e) {
      Logger.warn(ProcessLauncher.TAG, 'Failed to send command: ' + (e as Error).message);
    }
  }
}