/**
 * FileExchange — 文件目录交换（打开 / 导入 / 导出）
 *
 * ⚠️ 关于「打开文件夹」的结论修正：
 * 上一轮我判断「鸿蒙没有用文件管理器打开目录的接口，只能打包 zip」——
 * 那是错的，只查了 DocumentViewPicker 就下了结论。
 *
 * 正确做法是用 want 拉起系统文件管理器并带上路径参数。实测可用：
 *   bundle:  com.huawei.hmos.filemanager
 *   ability: MainAbility
 *   参数名:  fileUri（实测 uri / filePath 都不生效，只有 fileUri 有效）
 *   值:      file://bundle/<本应用包名>/haps/entry/files/...
 *
 * 设备实测：跳转后文件管理器路径栏显示「个人 | entry | files」，
 * 说明沙箱目录是可以被文件管理器浏览的（HarmonyOS 会通过「来自其他应用」
 * 的方式授权访问）。
 *
 * 所以这里提供三种能力：
 *   openInFileManager()   跳文件管理器并定位到指定目录 —— 这才是「打开文件夹」
 *   exportGameDir()       整个 .minecraft 打包导出（备份 / 分享给别人）
 *   importFromPicker()    选 zip 导入
 */
import { common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { ArchiveUtils, FileUtils, Logger } from './Utils';

export class FileExchange {
  private static readonly TAG = 'FileExchange';

  /** 系统文件管理器（鸿蒙自带） */
  private static readonly FM_BUNDLE = 'com.huawei.hmos.filemanager';
  private static readonly FM_ABILITY = 'MainAbility';

  /**
   * 跳到系统文件管理器并定位到目标目录。
   *
   * 把沙箱路径转成 file://bundle/<包名>/haps/entry/files/... 形式 ——
   * 沙箱路径（/data/storage/el2/base/...）在文件管理器里不认，
   * 必须用 bundle 形式的 fileUri。
   *
   * @param context UIAbilityContext（要拿它调 startAbility）
   * @param sandboxPath 沙箱内绝对路径，如 /data/storage/el2/base/haps/entry/files/minecraft
   * @param bundleName 本应用包名
   * @returns 是否成功发起跳转
   */
  static async openInFileManager(
    context: common.UIAbilityContext,
    sandboxPath: string,
    bundleName: string
  ): Promise<boolean> {
    const uri = FileExchange.toFileUri(sandboxPath, bundleName);
    if (uri.length === 0) {
      Logger.warn(FileExchange.TAG, `无法转换路径：${sandboxPath}`);
      return false;
    }
    const wantObj: Want = {
      bundleName: FileExchange.FM_BUNDLE,
      abilityName: FileExchange.FM_ABILITY,
      parameters: {
        'fileUri': uri
      }
    };
    try {
      await context.startAbility(wantObj);
      Logger.info(FileExchange.TAG, `已跳转文件管理器：${uri}`);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      Logger.error(FileExchange.TAG, `跳转文件管理器失败: ${err.message}`);
      return false;
    }
  }

  /**
   * 沙箱路径 → fileUri。
   *
   * /data/app/el2/100/base/<bundle>/haps/entry/files/X
   *   → file://bundle/<bundle>/haps/entry/files/X
   * /data/storage/el2/base/haps/entry/files/X（context.filesDir 返回的）
   *   → file://bundle/<bundle>/haps/entry/files/X
   */
  static toFileUri(sandboxPath: string, bundleName: string): string {
    if (sandboxPath.length === 0) {
      return '';
    }
    const marker = 'haps/entry/files';
    const idx = sandboxPath.indexOf(marker);
    if (idx < 0) {
      // 不在沙箱里（自定义目录），直接给原路径
      return `file://${sandboxPath.startsWith('/') ? '' : '/'}${sandboxPath}`;
    }
    return `file://bundle/${bundleName}/${sandboxPath.substring(idx)}`;
  }

  /**
   * 导出整个游戏目录。
   * 与「打开文件夹」不同：这是给备份 / 分享用的。
   */
  static async exportGameDir(srcDir: string, defaultName: string): Promise<string> {
    if (!FileUtils.exists(srcDir)) {
      Logger.warn(FileExchange.TAG, `目录不存在：${srcDir}`);
      return '';
    }
    const stage = `${srcDir}/.export-tmp/${defaultName}`;
    try {
      FileUtils.mkdirs(`${srcDir}/.export-tmp`);
      const ok = await ArchiveUtils.zipDir(srcDir, stage);
      if (!ok) {
        Logger.error(FileExchange.TAG, '打包游戏目录失败');
        return '';
      }
      Logger.info(FileExchange.TAG, `已打包 ${stage}`);

      const view = new picker.DocumentViewPicker();
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [defaultName];
      const uris = await view.save(options);
      if (uris === undefined || uris.length === 0) {
        Logger.info(FileExchange.TAG, '用户取消了保存');
        return '';
      }
      const data = FileUtils.readFileBytes(stage);
      if (data === null) {
        return '';
      }
      const written = FileUtils.writeBytesToUri(uris[0], data);
      Logger.info(FileExchange.TAG, written ? `已导出到 ${uris[0]}` : '写入目标失败');
      return written ? uris[0] : '';
    } catch (e) {
      Logger.error(FileExchange.TAG, `导出游戏目录失败: ${(e as Error).message}`);
      return '';
    } finally {
      FileUtils.delete(`${srcDir}/.export-tmp`);
    }
  }

  /** 让用户选一个 zip 导入（返回本地沙箱路径，空串表示取消） */
  static async importFromPicker(stageDir: string): Promise<string> {
    try {
      FileUtils.mkdirs(stageDir);
      const view = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.zip'];
      const uris = await view.select(options);
      if (uris === undefined || uris.length === 0) {
        return '';
      }
      const target = `${stageDir}/import-${Date.now()}.zip`;
      FileUtils.delete(target);
      const ok = FileUtils.copyFromUri(uris[0], target);
      if (!ok) {
        Logger.error(FileExchange.TAG, '读取所选文件失败');
        return '';
      }
      Logger.info(FileExchange.TAG, `已取回 ${target}`);
      return target;
    } catch (e) {
      Logger.error(FileExchange.TAG, `导入失败: ${(e as Error).message}`);
      return '';
    }
  }

  /** 让用户挑一个外部目录作为游戏目录（返回路径，空串表示取消） */
  static async chooseGameDir(): Promise<string> {
    try {
      const view = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await view.select(options);
      if (uris === undefined || uris.length === 0) {
        return '';
      }
      return uris[0];
    } catch (e) {
      Logger.error(FileExchange.TAG, `选择目录失败: ${(e as Error).message}`);
      return '';
    }
  }
}
