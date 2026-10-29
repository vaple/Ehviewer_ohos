import { Html, HtmlNode } from './Html';

const ONCLICK_FAVCAT: RegExp = new RegExp('favcat=(\\d+)');

/** 收藏页元信息（源 `FavoritesParser.Result` 的类/计数/排序子集；行另走 `GalleryListParser`）。 */
export interface FavMeta {
  cats: string[];
  counts: number[];
  order: string;
}

/**
 * 收藏页元信息（源 `FavoritesParser` 的 `.fp` + Order select 子集）：
 * `.fp` 取 `onclick` 的 `favcat=`（无则为"全部"跳过）、首子 div 计数、末子 div 名
 * （名空则取图标 `title`）；Order 取选中 `option` 的 `value`，无则 `''`。
 */
export function parseFavMeta(html: string): FavMeta {
  const meta: FavMeta = { cats: [], counts: [], order: '' };
  const root: HtmlNode = Html.parse(html);
  const fps: HtmlNode[] = Html.select(root, '.fp');
  for (let i = 0; i < fps.length; i++) {
    const onclick: string | null = Html.attr(fps[i], 'onclick');
    if (onclick === null || onclick.match(ONCLICK_FAVCAT) === null) {
      continue;
    }
    const all: HtmlNode[] = Html.select(fps[i], 'div');
    // `select` 含作用域自身（`.fp` 本身就是 `div`，见 `parseCover` 注释），去掉首个自身节点。
    const divs: HtmlNode[] = [];
    for (let j = 0; j < all.length; j++) {
      if (all[j] !== fps[i]) {
        divs.push(all[j]);
      }
    }
    if (divs.length < 3) {
      continue;
    }
    const count: number = Number.parseInt(Html.text(divs[0]).trim(), 10);
    let name: string = Html.text(divs[divs.length - 1]).trim();
    if (name.length === 0) {
      const iconTitle: string | null = Html.attr(divs[1], 'title');
      name = iconTitle === null ? '' : iconTitle;
    }
    meta.cats.push(name);
    meta.counts.push(isNaN(count) ? 0 : count);
  }
  const options: HtmlNode[] = Html.select(root, 'option');
  for (let i = 0; i < options.length; i++) {
    if (Html.attr(options[i], 'selected') !== null) {
      const value: string | null = Html.attr(options[i], 'value');
      meta.order = value === null ? '' : value;
      break;
    }
  }
  return meta;
}
