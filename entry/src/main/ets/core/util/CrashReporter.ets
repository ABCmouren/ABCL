/**
 * CrashReporter — 崩溃报告（对齐 HMCL 的 CrashWindow / GameCrashWindow）
 *
 * 两个来源：
 *   1. 启动器自身异常：EntryAbility 未捕获的 ArkTS 异常
 *   2. 游戏崩溃：<gameDir>/crash-reports/crash-YYYY-MM-DD_HH.mmss-client.txt
 *      （Minecraft 自己写的崩溃报告）
 *
 * HMCL 的做法是全局 ExceptionHandler + 独立窗口；
 * 这里用「收集 → 统一展示」的方式，够用且不侵入启动流程。
 */
import { FileUtils, Logger, StringUtils } from './Utils';

export interface CrashEntry {
  /** 来源：launcher / game */
  source: string;
  /** 时间戳文本 */
  time: string;
  /** 文件名或异常摘要 */
  title: string;
  /** 全文 */
  content: string;
}

export class CrashReporter {
  private static readonly TAG = 'CrashReporter';
  /** 启动器自身未捕获的异常 */
  private static appCrashes: string[] = [];

  /** 记录一个启动器异常 */
  static recordAppCrash(message: string): void {
    const ts = new Date().toISOString();
    CrashReporter.appCrashes.push(`[${ts}] ${message}`);
    Logger.error(CrashReporter.TAG, '未捕获异常: ' + message);
  }

  /** 读取游戏的崩溃报告（crash-reports/） */
  static readGameCrashes(gameDir: string): CrashEntry[] {
    const out: CrashEntry[] = [];
    const dir = gameDir + '/crash-reports';
    if (!FileUtils.exists(dir)) {
      return out;
    }
    let files: string[] = [];
    try {
      files = FileUtils.listDir(dir)
        .filter((f: string) => f.endsWith('.txt'))
        .sort()
        .reverse();
    } catch (e) {
      return out;
    }
    for (const f of files.slice(0, 20)) {
      try {
        out.push({
          source: 'game',
          time: CrashReporter.timeFromName(f),
          title: f,
          content: FileUtils.readFile(dir + '/' + f)
        });
      } catch (e) {
        Logger.warn(CrashReporter.TAG, '读取崩溃报告失败: ' + f);
      }
    }
    return out;
  }

  /** 合并两个来源 */
  static collect(gameDir: string): CrashEntry[] {
    const app: CrashEntry[] = [];
    for (const msg of CrashReporter.appCrashes) {
      app.push({
        source: 'launcher',
        time: msg.substring(1, 20),
        title: msg.substring(22),
        content: msg
      });
    }
    return app.concat(CrashReporter.readGameCrashes(gameDir));
  }

  static hasAny(gameDir: string): boolean {
    return CrashReporter.appCrashes.length > 0 ||
      CrashReporter.readGameCrashes(gameDir).length > 0;
  }

  static clearAppCrashes(): void {
    CrashReporter.appCrashes = [];
  }

  /** 从 crash-2026-10-04_17.30.12-client.txt 里抽出时间 */
  private static timeFromName(name: string): string {
    // crash-2026-10-04_17.30.12-client.txt
    const m = /crash-([\d-]+)_([\d.]+)-/.exec(name);
    if (m !== null && m.length > 2) {
      return m[1] + ' ' + m[2];
    }
    return name;
  }

  /** 提取崩溃报告里最关键的几行（异常类型 + 堆栈首行） */
  static summarize(content: string): string {
    const lines = content.split('\n');
    const out: string[] = [];
    let depth = 0;
    for (const raw of lines) {
      const line = raw.trim();
      if (line.length === 0) {
        continue;
      }
      // 找到 Description / Exception / Caused by 之类的关键行
      if (line.startsWith('Description:') || line.startsWith('Exception:') ||
        line.startsWith('Caused by:') || line.startsWith('java.lang.') ||
        line.startsWith('at ') || line.startsWith('Time:')) {
        out.push(line.length > 200 ? line.substring(0, 200) : line);
      }
      depth++;
      if (depth > 400) {
        break;
      }
    }
    if (out.length === 0) {
      return content.substring(0, 300);
    }
    return out.slice(0, 12).join('\n');
  }

  static sizeLabel(bytes: number): string {
    return StringUtils.formatSize(bytes);
  }
}
