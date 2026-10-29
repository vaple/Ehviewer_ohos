import { GalleryInfo } from '../model/GalleryInfo';
import { Html, HtmlNode } from './Html';
import { GalleryDetailUrlParser, DetailUrlResult } from './GalleryDetailUrlParser';
import { categoryOf, languageOf, ratingFromStyle } from './ParserUtils';
import { EhUrl } from '../network/EhUrl';

const NEXT_PAGE: RegExp = new RegExp('[?&]page=(\\d+)');
const ITG_CLASS: string = '.itg';
const PAGES_TEXT: RegExp = new RegExp('^(\\d+)\\s+pages$');

/** 解析画廊列表 HTML → `GalleryInfo[]`（仅取 `.itg` 容器内的行，与上游 Android 版 EhViewer 一致）。
 * `thumbSize` 透传设置（0 原图 / 1 `_250` / 2 `_300`，默 0 不改现有调用）。 */
export class GalleryListParser {
  static parse(html: string, thumbSize: number = 0): GalleryInfo[] {
    const root: HtmlNode = Html.parse(html);
    const containers: HtmlNode[] = Html.select(root, ITG_CLASS);
    if (containers.length === 0) {
      return [];
    }
    // 表格模式（Compact/Extended：`table.itg`）行是 `tr`；
    // 缩略图模式（Thumbnail：`div.itg.gld`）项是 `div.gl1t`（源 `GalleryListParser` 同形分支）。
    const rows: HtmlNode[] = Html.tagName(containers[0]) === 'table'
      ? Html.select(containers[0], 'tr')
      : Html.select(containers[0], '.gl1t');
    const list: GalleryInfo[] = [];

    for (let r = 0; r < rows.length; r++) {
      const row: HtmlNode = rows[r];

      const anchors: HtmlNode[] = Html.select(row, 'a');
      let detail: DetailUrlResult | null = null;
      let link: HtmlNode | null = null;
      for (let i = 0; i < anchors.length; i++) {
        const href: string | null = Html.attr(anchors[i], 'href');
        if (href === null) {
          continue;
        }
        const parsed: DetailUrlResult | null = GalleryDetailUrlParser.parse(href);
        if (parsed !== null) {
          detail = parsed;
          link = anchors[i];
          break;
        }
      }
      if (detail === null || link === null) {
        continue;
      }

      // 标题：优先 `.glink`（标题单元格）；缩略图模式下第一个详情链接可能是封面 `<a>`（无文字），
      // 所以在**整行**里找 `.glink` 兜底，避免标题变成空串（`gid xxx` 占位）。
      let titleNodes: HtmlNode[] = Html.select(link, '.glink');
      if (titleNodes.length === 0) {
        titleNodes = Html.select(row, '.glink');
      }
      const title: string = titleNodes.length > 0
        ? Html.text(titleNodes[0]).trim()
        : Html.text(link).trim();

      // 语言标签：**整行**取 `.gt[title]`。表格布局里它在详情 `<a>` 内，缩略图/紧凑布局里可能在 `<a>` 外，
      // 只绑第一个 `<a>` 会漏掉（收藏页曾因此丢失语言标签）。站点没给就不猜（不做标题兜底）。
      const tagTitles: string[] = [];
      const gts: HtmlNode[] = Html.select(row, '.gt');
      for (let t = 0; t < gts.length; t++) {
        const tagTitle: string | null = Html.attr(gts[t], 'title');
        if (tagTitle !== null) {
          tagTitles.push(tagTitle);
        }
      }

      let category: number = 0;
      let thumb: string = '';
      let uploader: string = '';
      let posted: string = '';
      let rating: number = 0;

      // 分类：表格 `div.cn`，缩略图 `div.cs`（源 `parseGalleryInfo` 同形回退）。
      let cn: HtmlNode[] = Html.select(row, '.cn');
      if (cn.length === 0) {
        cn = Html.select(row, '.cs');
      }
      if (cn.length > 0) {
        category = categoryOf(Html.text(cn[0]).trim());
      }

      const img: HtmlNode[] = Html.select(row, 'img');
      if (img.length > 0) {
        const dataSrc: string | null = Html.attr(img[0], 'data-src');
        const src: string | null = Html.attr(img[0], 'src');
        const rawThumb: string = dataSrc !== null ? dataSrc : (src !== null ? src : '');
        thumb = rawThumb.length > 0
          ? EhUrl.thumbResolution(EhUrl.fixedPreviewThumb(rawThumb), thumbSize) : '';
      }

      const gl4c: HtmlNode[] = Html.select(row, '.gl4c');
      if (gl4c.length > 0) {
        const ua: HtmlNode[] = Html.select(gl4c[0], 'a');
        if (ua.length > 0) {
          uploader = Html.text(ua[0]).trim();
        }
      }

      const postedNodes: HtmlNode[] = Html.select(row, `#posted_${detail.gid}`);
      if (postedNodes.length > 0) {
        posted = Html.text(postedNodes[0]).trim();
      }

      const ir: HtmlNode[] = Html.select(row, '.ir');
      if (ir.length > 0) {
        const style: string | null = Html.attr(ir[0], 'style');
        if (style !== null) {
          rating = ratingFromStyle(style);
        }
      }

      // 总页数：行内 `N pages` 叶 div（guest 列表缺该 div 时为 0，调用方跳过展示）。
      let pages: number = 0;
      const divs: HtmlNode[] = Html.select(row, 'div');
      for (let d = 0; d < divs.length; d++) {
        const m: RegExpMatchArray | null = Html.text(divs[d]).trim().match(PAGES_TEXT);
        if (m !== null) {
          const n: number = Number.parseInt(m[1], 10);
          pages = isNaN(n) ? 0 : n;
          break;
        }
      }

      const tagLang: string = languageOf(tagTitles);      const info: GalleryInfo = {
        gid: detail.gid,
        token: detail.token,
        title: title,
        titleJpn: '',
        thumb: thumb,
        category: category,
        posted: posted,
        uploader: uploader,
        rating: rating,
        // 只认站点给的 `language:` 标签；没有就不显示（不按标题猜）。
        simpleLanguage: tagLang,
        pages: pages
      };
      list.push(info);
    }
    return list;
  }

  /** 下一页页码（`page=` 参数）；无则 -1。 */
  static parseNextPage(html: string): number {
    const m: RegExpMatchArray | null = html.match(NEXT_PAGE);
    if (m === null) {
      return -1;
    }
    const page: number = Number.parseInt(m[1], 10);
    return isNaN(page) ? -1 : page;
  }
}
