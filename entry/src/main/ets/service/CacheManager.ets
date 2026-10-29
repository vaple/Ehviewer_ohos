import { common } from '@kit.AbilityKit';
import { fileIo, storageStatistics } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';

/**
 * 应用缓存统计与清理（官方 API）：
 * - 统计：`storageStatistics.getCurrentBundleStats()` → `cacheSize`（字节；与系统「设置-存储」同口径）。
 * - 清理：`context.cacheDir` 下的内容逐个删除。**模块级与应用级 Context 都要清**
 *   （官方 FAQ `faqs-local-file-manager-12`：只清一个会残留另一份缓存）。
 */
export class CacheManager {
  /** 当前应用缓存大小（字节）。 */
  static async cacheSize(): Promise<number> {
    const stats: storageStatistics.BundleStats = await storageStatistics.getCurrentBundleStats();
    return stats.cacheSize;
  }

  /** 清空模块级 + 应用级缓存目录的内容（保留目录本身）；任一失败向上抛。 */
  static async clear(context: common.Context): Promise<void> {
    await CacheManager.clearDir(context.cacheDir);
    const appCacheDir: string = context.getApplicationContext().cacheDir;
    if (appCacheDir !== context.cacheDir) {
      await CacheManager.clearDir(appCacheDir);
    }
  }

  private static async clearDir(dir: string): Promise<void> {
    const names: string[] = await fileIo.listFile(dir);
    for (let i = 0; i < names.length; i++) {
      const path: string = `${dir}/${names[i]}`;
      try {
        if (fileIo.statSync(path).isDirectory()) {
          fileIo.rmdirSync(path);
        } else {
          fileIo.unlinkSync(path);
        }
      } catch (e) {
        Logger.error('Cache', `clear ${path} failed: ${e}`);
        throw new Error(`clear ${path} failed`);
      }
    }
  }
}
