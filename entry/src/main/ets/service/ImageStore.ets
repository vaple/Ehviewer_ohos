import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { EhClient } from '../network/EhClient';

/**
 * 图片磁盘缓存（方案 B）：用 RCP（带 `Referer` + 身份 Cookie）取字节落盘，
 * 返回可交给 `Image` 组件的沙箱 URI（`file://<bundleName>/<path>`）。
 *
 * 好处：能带请求头（EX / H@H 必需）+ 白得磁盘缓存 + 由 `Image` 负责解码与内存缓存。
 *
 * 生命周期：**没有过期时间，也不自动清理**（用户 2026-10-28 决定保持手动管理）——
 * 只由设置页「清理缓存」（`CacheManager`）或系统回收 `cacheDir` 时删除。
 * 缓存键见 `stableKeyOf()`：必须剔除会变化的 `keystamp` 签名，否则永远命中不了。
 */
export class ImageStore {
  private dir: string = '';
  private ready: boolean = false;

  async init(context: common.Context): Promise<void> {
    if (this.ready) {
      return;
    }
    this.dir = `${context.cacheDir}/images`;
    if (!fs.accessSync(this.dir)) {
      fs.mkdirSync(this.dir, true);
    }
    this.ready = true;
  }

  /** 命中缓存直接返回沙箱 URI；否则下载并落盘。 */
  async get(client: EhClient, url: string, referer: string): Promise<string> {
    const path: string = await this.pathFor(client, url, referer);
    return fileUri.getUriFromPath(path);
  }

  /** 命中缓存直接返回沙箱路径；否则下载并落盘（`createImageSource(fd)` 用）。 */
  async getPath(client: EhClient, url: string, referer: string): Promise<string> {
    return await this.pathFor(client, url, referer);
  }

  private async pathFor(client: EhClient, url: string, referer: string): Promise<string> {
    const path: string = `${this.dir}/${ImageStore.nameOf(url)}`;
    if (!fs.accessSync(path)) {
      const bytes: ArrayBuffer = await client.getImageBytes(url, referer);
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes);
      } finally {
        fs.closeSync(file);
      }
    }
    return path;
  }

  /**
   * 稳定的缓存键。
   *
   * E-Hentai / H@H 的图片直链里带一次性签名：
   * `https://xxx.hath.network:34680/h/<hash>/keystamp=<时间戳>-<签名>;fileindex=...;xres=.../1.webp`
   * `keystamp` 每次加载都会变，按整串 URL 做键等于永远 miss（2026-10-28 实测 fixture）。
   * 所以只取真正标识图片的 `/h/<hash>` 段；没有该段的 URL（缩略图等）去掉 query 即可。
   */
  static stableKeyOf(url: string): string {
    const hath: RegExpMatchArray | null = url.match(/\/h\/([^/]+)/);
    if (hath !== null) {
      return hath[1];
    }
    const query: number = url.indexOf('?');
    return query >= 0 ? url.substring(0, query) : url;
  }

  /** 缓存文件名：稳定键的 djb2 哈希 + 原扩展名（纯 `[0-9a-f.]`，规避特殊字符路径问题）。 */
  static nameOf(url: string): string {
    const key: string = ImageStore.stableKeyOf(url);
    let h: number = 5381;
    for (let i = 0; i < key.length; i++) {
      h = ((h * 33) ^ key.charCodeAt(i)) >>> 0;
    }
    let ext: string = '.img';
    const dot: number = url.lastIndexOf('.');
    const slash: number = url.lastIndexOf('/');
    if (dot > slash && dot >= 0) {
      const e: string = url.substring(dot + 1).toLowerCase();
      if (e.length > 0 && e.length <= 4) {
        ext = `.${e}`;
      }
    }
    return `${h.toString(16)}${ext}`;
  }
}
