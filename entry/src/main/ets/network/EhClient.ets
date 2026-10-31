import { AppError } from '../common/AppError';
import { Logger } from '../common/Logger';
import { GalleryInfo } from '../model/GalleryInfo';
import { GalleryDetail } from '../model/GalleryDetail';
import { GalleryListParser } from '../parser/GalleryListParser';
import { GalleryDetailParser } from '../parser/GalleryDetailParser';
import { PreviewItem } from '../model/PreviewItem';
import { GalleryPageParser, GalleryPageResult } from '../parser/GalleryPageParser';
import { detectHtmlError, pageText } from '../parser/EhErrorDetector';
import { buildRateBody, parseRateResult, RateResult, buildCommentForm, buildAddFavForm } from './EhApi';
import { parseFavMeta, FavMeta } from '../parser/FavoritesParser';
import { GalleryComment } from '../model/GalleryComment';
import { HomeStats } from '../model/HomeStats';
import { HomeParser } from '../parser/HomeParser';
import { CookieJar } from './CookieJar';
import { DetailCache, sharedDetailCache } from './DetailCache';
import { EhSite, EhUrl } from './EhUrl';
import { HttpClient, HttpRequestOptions, HttpResponse } from './HttpClient';

/** 云收藏页（一行画廊 + 类/计数/排序元信息）。 */
export interface FavPage {
  items: GalleryInfo[];
  cats: string[];
  counts: number[];
  order: string;
}

/** 从 HTML 里取 `<title>`（只用于诊断日志：判断站点回的是列表页、登录页还是警告页）。 */
function htmlTitle(html: string): string {
  const match: RegExpMatchArray | null = html.match(new RegExp('<title[^>]*>([\\s\\S]{0,120})</title>', 'i'));
  return match === null ? '' : match[1].trim();
}

/** E-Hentai 请求层：站点/Referer/Cookie 组装 + 错误检测 + 解析。 */
export class EhClient {
  private http: HttpClient;
  private cookies: CookieJar;
  private cache: DetailCache;
  private defaults: HttpRequestOptions | undefined;

  constructor(http: HttpClient, cookies: CookieJar,
    cache: DetailCache = sharedDetailCache, defaults?: HttpRequestOptions) {
    this.http = http;
    this.cookies = cookies;
    this.cache = cache;
    this.defaults = defaults;
  }

  private async persistCookies(resp: HttpResponse): Promise<void> {
    if (resp.cookies === undefined) {
      return;
    }
    const jar: Record<string, string> = resp.cookies;
    const keys: string[] = Object.keys(jar);
    if (keys.length === 0) {
      return;
    }
    for (let i = 0; i < keys.length; i++) {
      this.cookies.set(keys[i], jar[keys[i]]);
    }
    await this.cookies.flush();
  }

  /**
   * 统一装配请求选项：调用方头（后写覆盖）+ 身份 Cookie + 默认超时。
   * `defaults.headers` 参与合并（当前无调用方设置，与旧行为逐字节一致）。
   */
  private requestOptions(headers: Record<string, string>): HttpRequestOptions {
    const merged: Record<string, string> = {};
    if (this.defaults !== undefined && this.defaults.headers !== undefined) {
      const keys: string[] = Object.keys(this.defaults.headers);
      for (let i = 0; i < keys.length; i++) {
        merged[keys[i]] = this.defaults.headers[keys[i]];
      }
    }
    const names: string[] = Object.keys(headers);
    for (let i = 0; i < names.length; i++) {
      merged[names[i]] = headers[names[i]];
    }
    const opt: HttpRequestOptions = { cookies: this.cookies.all(), headers: merged };
    if (this.defaults !== undefined) {
      if (this.defaults.timeoutMs !== undefined) {
        opt.timeoutMs = this.defaults.timeoutMs;
      }
    }
    return opt;
  }

  /** 拉取并解析画廊列表页（`thumbSize` 透传设置，默 0 原图）。 */
  async getGalleryList(site: EhSite, url: string, thumbSize: number = 0): Promise<GalleryInfo[]> {
    const headers: Record<string, string> = {};
    headers['Referer'] = EhUrl.referer(site);

    const opt: HttpRequestOptions = this.requestOptions(headers);

    const resp: HttpResponse = await this.http.get(url, opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    const list: GalleryInfo[] = GalleryListParser.parse(resp.body, thumbSize);
    if (list.length === 0) {
      Logger.error('List', `parse empty url=${url} len=${resp.body.length} title=${htmlTitle(resp.body)}`);
    }
    return list;
  }

  /** 拉取 `home.php` 并解析图片配额（My Home 第一块；未登录返回 `ok=false`）。 */
  async getHomeStats(site: EhSite): Promise<HomeStats> {
    // 图片配额是账号 / IP 级别，与浏览站点无关；EX 的 `home.php` 返回 404，统一读 E-Hentai。
    const homeSite: EhSite = EhSite.E;
    const headers: Record<string, string> = {};
    headers['Referer'] = EhUrl.referer(homeSite);
    const opt: HttpRequestOptions = this.requestOptions(headers);
    const resp: HttpResponse = await this.http.get(EhUrl.home(homeSite), opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    return HomeParser.parse(resp.body);
  }

  /** 拉取并解析详情页（`thumbSize` 透传设置，封面同样改写）。命中内存缓存时不发请求。 */
  async getGalleryDetail(site: EhSite, gid: number, token: string, thumbSize: number = 0): Promise<GalleryDetail | null> {
    // 缓存按 site/gid/thumbSize 分键：thumb 已按缩略图尺寸改写，混用会显示错尺寸封面。
    // 取出的对象只读使用（各页面都是抄字段进自己的 @Local），不得就地修改。
    const cached: GalleryDetail | null = this.cache.get(site, gid, thumbSize);
    if (cached !== null) {
      return cached;
    }
    const headers: Record<string, string> = {};
    headers['Referer'] = EhUrl.referer(site);
    const opt: HttpRequestOptions = this.requestOptions(headers);

    const resp: HttpResponse = await this.http.get(EhUrl.galleryDetail(site, gid, token), opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    const detail: GalleryDetail | null = GalleryDetailParser.parse(resp.body, gid, token, thumbSize);
    if (detail === null) {
      Logger.error('Detail', `parse null gid=${gid} len=${resp.body.length} reason=${GalleryDetailParser.lastReason()}`);
    } else {
      this.cache.put(site, gid, thumbSize, detail);
    }
    return detail;
  }

  /** 详情页 URL。 */
  getGalleryDetailUrl(site: EhSite, gid: number, token: string): string {
    return EhUrl.galleryDetail(site, gid, token);
  }

  /**
   * 画廊评分（源 `EhEngine.rateGallery`）：`POST api.php` JSON，成功返回服务端新均值 + 总数。
   * `apiUid/apiKey` 来自详情页 `var apiuid/apikey`（`GalleryDetailParser` 已解析）；缺失时调用方不得发请求。
   */
  async rateGallery(site: EhSite, gid: number, token: string, rating: number,
    apiUid: number, apiKey: string): Promise<RateResult> {
    const headers: Record<string, string> = {
      'Referer': EhUrl.galleryDetail(site, gid, token),
      'Origin': EhUrl.referer(site)
    };
    const opt: HttpRequestOptions = this.requestOptions(headers);
    const resp: HttpResponse =
      await this.http.postJson(EhUrl.api(site), buildRateBody(apiUid, apiKey, gid, token, rating), opt);
    await this.persistCookies(resp);
    const result: RateResult | null = parseRateResult(resp.body);
    if (result === null) {
      throw new AppError(-1, 'Cannot parse rate gallery result');
    }
    this.cache.drop(site, gid);
    return result;
  }

  /**
   * 发评论（源 `EhEngine.commentGallery` 新评论分支）：`POST` 详情页表单，
   * 成功返回重解析的评论区；回解析里找不到原文视为发送失败（服务端拒收时页面带错且评论不变）。
   */
  async postComment(site: EhSite, gid: number, token: string, text: string): Promise<GalleryComment[]> {
    const url: string = EhUrl.galleryDetail(site, gid, token);
    const headers: Record<string, string> = { 'Referer': url, 'Origin': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);
    const resp: HttpResponse = await this.http.postForm(url, buildCommentForm(text), opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    const comments: GalleryComment[] = GalleryDetailParser.parseComments(resp.body);
    const needle: string = text.trim();
    let found: boolean = false;
    for (let i = 0; i < comments.length; i++) {
      if (comments[i].text.includes(needle)) {
        found = true;
        break;
      }
    }
    if (!found) {
      throw new AppError(-1, 'Comment not posted');
    }
    this.cache.drop(site, gid);
    return comments;
  }

  /**
   * 云收藏页（源 `EhEngine.getFavorites` + `FavoritesParser`）：
   * 行复用 `GalleryListParser`，类/计数/排序走 `parseFavMeta`。
   * `favCat` `-1` = 全部。
   */
  async getCloudFavorites(site: EhSite, favCat: number, keyword: string, page: number,
    thumbSize: number = 0): Promise<FavPage> {
    const url: string = EhUrl.favorites(site, favCat, keyword, page);
    const headers: Record<string, string> = { 'Referer': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);
    const resp: HttpResponse = await this.http.get(url, opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    const meta: FavMeta = parseFavMeta(resp.body);
    return {
      items: GalleryListParser.parse(resp.body, thumbSize),
      cats: meta.cats,
      counts: meta.counts,
      order: meta.order
    };
  }

  /**
   * 收藏夹元信息（类名 + 计数 + 排序；源 `FavoritesParser` 的 `.fp` 子集）。
   * 详情页「选择收藏夹」半模态只需要这些，不解析行；`favCat=-1` = 全部页（页面顶部恒有 10 类统计）。
   */
  async getFavoritesMeta(site: EhSite): Promise<FavMeta> {
    const url: string = EhUrl.favorites(site, -1, '', 0);
    const headers: Record<string, string> = { 'Referer': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);
    const resp: HttpResponse = await this.http.get(url, opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    return parseFavMeta(resp.body);
  }

  /**
   * 收藏增/改/删（源 `EhEngine.addFavorites`）：`POST gallerypopups…act=addfav`。
   * `cat` 0–9 进类（已收画廊即改类），`-1` 删除；成功无回包，失败抛错。
   */
  async addFavorite(site: EhSite, gid: number, token: string, cat: number): Promise<void> {
    const url: string = EhUrl.addFav(site, gid, token);
    const headers: Record<string, string> = { 'Referer': url, 'Origin': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);
    const resp: HttpResponse = await this.http.postForm(url, buildAddFavForm(cat), opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    this.cache.drop(site, gid);
  }

  /**
   * 收藏排序切换（源 `FavoritesScene.getPageData(append)` + `FavoriteListSortDialog`）：
   * 往当前收藏页后缀 `inline_set=fs_f|fs_p` 再 GET；该 GET 即设置服务端排序偏好。
   * `order` `'f'` = 按收藏时间，`'p'` = 按发布时间。
   */
  async setFavOrder(site: EhSite, order: string, favCat: number, keyword: string, page: number): Promise<void> {
    const url: string = EhUrl.favOrderUrl(site, order, favCat, keyword, page);
    const headers: Record<string, string> = { 'Referer': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);
    const resp: HttpResponse = await this.http.get(url, opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
  }

  /** 拉取图片页并解析出图片直链与 H@H `skipHathKey`。 */
  async getGalleryPage(site: EhSite, gid: number, page: number, pToken: string,
    skipHathKey?: string): Promise<GalleryPageResult> {
    const headers: Record<string, string> = { 'Referer': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);

    const url: string = EhUrl.galleryPage(site, gid, page, pToken, skipHathKey);
    const resp: HttpResponse = await this.http.get(url, opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    const parsed: GalleryPageResult | null = GalleryPageParser.parse(resp.body, gid, page);
    if (parsed === null) {
      throw new AppError(-1, 'Cannot parse gallery page');
    }
    if (parsed.imageUrl.endsWith('/509.gif') || parsed.imageUrl.endsWith('/509s.gif')) {
      // 509 页面的站点原话最能说明额度：直接显示「用到多少 / 上限多少」。
      const siteText: string = pageText(resp.body);
      throw new AppError(509, siteText.length > 0 ? siteText : 'Exceeded image viewing quota (509)');
    }
    return parsed;
  }

  /**
   * 取某个**预览分块**的 pToken（按绝对页号 - 1 入数组），用于任意跳页。
   * 分块 URL：`/g/<gid>/<token>/?p=<chunk>`（每块 20 页，`chunk` 从 0 开始）。
   */
  async getPreviewTokens(site: EhSite, gid: number, token: string, chunk: number): Promise<string[]> {
    const headers: Record<string, string> = { 'Referer': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);

    const resp: HttpResponse = await this.http.get(EhUrl.galleryDetailChunk(site, gid, token, chunk), opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    return GalleryDetailParser.parsePreviewTokens(resp.body, gid);
  }

  /**
   * 取某个**预览分块**的预览项（含缩略图，用于详情预览区追加）。
   * 同 `getPreviewTokens` 的 URL，仅解析多取 `imageUrl`。
   */
  async getPreviews(site: EhSite, gid: number, token: string, chunk: number): Promise<PreviewItem[]> {
    const headers: Record<string, string> = { 'Referer': EhUrl.referer(site) };
    const opt: HttpRequestOptions = this.requestOptions(headers);

    const resp: HttpResponse = await this.http.get(EhUrl.galleryDetailChunk(site, gid, token, chunk), opt);
    await this.persistCookies(resp);
    const err: AppError | null = detectHtmlError(resp.body);
    if (err !== null) {
      throw err;
    }
    return GalleryDetailParser.parsePreviews(resp.body, gid);
  }

  /** 以 `Referer`（图片页 URL）+ 身份 Cookie 拉取图片直链的原始字节。 */
  async getImageBytes(imageUrl: string, referer: string): Promise<ArrayBuffer> {
    const headers: Record<string, string> = { 'Referer': referer };
    const opt: HttpRequestOptions = this.requestOptions(headers);
    // 原图 / 大图在慢网上可能超过默认 60s 传输；放宽到 120s，但仍保留 30s 无数据兜底（RCP 默认无空闲超时）。
    opt.timeoutMs = 120000;
    return this.http.getBytes(imageUrl, opt);
  }
}
