/**
 * JavaManager — Java 运行时管理（对齐 HMCL 的 download/java/ 与 JavaManagementPage）
 *
 * Minecraft 对 Java 版本有硬性要求，选错直接起不来：
 *   MC 1.17+        必须 Java 17
 *   MC 1.18.2~1.20.4 Java 17
 *   MC 1.20.5+       必须 Java 21
 *   MC ≤1.16.5       Java 8
 *   Forge 1.12.2 等老版本 Java 8
 *
 * HMCL 的做法（JavaVersion / JavaManager）：维护一张
 * 「MC 版本 → 所需 Java 主版本」的映射，再据此推荐运行时。
 * 这里实现同一套逻辑，并把结果接到启动链路上。
 */
import { FileUtils, Logger } from '../util/Utils';
import { Constants } from '../../config/Constants';

export interface JdkInfo {
  /** 目录名，如 jdk17 / jdk21 / jdk8 */
  name: string;
  path: string;
  /** 解析出的主版本号，识别不到为 0 */
  majorVersion: number;
  /** 是否内置（随包分发） */
  bundled: boolean;
  /** 是否可删除 */
  removable: boolean;
  /**
   * 是不是完整 JDK。
   * 只有 bin/（含 java 可执行文件）才能启动 Minecraft；
   * 只有 lib/ 的其实是 JRE（运行时），跑不了游戏。
   * 实测内置的 jdk17 / jdk21 就是这种情况，必须在界面上说清楚，
   * 否则用户会以为「装了 Java 17 却起不来」。
   */
  fullJdk: boolean;
}

/** Minecraft 版本 → 所需 Java 主版本 */
export interface JavaRequirement {
  /** 最低 MC 版本（含） */
  fromMc: string;
  /** 最高 MC 版本（含），'' 表示不限 */
  toMc: string;
  /** 所需 Java 主版本 */
  javaMajor: number;
  label: string;
}

export class JavaManager {
  private static readonly TAG = 'JavaManager';

  /**
   * 版本要求表。顺序即优先级（从新到旧）。
   * 依据 Mojang 官方 launcher 与 HMCL 的 JavaVersion 判定。
   */
  static readonly REQUIREMENTS: JavaRequirement[] = [
    { fromMc: '1.20.5', toMc: '', javaMajor: 21, label: 'Minecraft 1.20.5 及以上需要 Java 21' },
    { fromMc: '1.17', toMc: '1.20.4', javaMajor: 17, label: 'Minecraft 1.17 ~ 1.20.4 需要 Java 17' },
    { fromMc: '1.0.0', toMc: '1.16.5', javaMajor: 8, label: 'Minecraft 1.16.5 及以下需要 Java 8' }
  ];

  /** 该 MC 版本需要哪个 Java 主版本 */
  static requiredJavaMajor(mcVersion: string): number {
    const v = JavaManager.parseVersion(mcVersion);
    if (v.length === 0) {
      return 17;
    }
    // 1.20.5+ → 21；1.17~1.20.4 → 17；更早 → 8
    const cmp = JavaManager.compare(v, ['1', '20', '5']);
    if (cmp >= 0) {
      return 21;
    }
    const cmp17 = JavaManager.compare(v, ['1', '17', '0']);
    if (cmp17 >= 0) {
      return 17;
    }
    return 8;
  }

  /** 版本要求的人话说明 */
  static requirementLabel(mcVersion: string): string {
    const major = JavaManager.requiredJavaMajor(mcVersion);
    for (const r of JavaManager.REQUIREMENTS) {
      if (r.javaMajor === major) {
        return r.label;
      }
    }
    return `需要 Java ${major}`;
  }

  /** 从 bin/java 或 release 文件里读主版本号 */
  static probeMajor(jdkPath: string): number {
    // 优先看 release（里面写 JAVA_VERSION="17.0.13"）
    const release = `${jdkPath}/release`;
    if (FileUtils.exists(release)) {
      const text = FileUtils.readFile(release);
      const m = /JAVA_VERSION="([^"]+)"/.exec(text);
      if (m !== null && m.length > 1) {
        const major = parseInt(m[1].split(/[._\-]/)[0], 10);
        if (!isNaN(major)) {
          return major;
        }
      }
    }
    // 目录名兜底：jdk17 / jdk-21 / java-8
    const name = jdkPath.substring(jdkPath.lastIndexOf('/') + 1);
    const dm = /(\d+)/.exec(name);
    if (dm !== null) {
      const n = parseInt(dm[1], 10);
      if (!isNaN(n)) {
        return n;
      }
    }
    return 0;
  }

  /** 扫描已安装的 JDK */
  static scan(jdkRoot: string): JdkInfo[] {
    const out: JdkInfo[] = [];
    if (!FileUtils.exists(jdkRoot)) {
      return out;
    }
    let entries: string[] = [];
    try {
      entries = FileUtils.listDir(jdkRoot);
    } catch (e) {
      return out;
    }
    for (const dir of entries) {
      const full = `${jdkRoot}/${dir}`;
      if (!FileUtils.isDirectory(full)) {
        continue;
      }
      // 至少要有 lib/ 或 bin/ 才算是 Java 运行时目录。
      // 注意：只有 lib/ 而没有 bin/ 的是 JRE，启动 Minecraft 需要 bin/java，
      // 所以这里不丢弃，只标记 fullJdk=false，让界面明确提示。
      const hasBin = FileUtils.exists(`${full}/bin`);
      const hasLib = FileUtils.exists(`${full}/lib`);
      if (!hasBin && !hasLib) {
        continue;
      }
      out.push({
        name: dir,
        path: full,
        majorVersion: JavaManager.probeMajor(full),
        bundled: JavaManager.BUNDLED.indexOf(dir) >= 0,
        removable: JavaManager.BUNDLED.indexOf(dir) < 0,
        fullJdk: hasBin
      });
    }
    out.sort((a: JdkInfo, b: JdkInfo) => b.majorVersion - a.majorVersion);
    return out;
  }

  /** 随包分发的 JDK，不可删 */
  static readonly BUNDLED: string[] = ['jdk8', 'jdk17', 'jdk21'];

  /**
   * 为某个 MC 版本挑选最合适的 JDK。
   * 优先精确匹配所需主版本；其次向上兼容（高版本 JDK 能跑老 MC，但 8 不能跑 17+ 的游戏）。
   */
  static pickFor(jdks: JdkInfo[], mcVersion: string): JdkInfo | null {
    if (jdks.length === 0) {
      return null;
    }
    // ⚠️ 只考虑完整 JDK：JRE 没有 bin/java，启动不了 Minecraft。
    const usable: JdkInfo[] = [];
    for (const j of jdks) {
      if (j.fullJdk) {
        usable.push(j);
      }
    }
    if (usable.length === 0) {
      const msg = '没有可用的完整 JDK（现有 ' + jdks.length +
        ' 个目录都不是完整 JDK），Minecraft 需要带 bin/java 的 JDK';
      Logger.warn(JavaManager.TAG, msg);
      return null;
    }
    const need = JavaManager.requiredJavaMajor(mcVersion);
    // 1. 精确匹配
    for (const j of usable) {
      if (j.majorVersion === need) {
        return j;
      }
    }
    // 2. 同代向上取（需要 8 而只有 17/21 → 可以跑；需要 21 而只有 17 → 不行）
    if (need === 8) {
      for (const j of usable) {
        if (j.majorVersion >= 8) {
          return j;
        }
      }
    }
    // 3. 识别不出主版本时取最大的
    for (const j of usable) {
      if (j.majorVersion === 0) {
        return j;
      }
    }
    return null;
  }

  /** java 可执行文件路径（鸿蒙上 java 也可能是脚本） */
  static javaBin(jdkPath: string): string {
    return `${jdkPath}/bin/java`;
  }

  /** JVM 主类入口（鸿蒙 OpenJDK 发行版仍是 java.lang） */
  static mainClass(): string {
    return 'net.minecraft.client.main.Main';
  }

  private static parseVersion(v: string): string[] {
    // "1.20.4" → ["1","20","4"]；"26.3-snapshot" → ["26","3"]
    const cleaned = v.split('-')[0];
    const parts = cleaned.split('.');
    const out: string[] = [];
    for (const p of parts) {
      const n = parseInt(p, 10);
      out.push(isNaN(n) ? '0' : n.toString());
    }
    return out;
  }

  /** 逐段比较两个版本数组 */
  private static compare(a: string[], b: string[]): number {
    const len = Math.max(a.length, b.length);
    for (let i = 0; i < len; i++) {
      const x = parseInt(a.length > i ? a[i] : '0', 10);
      const y = parseInt(b.length > i ? b[i] : '0', 10);
      if (x > y) {
        return 1;
      }
      if (x < y) {
        return -1;
      }
    }
    return 0;
  }

  /** JDK 根目录 */
  static root(baseDir: string): string {
    return `${baseDir}/${Constants.JDK_DIR}`;
  }
}
