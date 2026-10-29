/** 画廊类别（与上游 Android 版 EhViewer EhConfig / EhUtils 一致）。 */
export const CATEGORY_UNKNOWN: number = 0x400;
export const CATEGORY_MISC: number = 0x1;
export const CATEGORY_DOUJINSHI: number = 0x2;
export const CATEGORY_MANGA: number = 0x4;
export const CATEGORY_ARTIST_CG: number = 0x8;
export const CATEGORY_GAME_CG: number = 0x10;
export const CATEGORY_IMAGE_SET: number = 0x20;
export const CATEGORY_COSPLAY: number = 0x40;
export const CATEGORY_ASIAN_PORN: number = 0x80;
export const CATEGORY_NON_H: number = 0x100;
export const CATEGORY_WESTERN: number = 0x200;

/** 类别名（来自 `api.php` 的 `category` / HTML 的 `cn ctN` 文本）→ 类别码。 */
export function categoryOf(type: string | undefined): number {
  if (type === undefined) {
    return CATEGORY_UNKNOWN;
  }
  const t: string = type.toLowerCase();
  if (t === 'misc') return CATEGORY_MISC;
  if (t === 'doujinshi') return CATEGORY_DOUJINSHI;
  if (t === 'manga') return CATEGORY_MANGA;
  if (t === 'artistcg' || t === 'artist cg sets' || t === 'artist cg') return CATEGORY_ARTIST_CG;
  if (t === 'gamecg' || t === 'game cg sets' || t === 'game cg') return CATEGORY_GAME_CG;
  if (t === 'imageset' || t === 'image sets' || t === 'image set') return CATEGORY_IMAGE_SET;
  if (t === 'cosplay') return CATEGORY_COSPLAY;
  if (t === 'asianporn' || t === 'asian porn') return CATEGORY_ASIAN_PORN;
  if (t === 'non-h') return CATEGORY_NON_H;
  if (t === 'western') return CATEGORY_WESTERN;
  return CATEGORY_UNKNOWN;
}

const LANGUAGE_MAP: Record<string, string> = {
  'english': 'EN', 'chinese': 'ZH', 'japanese': 'JA', 'korean': 'KO', 'spanish': 'ES',
  'russian': 'RU', 'french': 'FR', 'portuguese': 'PT', 'thai': 'TH', 'german': 'DE',
  'italian': 'IT', 'vietnamese': 'VI', 'polish': 'PL', 'hungarian': 'HU', 'dutch': 'NL'
};

const RATING_PX: RegExp = new RegExp('\\d+px', 'g');

/** 由 `.ir` 的 `background-position` 评星样式换算评分（源 `GalleryListParser.parseRating`）。 */
export function ratingFromStyle(style: string): number {
  const m: RegExpMatchArray | null = style.match(RATING_PX);
  if (m === null || m.length < 2) {
    return 0;
  }
  const num1: number = Number.parseInt(m[0].replace('px', ''), 10);
  const num2: number = Number.parseInt(m[1].replace('px', ''), 10);
  let rate: number = 5 - Math.floor(num1 / 16);
  if (num2 === 21) {
    rate = rate - 1 + 0.5;
  }
  return rate;
}

/** 从标签里取 `language:xxx` 映射为 ISO 639-1；找不到返回空串。 */
export function languageOf(tags: string[]): string {
  for (let i = 0; i < tags.length; i++) {
    const tag: string = tags[i];
    if (tag.startsWith('language:')) {
      const name: string = tag.substring('language:'.length).toLowerCase();
      const iso: string | undefined = LANGUAGE_MAP[name];
      if (iso !== undefined) {
        return iso;
      }
    }
  }
  return '';
}
