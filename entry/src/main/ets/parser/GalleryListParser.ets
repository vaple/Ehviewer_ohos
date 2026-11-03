import { GalleryInfo } from '../model/GalleryInfo';
import { Html, HtmlNode } from './Html';
import { GalleryDetailUrlParser, DetailUrlResult } from './GalleryDetailUrlParser';
import { categoryOf, languageOf, ratingFromStyle } from './ParserUtils';
import { EhUrl } from '../network/EhUrl';

const ITG_CLASS: string = '.itg';
const PAGES_TEXT: RegExp = new RegExp('^(\\d+)\\s+pages$');
const SITE_BASE: string = 'https://e-hentai.org';

/** 一页列表的解析结果：条目 + 站点自己给的下一页 URL（没有就是到底）。 */
export interface GalleryListPage {
  items: GalleryInfo[];
  next: string | null;
}

/**
 * 从分页控件里取"下一页"链接。
 *
 * 站点有两套分页控件，**必须都认**（真机抓包实证）：
 * - `table.ptt`（排行榜）：最后一格是 `>` 箭头，末页时它退化成纯文本、没有 `<a>`；
 * - `div.searchnav` 的 `a#dnext`（搜索 / 收藏 / 订阅）：单页时它是 `<span id="dnext">`，
 *   有下一页时才是 `<a id="dnext" href="…?next=<gid>">`。
 *
 * 认不出结构时返回 `null`（fail-closed：宁可少翻一页，也不能靠猜页码无限翻）。
 */
function nextUrlOf(root: HtmlNode): string | null {
  const ptt: HtmlNode[] = Html.select(root, '.ptt');
  if (ptt.length > 0) {
    const cells: HtmlNode[] = Html.select(ptt[0], 'td');
    if (cells.length === 0) {
      return null;
    }
    const anchors: HtmlNode[] = Html.select(cells[cells.length - 1], 'a');
    return anchors.length > 0 ? absoluteUrl(Html.attr(anchors[0], 'href')) : null;
  }
  const dnext: HtmlNode[] = Html.select(root, '#dnext');
  if (dnext.length > 0) {
    // 单页时这里是 `<span>`，没有 `href` → `null`，正好表示"没有下一页"。
    return absoluteUrl(Html.attr(dnext[0], 'href'));
  }
  return null;
}

/** 属性里的 `&amp;` 不一定被解码，统一补齐；相对路径按站点域名补全。 */
function absoluteUrl(href: string | null): string | null {
  if (href === null || href.length === 0) {
    return null;
  }
  const url: string = href.replace(new RegExp('&amp;', 'g'), '&');
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  if (url.startsWith('/')) {
    return `${SITE_BASE}${url}`;
  }
  return null;
}

/** 解析画廊列表 HTML → `GalleryInfo[]`（仅取 `.itg` 容器内的行，与上游 Android 版 EhViewer 一致）。
 * `thumbSize` 透传设置（0 原图 / 1 `_250` / 2 `_300`，默 0 不改现有调用）。 */
export class GalleryListParser {
  /** 兼容旧调用：只要条目。新代码请用 `parsePage`（它同时给下一页 URL）。 */
  static parse(html: string, thumbSize: number = 0): GalleryInfo[] {
    return GalleryListParser.parsePage(html, thumbSize).items;
  }

  /**
   * 解析一页列表：条目 + 站点自己给的下一页 URL。
   * `next === null` 就等于"到底了"——不再靠"本页有没有新增条目"猜（见 `ui/AGENTS.md` #66）。
   */
  static parsePage(html: string, thumbSize: number = 0): GalleryListPage {
    const root: HtmlNode = Html.parse(html);
    // 先取下一页：即使这一页没有任何条目（No hits），分页控件也可能存在。
    const next: string | null = nextUrlOf(root);
    const containers: HtmlNode[] = Html.select(root, ITG_CLASS);
    if (containers.length === 0) {
      return { items: [], next: next };
    }
    return { items: GalleryListParser.parseItems(containers, thumbSize), next: next };
  }

  private static parseItems(containers: HtmlNode[], thumbSize: number): GalleryInfo[] {
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
}
