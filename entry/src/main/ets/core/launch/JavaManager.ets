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
   * 是否具备启动 Minecraft 的条件。
   *
   * ⚠️ 这里踩过一个坑，值得写清楚：
   * 我原来用「有没有 bin/java 可执行文件」判定，把内置 jdk17 / jdk21
   * 判成了「仅 JRE，不可启动游戏」。这是错的。
   *
   * 实际情况（核对 mc-ohos-resources 发布的 zip 后）：
   *   jdk17-ohos-full-v5.zip → 72 个条目，顶层只有 conf / lib / release
   *   jdk21-ohos-full-v7.zip → 82 个条目，同样
   *   jdk8-ohos-full-v4.zip  → 126 个条目，顶层 jre/，含 jre/bin/java
   *
   * 但前两者内部其实很完整：
   *   lib/modules（122~134 MB，JVM 的全部核心类）
   *   lib/server/libjvm.so（22~24 MB，JVM 本体）
   *   lib/libjava.so / libjava.so 等原生库
   * 也就是说「运行时」是全的，只是没带 bin/java 这个启动器程序。
   * 在 ARM + 鸿蒙上，启动器本来就要由我们的 native 层
   * dlopen libjvm.so 并自己调 JNI_CreateJavaVM（见 cpp/java_tool.cpp），
   * 本来就不依赖 bin/java。
   *
   * 所以判定标准改为：有没有 lib/modules 或 libjvm.so。
   */
  usable: boolean;
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

  /**
   * 读主版本号。
   * 优先看 release 文件（里面写 JAVA_VERSION="17.0.13"），
   * 读不到再从目录名兜底（jdk17 / jdk-21 / java-8）。
   */
  static probeMajor(jdkPath: string): number {
    const release = `${jdkPath}/release`;
    if (FileUtils.exists(release)) {
      try {
        const text = FileUtils.readFile(release);
        const m = /JAVA_VERSION="([^"]+)"/.exec(text);
        if (m !== null && m.length > 1) {
          const major = parseInt(m[1].split(/[._\-]/)[0], 10);
          if (!isNaN(major)) {
            return major;
          }
        }
      } catch (e) {
        // release 读不到就退化到目录名
      }
    }
    // jdk8 的结构是 jdk8/jre/release
    const nested = `${jdkPath}/jre/release`;
    if (FileUtils.exists(nested)) {
      try {
        const text = FileUtils.readFile(nested);
        const m = /JAVA_VERSION="([^"]+)"/.exec(text);
        if (m !== null && m.length > 1) {
          const major = parseInt(m[1].split(/[._\-]/)[0], 10);
          if (!isNaN(major)) {
            return major;
          }
        }
      } catch (e) {
      }
    }
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
      // 判定能否启动 Minecraft：需要 lib/modules（JVM 的全部核心类）
      // 或 libjvm.so（JVM 本体）。不要求 bin/java ——
      // 我们用 native dlopen libjvm.so + JNI_CreateJavaVM 启动（见 cpp/java_tool.cpp），
      // 本来就不经过 java 可执行文件。
      //
      // ⚠️ libjvm.so 的位置各版本不同，必须逐个位置试：
      //   jdk17/21: lib/server/libjvm.so、lib/libjvm.so
      //   jdk8:     lib/<arch>/server/libjvm.so（带架构目录层级），
      //            可能是 jdk8/lib/... 也可能是 jdk8/jre/lib/...
      const hasModules = FileUtils.exists(`${full}/lib/modules`);
      const hasJvm = JavaManager.hasLibJvm(full);
      const hasLib = FileUtils.exists(`${full}/lib`) || FileUtils.exists(`${full}/jre/lib`);
      if (!hasModules && !hasJvm && !hasLib) {
        continue;
      }
      out.push({
        name: dir,
        path: full,
        majorVersion: JavaManager.probeMajor(full),
        bundled: JavaManager.BUNDLED.indexOf(dir) >= 0,
        removable: JavaManager.BUNDLED.indexOf(dir) < 0,
        usable: hasModules || hasJvm
      });
    }
    out.sort((a: JdkInfo, b: JdkInfo) => b.majorVersion - a.majorVersion);
    return out;
  }

  /** 随包分发的 JDK，不可删 */
  static readonly BUNDLED: string[] = ['jdk8', 'jdk17', 'jdk21'];

  /**
   * libjvm.so 在各版本里的位置不统一，逐个探测：
   *   jdk17/21 → lib/server/libjvm.so 或 lib/libjvm.so
   *   jdk8     → lib/aarch64/server/libjvm.so、lib/<arch>/server/libjvm.so
   *              （且可能在 jdk8/lib 下，也可能在 jdk8/jre/lib 下）
   */
  static hasLibJvm(jdkPath: string): boolean {
    const candidates: string[] = [
      `${jdkPath}/lib/server/libjvm.so`,
      `${jdkPath}/lib/libjvm.so`,
      `${jdkPath}/jre/lib/server/libjvm.so`,
      `${jdkPath}/jre/lib/aarch64/server/libjvm.so`,
      `${jdkPath}/jre/lib/arm64-v8a/server/libjvm.so`,
      `${jdkPath}/lib/aarch64/server/libjvm.so`,
      `${jdkPath}/lib/arm64-v8a/server/libjvm.so`
    ];
    for (const c of candidates) {
      if (FileUtils.exists(c)) {
        return true;
      }
    }
    // 再兜底扫一层架构目录（未来可能有别的架构）
    for (const arch of ['aarch64', 'arm64-v8a', 'x86_64']) {
      if (FileUtils.exists(`${jdkPath}/lib/${arch}/server/libjvm.so`) ||
        FileUtils.exists(`${jdkPath}/jre/lib/${arch}/server/libjvm.so`)) {
        return true;
      }
    }
    return false;
  }

  /** 定位 libjvm.so 的实际路径（启动时 dlopen 要用） */
  static findLibJvm(jdkPath: string): string {
    const candidates: string[] = [
      `${jdkPath}/lib/server/libjvm.so`,
      `${jdkPath}/lib/libjvm.so`,
      `${jdkPath}/jre/lib/server/libjvm.so`,
      `${jdkPath}/jre/lib/aarch64/server/libjvm.so`,
      `${jdkPath}/jre/lib/arm64-v8a/server/libjvm.so`,
      `${jdkPath}/lib/aarch64/server/libjvm.so`,
      `${jdkPath}/lib/arm64-v8a/server/libjvm.so`
    ];
    for (const c of candidates) {
      if (FileUtils.exists(c)) {
        return c;
      }
    }
    for (const arch of ['aarch64', 'arm64-v8a', 'x86_64']) {
      const a = `${jdkPath}/lib/${arch}/server/libjvm.so`;
      const b = `${jdkPath}/jre/lib/${arch}/server/libjvm.so`;
      if (FileUtils.exists(a)) {
        return a;
      }
      if (FileUtils.exists(b)) {
        return b;
      }
    }
    return '';
  }

  /**
   * 为某个 MC 版本挑选最合适的 JDK。
   * 优先精确匹配所需主版本；其次向上兼容（高版本 JDK 能跑老 MC，但 8 不能跑 17+ 的游戏）。
   */
  static pickFor(jdks: JdkInfo[], mcVersion: string): JdkInfo | null {
    if (jdks.length === 0) {
      return null;
    }
    // 只考虑可用（有 lib/modules 或 libjvm.so）的运行时
    const usable: JdkInfo[] = [];
    for (const j of jdks) {
      if (j.usable) {
        usable.push(j);
      }
    }
    if (usable.length === 0) {
      const msg = '没有可用的 Java 运行时（现有 ' + jdks.length +
        ' 个目录都缺少 lib/modules 或 libjvm.so）';
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

  /**
   * java 可执行文件路径。
   * 仅用于展示/兜底 —— 实际启动走 native dlopen libjvm.so。
   */
  static javaBin(jdkPath: string): string {
    const direct = `${jdkPath}/bin/java`;
    if (FileUtils.exists(direct)) {
      return direct;
    }
    return `${jdkPath}/jre/bin/java`;
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
