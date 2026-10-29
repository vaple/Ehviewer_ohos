import { GalleryDetail } from '../model/GalleryDetail';
import { GalleryComment } from '../model/GalleryComment';
import { PreviewItem } from '../model/PreviewItem';
import { TagGroup } from '../model/TagGroup';
import { Html, HtmlNode } from './Html';
import { categoryOf, ratingFromStyle } from './ParserUtils';
import { EhUrl } from '../network/EhUrl';

/** 页数（源 `PATTERN_PAGES`：Length 行唯一来源，逗号容忍；无 `of N images` 兜底）。 */
const LENGTH_PAGES: RegExp = new RegExp('<tr><td[^<>]*>Length:</td><td[^<>]*>([\\d,]+) page');
const AVERAGE: RegExp = new RegExp('Average:\\s*([\\d.]+)');
const COMMENT_TIME: RegExp = new RegExp('Posted on (.+?) by:');
const SCORE_NUM: RegExp = new RegExp('[+-]?\\d+');
/** 评分凭证（源 `GalleryDetailParser.PATTERN_DETAIL` 等价；游客 `apiuid` 为 `-1`）。 */
const API_KEYS: RegExp =
  new RegExp('var gid = (\\d+);[\\s\\S]+?var token = "([a-f0-9]+)";[\\s\\S]+?var apiuid = ([\\-\\d]+);[\\s\\S]+?var apikey = "([a-f0-9]+)";');
/** 封面样式（源 `GalleryDetailParser.PATTERN_COVER`；取第 3 组即 URL）。 */
const COVER: RegExp = new RegExp('width:(\\d+)px; height:(\\d+)px.+?url\\((.+?)\\)');
/** 预览图（`style` 的 `url(...)`，引号可选；沿 `COVER` 取组方式）。 */
const PREVIEW_IMG: RegExp = new RegExp('url\\(["\']?(.+?)["\']?\\)');
/** 预览格几何（`width:Wpx;height:Hpx;…` + `url(...) -Xpx Y`；空白容忍，逐格独立）。 */
const PREVIEW_BOX: RegExp = new RegExp('width:\\s*(\\d+)px;\\s*height:\\s*(\\d+)px');
const PREVIEW_OFF: RegExp = new RegExp('\\)\\s*(-?\\d+)px\\s+(-?\\d+)');
/** 未收藏时收藏按钮的站点原文（源 `GalleryDetailParser` 同判据）。 */
const ADD_TO_FAVORITES: string = 'Add to Favorites';

/**
 * 最近一次 `parse` 的失败/降级原因：`''`（正常）/ `empty body` / `no #gn` / `no Length row`。
 * 返回类型与签名都不变，只多一个可读的副作用，供 `EhClient` 写日志。
 */
let lastReason: string = '';

/**
 * 标签键（`namespace:tag` 全称，站内原串；组名恒带，`other:` 是站内真命名空间，fixture href 为证）。
 * 用于复制与展示；**搜索查询串**要再经 `exactTagQuery` 包成 `namespace:"tag$"`（见 `GalleryDetailPage`）。
 * 冒号/空格编码由 `EhUrl.tag` / `EhUrl.search` 处理。
 */
export function tagQueryOf(namespace: string, tag: string): string {
  return `${namespace}:${tag}`;
}

/**
 * 解析详情页 HTML → `GalleryDetail`（源 `GalleryDetailParser` 的核心字段子集）。
 * 缺少标题（`#gn`）时返回 `null`。`thumbSize` 透传设置（封面同样改写，默 0）。
 */
export class GalleryDetailParser {
  /** 最近一次解析的失败/降级原因（见模块注释）。 */
  static lastReason(): string {
    return lastReason;
  }

  static parse(html: string, gid: number, token: string = '', thumbSize: number = 0): GalleryDetail | null {
    lastReason = '';
    if (html.trim().length === 0) {
      lastReason = 'empty body';
      return null;
    }
    const root: HtmlNode = Html.parse(html);

    const gn: HtmlNode[] = Html.select(root, '#gn');
    if (gn.length === 0) {
      lastReason = 'no #gn';
      return null;
    }
    const title: string = Html.text(gn[0]).trim();

    let titleJpn: string = '';
    const gj: HtmlNode[] = Html.select(root, '#gj');
    if (gj.length > 0) {
      titleJpn = Html.text(gj[0]).trim();
    }

    let category: number = 0;
    const gdc: HtmlNode[] = Html.select(root, '#gdc');
    if (gdc.length > 0) {
      const cs: HtmlNode[] = Html.select(gdc[0], '.cs');
      if (cs.length > 0) {
        category = categoryOf(Html.text(cs[0]).trim());
      }
    }

    let uploader: string = '';
    const gdn: HtmlNode[] = Html.select(root, '#gdn');
    if (gdn.length > 0) {
      const a: HtmlNode[] = Html.select(gdn[0], 'a');
      if (a.length > 0) {
        uploader = Html.text(a[0]).trim();
      }
    }

    let rating: number = 0;
    const ratingLabel: HtmlNode[] = Html.select(root, '#rating_label');
    if (ratingLabel.length > 0) {
      const m: RegExpMatchArray | null = Html.text(ratingLabel[0]).match(AVERAGE);
      if (m !== null) {
        rating = Number.parseFloat(m[1]);
      }
    }
    if (rating === 0) {
      const ratingImage: HtmlNode[] = Html.select(root, '#rating_image');
      if (ratingImage.length > 0) {
        const style: string | null = Html.attr(ratingImage[0], 'style');
        if (style !== null) {
          rating = ratingFromStyle(style);
        }
      }
    }

    let pages: number = 0;
    const lengthRow: RegExpMatchArray | null = html.match(LENGTH_PAGES);
    if (lengthRow !== null) {
      const n: number = Number.parseInt(lengthRow[1].replace(/,/g, ''), 10);
      pages = isNaN(n) ? 0 : n;
    } else {
      // 有标题但没有页数行：站点版式变了（或页面被截断），留给上层记日志。
      lastReason = 'no Length row';
    }

    const tags: TagGroup[] = GalleryDetailParser.parseTagGroupsFrom(root);

    // 收藏态（源 `GalleryDetailParser`：`#gdf` 文本不是 `Add to Favorites` 即已收藏，文本是收藏夹名）。
    let isFavorited: boolean = false;
    let favoriteName: string = '';
    const gdf: HtmlNode[] = Html.select(root, '#gdf');
    if (gdf.length > 0) {
      const favText: string = Html.text(gdf[0]).trim();
      if (favText.length > 0 && favText !== ADD_TO_FAVORITES) {
        isFavorited = true;
        favoriteName = favText;
      }
    }

    const keys: RegExpMatchArray | null = html.match(API_KEYS);
    let apiUid: number = -1;
    let apiKey: string = '';
    if (keys !== null) {
      apiUid = Number.parseInt(keys[3], 10);
      if (isNaN(apiUid)) {
        apiUid = -1;
      }
      apiKey = keys[4];
    }

    const detail: GalleryDetail = {
      gid: gid,
      token: token,
      title: title,
      titleJpn: titleJpn,
      category: category,
      uploader: uploader,
      posted: '',
      rating: rating,
      ratingCount: GalleryDetailParser.parseRatingCount(html),
      pages: pages,
      thumb: EhUrl.thumbResolution(GalleryDetailParser.parseCoverFrom(root), thumbSize),
      tagGroups: tags,
      previewTokens: GalleryDetailParser.parsePreviewTokens(html, gid),
      previews: GalleryDetailParser.parsePreviews(html, gid),
      apiUid: apiUid,
      apiKey: apiKey,
      comments: GalleryDetailParser.parseComments(html),
      isFavorited: isFavorited,
      favoriteName: favoriteName
    };
    return detail;
  }

  /** 从详情页提取预览页 pToken（`/s/<pToken>/<gid>-<page>`），按页序放入数组。 */
  static parsePreviewTokens(html: string, gid: number): string[] {
    const tokens: string[] = [];
    const re: RegExp = new RegExp('/s/([0-9a-f]{10})/' + gid + '-(\\d+)', 'g');
    const found: RegExpMatchArray | null = html.match(re);
    if (found !== null) {
      for (let i = 0; i < found.length; i++) {
        const parts: string[] = found[i].split('/');
        if (parts.length < 4) {
          continue;
        }
        const pToken: string = parts[2];
        const dash: number = parts[3].indexOf('-');
        if (dash < 0) {
          continue;
        }
        const page: number = Number.parseInt(parts[3].substring(dash + 1), 10);
        if (!isNaN(page) && page > 0) {
          tokens[page - 1] = pToken;
        }
      }
    }
    return tokens;
  }

  /**
   * 解析评论区（源 `GalleryDetailParser.parseComments` 的展示子集）：
   * `#cdiv > .c1` 逐块取用户 / 原文时间 / 纯文本正文 / 分数。
   * 正文只取 `textContent`（不渲染 HTML）；`id` 为列表序号（投票/编辑不在本期）。
   */
  static parseComments(html: string): GalleryComment[] {
    const list: GalleryComment[] = [];
    const root: HtmlNode = Html.parse(html);
    const cdiv: HtmlNode[] = Html.select(root, '#cdiv');
    if (cdiv.length === 0) {
      return list;
    }
    const blocks: HtmlNode[] = Html.select(cdiv[0], '.c1');
    for (let i = 0; i < blocks.length; i++) {
      const block: HtmlNode = blocks[i];
      let user: string = '';
      let time: string = '';
      const c3: HtmlNode[] = Html.select(block, '.c3');
      if (c3.length > 0) {
        const raw: string = Html.text(c3[0]);
        const m: RegExpMatchArray | null = raw.match(COMMENT_TIME);
        if (m !== null) {
          time = m[1].trim();
        }
        const anchors: HtmlNode[] = Html.select(c3[0], 'a');
        if (anchors.length > 0) {
          user = Html.text(anchors[0]).trim();
        }
      }
      let text: string = '';
      const c6: HtmlNode[] = Html.select(block, '.c6');
      if (c6.length > 0) {
        text = Html.text(c6[0]).trim();
      }
      if (user.length === 0 && text.length === 0) {
        continue;
      }
      const comment: GalleryComment = { id: i, user: user, time: time, text: text };
      const c5: HtmlNode[] = Html.select(block, '.c5');
      if (c5.length > 0) {
        const sm: RegExpMatchArray | null = Html.text(c5[0]).match(SCORE_NUM);
        if (sm !== null) {
          comment.score = Number.parseInt(sm[0], 10);
        }
      }
      list.push(comment);
    }
    return list;
  }

  /**
   * 封面图（源 `GalleryDetailParser.parseCoverStyle`）：
   * `#gd1` 下诸 `div` 中首个 `style` 命中 `COVER` 者，第 3 组即 URL。
   * 无命中回 `''`（无封面是常态，不抛；不记日志，避免刷屏）。
   * 注意：`Html.select` 的标签分支（含 domutils 标准语义）会把作用域节点自身
   * 也计入结果（`#gd1` 本身就是 `div`），故逐个扫描而非固定取 `[0]`。
   * 分辨率重写不在此做：调用方 `parse()` 统一经 `EhUrl.thumbResolution`（源
   * `EhUtils.handleThumbUrlResolution`，设置 0 原图 / 1 `_250` / 2 `_300`）。
   */
  static parseCover(html: string): string {
    return GalleryDetailParser.parseCoverFrom(Html.parse(html));
  }

  /** `parseCover` 的文档复用版（`parse()` 已持有 `root` 时用，少一次解析）。 */
  static parseCoverFrom(root: HtmlNode): string {
    const gd1: HtmlNode[] = Html.select(root, '#gd1');
    if (gd1.length === 0) {
      return '';
    }
    const divs: HtmlNode[] = Html.select(gd1[0], 'div');
    for (let i = 0; i < divs.length; i++) {
      const style: string | null = Html.attr(divs[i], 'style');
      if (style === null) {
        continue;
      }
      const m: RegExpMatchArray | null = style.match(COVER);
      if (m !== null) {
        return m[3];
      }
    }
    return '';
  }

  /**
   * 预览项（`#gdt > a`：href 取 `/s/<pToken>/<gid>-<page>`，首子 div `style` 取 `url()` 缩略图）。
   * 任一步缺失跳过该项；`#gdt` 缺失回 `[]`。`page` 转内部 0 起。
   */
  static parsePreviews(html: string, gid: number): PreviewItem[] {
    const items: PreviewItem[] = [];
    const root: HtmlNode = Html.parse(html);
    const gdt: HtmlNode[] = Html.select(root, '#gdt');
    if (gdt.length === 0) {
      return items;
    }
    const anchors: HtmlNode[] = Html.select(gdt[0], 'a');
    const re: RegExp = new RegExp('/s/([0-9a-f]{10})/' + gid + '-(\\d+)');
    for (let i = 0; i < anchors.length; i++) {
      const href: string | null = Html.attr(anchors[i], 'href');
      if (href === null) {
        continue;
      }
      const m: RegExpMatchArray | null = href.match(re);
      if (m === null) {
        continue;
      }
      const page: number = Number.parseInt(m[2], 10);
      if (isNaN(page) || page <= 0) {
        continue;
      }
      const divs: HtmlNode[] = Html.select(anchors[i], 'div');
      if (divs.length === 0) {
        continue;
      }
      const style: string | null = Html.attr(divs[0], 'style');
      if (style === null) {
        continue;
      }
      const img: RegExpMatchArray | null = style.match(PREVIEW_IMG);
      if (img === null) {
        continue;
      }
      const box: RegExpMatchArray | null = style.match(PREVIEW_BOX);
      const off: RegExpMatchArray | null = style.match(PREVIEW_OFF);
      if (box === null || off === null) {
        continue;
      }
      const w: number = Number.parseInt(box[1], 10);
      const h: number = Number.parseInt(box[2], 10);
      if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) {
        continue;
      }
      const x: number = Math.abs(Number.parseInt(off[1], 10));
      const y: number = Math.abs(Number.parseInt(off[2], 10));
      if (isNaN(x) || isNaN(y)) {
        continue;
      }
      items.push({ page: page - 1, pToken: m[1], imageUrl: img[1], x: x, y: y, w: w, h: h });
    }
    return items;
  }

  /** 标签分组（`#taglist tr` 逐行：`.tc` 去尾冒号为组名 + 行内 `a` 文本；无组名行并入 `other`；空组不收录）。 */
  static parseTagGroups(html: string): TagGroup[] {
    return GalleryDetailParser.parseTagGroupsFrom(Html.parse(html));
  }

  /** `parseTagGroups` 的文档复用版（`parse()` 已持有 `root` 时用，少一次解析）。 */
  static parseTagGroupsFrom(root: HtmlNode): TagGroup[] {
    const groups: TagGroup[] = [];
    const taglist: HtmlNode[] = Html.select(root, '#taglist');
    if (taglist.length === 0) {
      return groups;
    }
    const rows: HtmlNode[] = Html.select(taglist[0], 'tr');
    for (let r = 0; r < rows.length; r++) {
      let namespace: string = 'other';
      const tcs: HtmlNode[] = Html.select(rows[r], '.tc');
      if (tcs.length > 0) {
        const raw: string = Html.text(tcs[0]).trim();
        const name: string = raw.endsWith(':') ? raw.substring(0, raw.length - 1) : raw;
        if (name.length > 0) {
          namespace = name;
        }
      }
      const tags: string[] = [];
      const anchors: HtmlNode[] = Html.select(rows[r], 'a');
      for (let i = 0; i < anchors.length; i++) {
        // 站点会在部分标签后追加「| 英文译名」（源 `GalleryDetailParser.parseTagGroup` 同处理：
        // *Sometimes parody tag is followed with '|' and english translate, just remove them*）。
        // 只截显示/搜索串，命名空间不变；截断后为空则跳过。
        const raw: string = Html.text(anchors[i]).trim();
        const pipe: number = raw.indexOf('|');
        const text: string = pipe >= 0 ? raw.substring(0, pipe).trim() : raw;
        if (text.length > 0) {
          tags.push(text);
        }
      }
      if (tags.length === 0) {
        continue;
      }
      let group: TagGroup | null = null;
      for (let g = 0; g < groups.length; g++) {
        if (groups[g].namespace === namespace) {
          group = groups[g];
          break;
        }
      }
      if (group === null) {
        group = { namespace: namespace, tags: [] };
        groups.push(group);
      }
      for (let t = 0; t < tags.length; t++) {
        group.tags.push(tags[t]);
      }
    }
    return groups;
  }

  /** 投票数（`#rating_count`；缺失为 0）。 */
  static parseRatingCount(html: string): number {
    const root: HtmlNode = Html.parse(html);
    const nodes: HtmlNode[] = Html.select(root, '#rating_count');
    if (nodes.length === 0) {
      return 0;
    }
    const count: number = Number.parseInt(Html.text(nodes[0]).trim(), 10);
    return isNaN(count) ? 0 : count;
  }
}
