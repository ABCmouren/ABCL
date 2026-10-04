/**
 * FileExchange — 把 .minecraft 目录「打开」给用户看
 *
 * 需求：用户想用文件管理器/电脑访问 .minecraft。
 *
 * 鸿蒙的限制（查过本地 SDK）：
 *   - 没有「用系统文件管理器打开指定目录」的 API
 *     DocumentViewPicker 只能让用户【选】目录，不能被动打开；
 *     want 也无法跳到某个沙箱路径（沙箱对外不可见）。
 *   - 所以唯一可行的做法是「把目录导出到用户可见的位置」。
 *
 * 这里提供三个方向，与 HMCL 的「打开目录 / 导出整合包 / 导入整合包」对应：
 *   exportGameDir()   整个 .minecraft 打成 zip，交给用户选位置保存
 *   importFromPicker()用户选一个 zip 进来，解包合并回 .minecraft
 *   chooseGameDir()    让用户直接挑一个外部目录作为游戏目录
 */
import { picker } from '@kit.CoreFileKit';
import { ArchiveUtils, FileUtils, Logger } from '../util/Utils';

export class FileExchange {
  private static readonly TAG = 'FileExchange';

  /**
   * 导出整个游戏目录。
   * @param srcDir .minecraft 目录
   * @param defaultName 默认文件名，如 ABCL-minecraft-20261004.zip
   * @returns 成功返回保存后的 uri，失败返回空串
   */
  static async exportGameDir(srcDir: string, defaultName: string): Promise<string> {
    if (!FileUtils.exists(srcDir)) {
      Logger.warn(FileExchange.TAG, `目录不存在：${srcDir}`);
      return '';
    }
    // 先在沙箱内打包，再让用户选保存位置
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
      // 系统只给了目标 uri，我们自己写内容
      const written = await FileExchange.copyToUri(stage, uris[0]);
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
      // 取第一个取回内容（picker 给的是 uri，需要通过 fs 按 uri 读）
      const src = uris[0];
      Logger.info(FileExchange.TAG, `用户选择了 ${src}`);
      const target = `${stageDir}/import-${Date.now()}.zip`;
      FileUtils.delete(target);
      const ok = FileUtils.copyFromUri(src, target);
      if (!ok) {
        Logger.error(FileExchange.TAG, '读取所选文件失败');
        return '';
      }
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

  /** 把沙箱内文件写到用户选择的 uri */
  private static async copyToUri(srcPath: string, dstUri: string): Promise<boolean> {
    try {
      const data = FileUtils.readFileBytes(srcPath);
      if (data === null) {
        return false;
      }
      FileUtils.writeBytesToUri(dstUri, data);
      return true;
    } catch (e) {
      Logger.error(FileExchange.TAG, `写入 ${dstUri} 失败: ${(e as Error).message}`);
      return false;
    }
  }
}
