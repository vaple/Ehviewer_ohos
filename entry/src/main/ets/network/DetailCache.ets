import { EhSite } from './EhUrl';
import { GalleryDetail } from '../model/GalleryDetail';

/** 一条缓存记录：详情 + 写入时刻（TTL 判定用）。 */
interface CacheEntry {
  detail: GalleryDetail;
  at: number;
}

/**
 * 详情页内存缓存（源 `EhApplication.mGalleryDetailCache`：`LruCache(25)`）。
 *
 * 为什么需要：`/g/<gid>/<token>/` 这份 HTML 会被拉两遍 —— 详情页一次、进阅读器 `init()` 又一次。
 * E 站详情页由服务端实时渲染，冷请求真机实测 1.4 s 起步；缓存把第二次降到 0 网络。
 *
 * 为什么 key 带 `thumbSize`：`GalleryDetail.thumb` 已按设置里的缩略图尺寸改写，混用会显示错误尺寸的封面。
 * 为什么要 TTL：标签/评论会被别人改动，3 分钟够覆盖「详情 → 阅读 → 返回」，又不会长期显示旧数据。
 *
 * ⚠️ 取出的对象按**只读**使用：调用方只抄字段，不得就地修改，否则会污染其它页面。
 */
export class DetailCache {
  private capacity: number;
  private ttlMs: number;
  private now: () => number;
  private entries: Map<string, CacheEntry> = new Map<string, CacheEntry>();

  constructor(capacity: number, ttlMs: number, now: () => number = () => Date.now()) {
    this.capacity = capacity;
    this.ttlMs = ttlMs;
    this.now = now;
  }

  private static keyOf(site: EhSite, gid: number, thumbSize: number): string {
    return `${site}:${gid}:${thumbSize}`;
  }

  get(site: EhSite, gid: number, thumbSize: number): GalleryDetail | null {
    // `ttlMs <= 0` = 关闭缓存（设备级测试用它保持「每次真发请求」的语义）。
    if (this.ttlMs <= 0) {
      return null;
    }
    const key: string = DetailCache.keyOf(site, gid, thumbSize);
    const entry: CacheEntry | undefined = this.entries.get(key);
    if (entry === undefined) {
      return null;
    }
    if (this.now() - entry.at > this.ttlMs) {
      this.entries.delete(key);
      return null;
    }
    // 命中即刷新近期性：Map 的插入顺序就是 LRU 顺序，删了重插即置顶。
    this.entries.delete(key);
    this.entries.set(key, entry);
    // 返回副本：调用方（详情页 / 评论页）会把对象和数组直接挂到 @Local 上，
    // 一旦谁就地改（乐观插入评论、过滤标签），就会污染缓存里的原件。
    return DetailCache.copyOf(entry.detail);
  }

  /** 浅拷贝：顶层字段 + 四个数组各复制一份（元素本身只读，不再深拷）。 */
  private static copyOf(d: GalleryDetail): GalleryDetail {
    return {
      gid: d.gid,
      token: d.token,
      title: d.title,
      titleJpn: d.titleJpn,
      category: d.category,
      uploader: d.uploader,
      posted: d.posted,
      rating: d.rating,
      ratingCount: d.ratingCount,
      pages: d.pages,
      thumb: d.thumb,
      tagGroups: d.tagGroups.slice(),
      previewTokens: d.previewTokens.slice(),
      previews: d.previews.slice(),
      apiUid: d.apiUid,
      apiKey: d.apiKey,
      comments: d.comments.slice(),
      isFavorited: d.isFavorited,
      favoriteName: d.favoriteName
    };
  }

  put(site: EhSite, gid: number, thumbSize: number, detail: GalleryDetail): void {
    if (this.ttlMs <= 0) {
      return;
    }
    const key: string = DetailCache.keyOf(site, gid, thumbSize);
    this.entries.delete(key);
    const entry: CacheEntry = { detail: detail, at: this.now() };
    this.entries.set(key, entry);
    while (this.entries.size > this.capacity) {
      let oldest: string = '';
      this.entries.forEach((_value: CacheEntry, k: string) => {
        if (oldest.length === 0) {
          oldest = k;
        }
      });
      if (oldest.length === 0) {
        return;
      }
      this.entries.delete(oldest);
    }
  }

  /** 失效该画廊的全部 `thumbSize` 变体（写操作后用）。 */
  drop(site: EhSite, gid: number): void {
    const prefix: string = `${site}:${gid}:`;
    const doomed: string[] = [];
    this.entries.forEach((_value: CacheEntry, k: string) => {
      if (k.startsWith(prefix)) {
        doomed.push(k);
      }
    });
    // 先收集再删：边迭代边删 Map 不安全。
    for (let i = 0; i < doomed.length; i++) {
      this.entries.delete(doomed[i]);
    }
  }

  /** 清空全部缓存：登录态（Cookie）变化后必须调用，否则会读到上一个账号的详情。 */
  clear(): void {
    this.entries.clear();
  }

  /** 仅供测试断言。 */
  size(): number {
    return this.entries.size;
  }
}

/** 全 App 共用：25 条 / 180 s（对齐源工程 `LruCache<>(25)` + 3 分钟）。 */
export const sharedDetailCache: DetailCache = new DetailCache(25, 180000);
