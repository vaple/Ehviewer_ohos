/** 详情页 URL 解析结果。 */
export interface DetailUrlResult {
  gid: number;
  token: string;
}

const STRICT: RegExp = new RegExp(
  'https?://(?:exhentai\\.org|e-hentai\\.org|lofi\\.e-hentai\\.org)/(?:g|mpv)/(\\d+)/([0-9a-f]{10})');

/** 解析详情页 URL（`/g/<gid>/<token>/`）。 */
export class GalleryDetailUrlParser {
  static parse(url: string): DetailUrlResult | null {
    const m: RegExpMatchArray | null = url.match(STRICT);
    if (m === null || m.length < 3) {
      return null;
    }
    const gid: number = Number.parseInt(m[1], 10);
    if (isNaN(gid) || gid < 0) {
      return null;
    }
    const result: DetailUrlResult = { gid: gid, token: m[2] };
    return result;
  }
}
