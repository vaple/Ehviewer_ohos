import { common } from '@kit.AbilityKit';
import { fileIo, storageStatistics } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';

/** 存储占用明细（`BundleStats` 的四个数值，与系统「设置-存储-应用」同口径）。 */
export interface BundleStorage {
  /** 应用安装文件大小（`/data/storage/el1/bundle`）。 */
  appSize: number;
  /** 应用文件存储大小（除安装文件）。缓存目录是它的子目录。 */
  dataSize: number;
  /**
   * 缓存文件大小（`.../base/cache` 与 `.../base/haps/<module>/cache`）——**已包含在 `dataSize` 里**。
   */
  cacheSize: number;
  /** 总计 = `appSize + dataSize`（官方 FAQ 口径：缓存不重复计入）。 */
  totalSize: number;
}

/**
 * 应用存储占用与缓存清理（官方 API）：
 * - 统计：`storageStatistics.getCurrentBundleStats()`（字节；与系统「设置-存储-应用」同口径）。
 * - 清理：`context.cacheDir` 下的内容逐个删除。**模块级与应用级 Context 都要清**
 *   （官方 FAQ `faqs-local-file-manager-12`：只清一个会残留另一份缓存）。
 */
export class CacheManager {
  /** 当前应用的存储占用明细（系统「设置-存储」同口径）。 */
  static async stats(): Promise<BundleStorage> {
    const stats: storageStatistics.BundleStats = await storageStatistics.getCurrentBundleStats();
    const result: BundleStorage = {
      appSize: stats.appSize,
      dataSize: stats.dataSize,
      cacheSize: stats.cacheSize,
      totalSize: stats.appSize + stats.dataSize
    };
    return result;
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
