import { GalleryInfo } from '../model/GalleryInfo';
import { GalleryListPage } from '../parser/GalleryListParser';
import { GalleryRowItem } from './GalleryRow';

/** 取一页列表（真机走 `EhClient`，单测用假实现）。 */
export type ListFetcher = (url: string) => Promise<GalleryListPage>;

/**
 * 分页列表的唯一状态持有者：items / 下一页游标 / 已访问 URL。
 *
 * 为什么不再用"本页新增了几条"推断到底（旧 `PagedList.hasMoreAfterPage`）：
 * 那是拿结果猜原因——站点对越界页会重复返回最后一页，靠"新增为 0"判断要**多打一次必废请求**，
 * 而且页数语义在三种列表（`page=` / `p=` / `?next=<gid>`）里各不相同。
 * 站点在分页控件里已经给了下一页的 URL，顺着走就行：`next === null` 或 `next` 回指已访问页
 * 就是到底（`ui/AGENTS.md` #66）。
 */
export class GalleryListFeed {
  private readonly fetcher: (url: string) => Promise<GalleryListPage>;
  private rows: GalleryRowItem[] = [];
  private cursor: string | null = null;
  private visited: Set<string> = new Set<string>();
  private busy: boolean = false;

  constructor(fetcher: ListFetcher) {
    this.fetcher = fetcher;
  }

  get items(): GalleryRowItem[] {
    return this.rows;
  }

  /** 还有下一页（游标非空）。 */
  get hasMore(): boolean {
    return this.cursor !== null;
  }

  get loading(): boolean {
    return this.busy;
  }

  /**
   * 取下一页；`refresh === true` 时从 `firstUrl` 重新开始。
   *
   * 失败直接抛给调用方（页面负责把它变成错误文案）——这里不做兜底，
   * 否则"解析失败"会被伪装成"已经到底"，用户看到的是列表突然停住。
   */
  async load(firstUrl: string, refresh: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    if (refresh) {
      this.rows = [];
      this.visited.clear();
      this.cursor = firstUrl;
    }
    if (this.cursor === null) {
      return;
    }
    const url: string = this.cursor;
    this.busy = true;
    try {
      // 先登记再请求：站点把越界页重定向回第 1 页时，下一轮就能认出"这个 URL 来过"。
      this.visited.add(url);
      // `Promise.resolve` 只是把类型显式化：`await` 一个"函数类型属性"的返回值会被
      // `@typescript-eslint/await-thenable` 误判（同一规则在 `AGENTS.md` #14 也有先例）。
      const pending: Promise<GalleryListPage> = Promise.resolve(this.fetcher(url));
      const page: GalleryListPage = await pending;
      const fresh: GalleryRowItem[] = GalleryListFeed.dedupe(this.rows, page.items);
      this.rows = refresh ? fresh : this.rows.concat(fresh);
      this.cursor = page.next !== null && !this.visited.has(page.next) ? page.next : null;
    } finally {
      this.busy = false;
    }
  }

  /** 按 gid 去重后映射成行（同一条目在跨页时可能重复出现）。 */
  private static dedupe(existing: GalleryRowItem[], page: GalleryInfo[]): GalleryRowItem[] {
    const seen: Set<number> = new Set<number>();
    for (let i = 0; i < existing.length; i++) {
      seen.add(existing[i].gid);
    }
    const out: GalleryRowItem[] = [];
    for (let i = 0; i < page.length; i++) {
      const info: GalleryInfo = page[i];
      if (seen.has(info.gid)) {
        continue;
      }
      seen.add(info.gid);
      const item: GalleryRowItem = new GalleryRowItem();
      item.gid = info.gid;
      item.token = info.token;
      item.title = info.title;
      item.uploader = info.uploader;
      item.thumbUrl = info.thumb;
      item.category = info.category;
      item.rating = info.rating;
      item.posted = info.posted;
      item.simpleLanguage = info.simpleLanguage;
      item.pages = info.pages;
      out.push(item);
    }
    return out;
  }
}
