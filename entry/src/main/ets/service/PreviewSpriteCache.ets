import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ImageStore } from './ImageStore';
import { EhClient } from '../network/EhClient';

/** 裁剪缓存上限（单格约 200×300×4B；跨画廊切换时整清）。 */
const MAX_CROPS: number = 48;

/** 缓存项（共享所有权：引用计数归零且超限才逐出释放）。 */
interface CropEntry {
  pm: image.PixelMap;
  refs: number;
}

/**
 * 预览裁剪缓存（`ImageKit.crop` 官方编辑 API；Canvas 九参数会画出整图，弃用）。
 * 键：`url#x,y,w,h`；文件层走 `ImageStore`，fd 解码（`createImageSource(fileUri)` 返回 undefined）。
 * 解码后原地裁剪，缓存即成品小图；`acquire` 引用 +1，`release` 引用 -1（归零且超限才释放）。
 */
export class PreviewSpriteCache {
  private static crops: Map<string, CropEntry> = new Map<string, CropEntry>();
  private store: ImageStore | undefined = undefined;

  /** 缓存键（cell 与页面共用，保证 `acquire/release` 同键）。 */
  static keyOf(url: string, x: number, y: number, w: number, h: number): string {
    return `${url}#${x},${y},${w},${h}`;
  }

  clear(): void {
    PreviewSpriteCache.crops.forEach((entry: CropEntry) => {
      entry.pm.release().catch((_e: object) => {
        // 释放失败 GC 兜底
      });
    });
    PreviewSpriteCache.crops.clear();
  }

  async acquire(context: common.Context, client: EhClient, referer: string,
    url: string, x: number, y: number, w: number, h: number): Promise<image.PixelMap> {
    const key: string = PreviewSpriteCache.keyOf(url, x, y, w, h);
    const hit: CropEntry | undefined = PreviewSpriteCache.crops.get(key);
    if (hit !== undefined) {
      hit.refs += 1;
      return hit.pm;
    }
    if (this.store === undefined) {
      this.store = new ImageStore();
      await this.store.init(context);
    }
    const path: string = await this.store.getPath(client, url, referer);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const source: image.ImageSource = image.createImageSource(file.fd);
      const pm: image.PixelMap = await source.createPixelMap();
      await pm.crop({ size: { width: w, height: h }, x: x, y: y });
      PreviewSpriteCache.evict();
      PreviewSpriteCache.crops.set(key, { pm: pm, refs: 1 });
      return pm;
    } finally {
      fs.closeSync(file);
    }
  }

  /** 归还引用；归零且超限时释放。键缺失（整清后）则无操作。 */
  static release(key: string): void {
    const entry: CropEntry | undefined = PreviewSpriteCache.crops.get(key);
    if (entry === undefined) {
      return;
    }
    entry.refs -= 1;
    if (entry.refs <= 0) {
      PreviewSpriteCache.crops.delete(key);
      entry.pm.release().catch((_e: object) => {
        // 释放失败 GC 兜底
      });
    } else {
      PreviewSpriteCache.evict();
    }
  }

  private static evict(): void {
    while (PreviewSpriteCache.crops.size >= MAX_CROPS) {
      let oldest: string | undefined = undefined;
      const keys: IterableIterator<string> = PreviewSpriteCache.crops.keys();
      let next: IteratorResult<string> = keys.next();
      while (!next.done) {
        const entry: CropEntry | undefined = PreviewSpriteCache.crops.get(next.value);
        if (entry !== undefined && entry.refs <= 0) {
          oldest = next.value;
          break;
        }
        next = keys.next();
      }
      if (oldest === undefined) {
        return;
      }
      const victim: CropEntry | undefined = PreviewSpriteCache.crops.get(oldest);
      PreviewSpriteCache.crops.delete(oldest);
      if (victim !== undefined) {
        victim.pm.release().catch((_e: object) => {
          // 释放失败 GC 兜底
        });
      }
    }
  }
}
