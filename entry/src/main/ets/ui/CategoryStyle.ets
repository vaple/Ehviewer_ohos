import {
  CATEGORY_MISC, CATEGORY_DOUJINSHI, CATEGORY_MANGA, CATEGORY_ARTIST_CG, CATEGORY_GAME_CG,
  CATEGORY_IMAGE_SET, CATEGORY_COSPLAY, CATEGORY_ASIAN_PORN, CATEGORY_NON_H, CATEGORY_WESTERN
} from '../parser/ParserUtils';

/**
 * 分类展示映射（名称与色值沿上游 Android 版 EhViewer 原文：`strings.xml` 的 `translatable=false` 分类名
 * + `EhUtils` 的 `BG_COLOR_*`；`translatable=false` 的词永不本地化）。
 */
export function catLabel(cat: number): string {
  switch (cat) {
    case CATEGORY_MISC:
      return 'MISC';
    case CATEGORY_DOUJINSHI:
      return 'DOUJINSHI';
    case CATEGORY_MANGA:
      return 'MANGA';
    case CATEGORY_ARTIST_CG:
      return 'ARTIST CG';
    case CATEGORY_GAME_CG:
      return 'GAME CG';
    case CATEGORY_IMAGE_SET:
      return 'IMAGE SET';
    case CATEGORY_COSPLAY:
      return 'COSPLAY';
    case CATEGORY_ASIAN_PORN:
      return 'ASIAN PORN';
    case CATEGORY_NON_H:
      return 'NON-H';
    case CATEGORY_WESTERN:
      return 'WESTERN';
    default:
      return 'UNKNOWN';
  }
}

/** 分类底色（`$r` token；未知回品牌色）。`$r` 需 UI 上下文，Local 只断言 `catLabel`。 */
export function catColor(cat: number): ResourceColor {
  switch (cat) {
    case CATEGORY_MISC:
      return $r('app.color.cat_misc');
    case CATEGORY_DOUJINSHI:
      return $r('app.color.cat_doujinshi');
    case CATEGORY_MANGA:
      return $r('app.color.cat_manga');
    case CATEGORY_ARTIST_CG:
      return $r('app.color.cat_artist_cg');
    case CATEGORY_GAME_CG:
      return $r('app.color.cat_game_cg');
    case CATEGORY_IMAGE_SET:
      return $r('app.color.cat_image_set');
    case CATEGORY_COSPLAY:
      return $r('app.color.cat_cosplay');
    case CATEGORY_ASIAN_PORN:
      return $r('app.color.cat_asian_porn');
    case CATEGORY_NON_H:
      return $r('app.color.cat_non_h');
    case CATEGORY_WESTERN:
      return $r('app.color.cat_western');
    default:
      return $r('app.color.brand');
  }
}
