import { Html, HtmlNode } from './Html';

/** 图片页解析结果。 */
export interface GalleryPageResult {
  /** 页面展示的图片直链（按站点画质设置重采样后的版本）。 */
  imageUrl: string;
  /** 「Download original」的直链（原图）；没有该入口时为 `null`。 */
  originalUrl: string | null;
  skipHathKey: string | null;
  /** 下一页的 pToken（顺序翻页用）；未知为 `null`。 */
  nextPToken: string | null;
}

const SKIP_HATH: RegExp = new RegExp("nl\\('([^)]+)'\\)");
const ORIGINAL_HREF: RegExp = new RegExp('href="([^"]*\\/fullimg\\/[^"]+)"');

/**
 * 解析图片页 HTML → `{ imageUrl, originalUrl, skipHathKey, nextPToken }`（源 `GalleryPageParser`）。
 * 传入 `gid`/`page` 时可解析下一页 pToken。
 */
export class GalleryPageParser {
  static parse(html: string, gid: number = -1, page: number = -1): GalleryPageResult | null {
    const root: HtmlNode = Html.parse(html);
    const img: HtmlNode[] = Html.select(root, '#img');
    if (img.length === 0) {
      return null;
    }
    const src: string | null = Html.attr(img[0], 'src');
    if (src === null) {
      return null;
    }

    let skipHathKey: string | null = null;
    const m: RegExpMatchArray | null = html.match(SKIP_HATH);
    if (m !== null) {
      skipHathKey = m[1];
    }

    let originalUrl: string | null = null;
    const original: RegExpMatchArray | null = html.match(ORIGINAL_HREF);
    if (original !== null) {
      originalUrl = original[1];
    }

    let nextPToken: string | null = null;
    if (gid >= 0 && page >= 0) {
      const next: RegExpMatchArray | null =
        html.match(new RegExp('/s/([0-9a-f]{10})/' + gid + '-' + (page + 1) + '(?![0-9])'));
      if (next !== null) {
        nextPToken = next[1];
      }
    }

    const result: GalleryPageResult = {
      imageUrl: src,
      originalUrl: originalUrl,
      skipHathKey: skipHathKey,
      nextPToken: nextPToken
    };
    return result;
  }
}
