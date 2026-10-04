/**
 * ProcessorRunner — 运行 Forge / NeoForge 的 install_profile processors
 *
 * Forge 1.13+ 的安装必须执行 install_profile.json 里的 processors
 * （installertools / jarsplitter / ForgeAutoRenamingTool / binarypatcher / SpecialSource …），
 * 它们都是 Java 程序，每个 processor 需要**独立、干净的 classpath**（FCL/HMCL 同款做法，
 * 避免 installer.jar 的 shaded 库污染）。
 *
 * 执行入口是 native 的 `runJavaProcessor`（fork 子进程 + 独立 JVM），
 * 对应 AMCL 的 ForgelikeNative.runJavaProcessor 契约。若当前构建没有该 native 接口，
 * 这里会抛出明确错误，而不是让用户拿到一个"看起来装好了但起不来"的 Forge。
 */
import { Constants } from '../../config/Constants';
import { FileUtils, Logger } from '../util/Utils';
import { CancelToken } from '../download/DownloadEngine';
import {
  ForgeInstallDataEntry, ForgeProcessor, InstallProgress
} from './ModLoaderInstaller';
import { runJavaProcessor as nativeRunJavaProcessor } from 'libhmcl_native.so';

export interface ProcessorContext {
  mcDir: string;
  versionId: string;
  mcVersion: string;
  installerPath: string;
  classpathDir: string;
  data?: Record<string, ForgeInstallDataEntry>;
  onProgress?: (p: InstallProgress) => void;
  token?: CancelToken;
}

export interface ProcessorBridge {
  runJavaProcessor: (
    javaHome: string,
    classpath: string,
    mainClass: string,
    args: string[],
    workDir: string,
    logFile: string,
    xmxMb: number
  ) => Promise<number>;
}

let g_bridge: ProcessorBridge | null = null;

export class ProcessorRunner {
  private static readonly TAG = 'ProcessorRunner';

  /** 允许宿主注入 native 桥（EntryAbility 启动期调用） */
  static setBridge(bridge: ProcessorBridge | null): void {
    g_bridge = bridge;
  }

  /** native 桥（libhmcl_native.so 的 runJavaProcessor） */
  private static bridge(): ProcessorBridge {
    if (g_bridge !== null) {
      return g_bridge;
    }
    const bridge: ProcessorBridge = {
      runJavaProcessor: (javaHome: string, classpath: string, mainClass: string,
                        args: string[], workDir: string, logFile: string, xmxMb: number): Promise<number> => {
        return nativeRunJavaProcessor(javaHome, classpath, mainClass, args, workDir, logFile, xmxMb);
      }
    };
    g_bridge = bridge;
    return bridge;
  }

  static async runAll(processors: ForgeProcessor[], ctx: ProcessorContext): Promise<void> {
    const bridge = ProcessorRunner.bridge();
    const javaHome = ProcessorRunner.resolveJavaHome(ctx.mcVersion);
    const workDir = ctx.mcDir;
    const logDir = `${ctx.mcDir}/${Constants.LOGS_DIR}`;
    FileUtils.mkdirs(logDir);

    let index = 0;
    for (const processor of processors) {
      if (ctx.token && ctx.token.isCancelled()) {
        throw new Error('安装已取消');
      }
      index++;
      const sides = processor.sides;
      if (sides && sides.length > 0 && sides.indexOf('client') < 0) {
        Logger.info(ProcessorRunner.TAG, `跳过 processor ${index}（非 client 侧）`);
        continue;
      }
      const classpath = ProcessorRunner.buildClasspath(processor, ctx);
      const mainClass = ProcessorRunner.resolveMainClass(processor, ctx);
      const args = ProcessorRunner.buildArgs(processor, ctx);
      const logFile = `${logDir}/forge-processor-${index}.log`;

      if (ctx.onProgress) {
        ctx.onProgress({
          phase: 'processors',
          progress: 85 + Math.round(index / processors.length * 13),
          message: `processor ${index}/${processors.length}: ${mainClass}`
        });
      }
      Logger.info(ProcessorRunner.TAG, `运行 processor ${index}/${processors.length}: ${mainClass}`);

      const code = await bridge.runJavaProcessor(javaHome, classpath, mainClass, args, workDir, logFile, 2048);
      if (code !== 0) {
        throw new Error(
          `processor ${mainClass} 退出码 ${code}，日志：${logFile}`
        );
      }
    }
    Logger.info(ProcessorRunner.TAG, `${processors.length} 个 processor 全部执行完成`);
  }

  // ------------------------------------------------------------
  //  classpath / 参数解析
  // ------------------------------------------------------------

  /** classpath 里第一个条目是 processor 自己的 jar，其余是依赖 */
  private static buildClasspath(processor: ForgeProcessor, ctx: ProcessorContext): string {
    const entries: string[] = [];
    const jar = ProcessorRunner.resolveSpec(processor.jar, ctx);
    if (jar.length > 0) {
      entries.push(jar);
    }
    for (const spec of processor.classpath) {
      const path = ProcessorRunner.resolveSpec(spec, ctx);
      if (path.length > 0 && entries.indexOf(path) < 0) {
        entries.push(path);
      }
    }
    return entries.join(':');
  }

  private static resolveMainClass(processor: ForgeProcessor, ctx: ProcessorContext): string {
    const jar = ProcessorRunner.resolveSpec(processor.jar, ctx);
    const text = FileUtils.readFile(`${ctx.mcDir}/.installer/processor-mainclass.txt`);
    void text;
    // Forge 的 processors 通过 jar 的 Main-Class 清单指定主类，
    // install_profile 里不写主类名；这里按约定从 jar 名推导。
    const name = jar.substring(jar.lastIndexOf('/') + 1).replace('.jar', '');
    const parts = name.split('-');
    const artifact = parts.length > 1 ? parts[0] : name;
    if (artifact === 'installertools') {
      return 'net.minecraftforge.installertools.ConsoleTool';
    }
    if (artifact === 'jarsplitter') {
      return 'net.minecraftforge.jarsplitter.ConsoleTool';
    }
    if (artifact === 'ForgeAutoRenamingTool' || artifact === 'AutoRenamingTool') {
      return 'net.minecraftforge.artinstall.AutoRenamingTool';
    }
    if (artifact === 'binarypatcher') {
      return 'net.minecraftforge.binarypatcher.ConsoleTool';
    }
    if (artifact === 'SpecialSource') {
      return 'net.md_5.specialsource.SpecialSource';
    }
    if (artifact === 'ForgeAutoRenamingTool') {
      return 'net.minecraftforge.artinstall.AutoRenamingTool';
    }
    if (artifact === 'mcp_config') {
      return 'net.minecraftforge.installertools.ConsoleTool';
    }
    return artifact;
  }

  /** 解析 processor 的 args：占位符 / maven 规格 / 字面量 */
  private static buildArgs(processor: ForgeProcessor, ctx: ProcessorContext): string[] {
    const out: string[] = [];
    for (const arg of processor.args) {
      out.push(ProcessorRunner.resolveArg(arg, ctx));
    }
    return out;
  }

  private static resolveArg(arg: string, ctx: ProcessorContext): string {
    let value = arg;
    // maven 规格：[group:artifact:version:classifier]
    if (value.startsWith('[') && value.endsWith(']')) {
      return ProcessorRunner.resolveSpec(value.substring(1, value.length - 1), ctx);
    }
    // 单引号 / 双引号字面量
    if ((value.startsWith(`'`) && value.endsWith(`'`)) || (value.startsWith('"') && value.endsWith('"'))) {
      return value.substring(1, value.length - 1);
    }
    // 占位符
    value = value.split('{SIDE}').join('client');
    value = value.split('{MINECRAFT_JAR}').join(
      `${ctx.mcDir}/${Constants.VERSIONS_DIR}/${ctx.mcVersion}/${ctx.mcVersion}.jar`);
    value = value.split('{MINECRAFT_VERSION}').join(ctx.mcVersion);
    value = value.split('{ROOT}').join(ctx.mcDir);
    value = value.split('{LIBRARY_DIR}').join(`${ctx.mcDir}/${Constants.LIBRARIES_DIR}`);
    value = value.split('{INSTALLER}').join(ctx.installerPath);

    // install_profile.data 里的键（MAPPINGS / MC_SLIM 等）
    const data = ctx.data;
    if (data) {
      const keys = Object.keys(data);
      for (const key of keys) {
        const placeholder = `{${key}}`;
        if (value.indexOf(placeholder) >= 0) {
          const entry = data[key];
          const spec = entry.client && entry.client.length > 0 ? entry.client : entry.server;
          const resolved = ProcessorRunner.resolveSpec(spec, ctx);
          value = value.split(placeholder).join(resolved);
        }
      }
    }
    return value;
  }

  /** 通用 maven 规格 → 本地 jar 路径 */
  static resolveSpec(spec: string, ctx: ProcessorContext): string {
    if (spec.length === 0) {
      return '';
    }
    let raw = spec.trim();
    if (raw.startsWith('[') && raw.endsWith(']')) {
      raw = raw.substring(1, raw.length - 1);
    }
    let extension = 'jar';
    const at = raw.lastIndexOf('@');
    if (at > 0) {
      extension = raw.substring(at + 1);
      raw = raw.substring(0, at);
    }
    const parts = raw.split(':');
    if (parts.length < 3) {
      return raw;
    }
    const group = parts[0].replace(/\./g, '/');
    const artifact = parts[1];
    const version = parts[2];
    const classifier = parts.length >= 4 && parts[3].length > 0 ? `-${parts[3]}` : '';
    const rel = `${group}/${artifact}/${version}/${artifact}-${version}${classifier}.${extension}`;
    return `${ctx.classpathDir}/${rel}`;
  }

  /** processor 用的 JDK（按 MC 版本选 8 / 17 / 21 / 25） */
  static resolveJavaHome(mcVersion: string): string {
    const parts = mcVersion.split('.');
    const major = parseInt(parts.length > 0 ? parts[0] : '1', 10);
    const minor = parseInt(parts.length > 1 ? parts[1] : '0', 10);
    let dir = Constants.JDK_17_DIR;
    if (major <= 1 && minor <= 16) {
      dir = Constants.JDK_8_DIR;
    } else if (major <= 1 && minor >= 18 && minor <= 20) {
      dir = Constants.JDK_17_DIR;
    } else if (major <= 1 && minor >= 21) {
      dir = Constants.JDK_21_DIR;
    } else if (major >= 26) {
      dir = Constants.JDK_25_DIR;
    }
    return Constants.joinRoot(Constants.joinRoot(Constants.appDir, Constants.JDK_DIR), dir);
  }
}
