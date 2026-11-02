/**
 * 标签翻译快照（`tagdb.v1.tsv`）的格式层：**纯函数**，不碰文件、不碰 context、不碰 UI。
 *
 * 为什么单独一层：解析结果既来自打包内置的 rawfile，也来自设备端现转的更新文件（`TagDbConvert`），
 * 两边必须走同一套校验，否则"内置的没事、更新后写坏"会变成只在部分用户身上出现的延迟 bug。
 * 因此这里对格式问题一律抛错（错误优先暴露），由加载器决定是忽略该份还是上抛。
 */
import { TagCandidate } from './TagCandidate';

/** 快照格式版本；与文件头 `#tagdb` 第二列不等 = 别的格式，不猜、直接抛错。 */
export const TAGDB_FORMAT: number = 1;

export interface TagDbMeta {
  format: number;
  /** 上游 `head.sha`，只用来判断"是不是同一份数据"，不参与解析。 */
  sha: string;
  /** 生成时间 ISO8601 UTC；加载器按字典序比较新鲜度。 */
  builtAt: string;
}

export interface TagDbData {
  meta: TagDbMeta;
  /** 命名空间 → 中文名（含伪命名空间 `rows`）。 */
  nsNames: Map<string, string>;
  /** `ns + ':' + tag`，严格升序（二分查找的前提）。 */
  keys: string[];
  /** 与 `keys` 平行的中文名。 */
  names: string[];
  /** `#intro` 段原文（未解码）；44.8k 里有 3.2 万条没有释义，全量建表不划算，留给 `introOf` 懒解析。 */
  introRaw: string;
  /** 懒解析产物；`undefined` = 还没建过表。 */
  intros: Map<string, string> | undefined;
}

const SEG_TAGDB: string = '#tagdb';
const SEG_SOURCE: string = '#source';
const SEG_ROWS: string = '#rows';
const SEG_TAGS: string = '#tags';
const SEG_INTRO: string = '#intro';

/**
 * 只读首行的格式版本，**不解析正文**。
 *
 * 为什么单独暴露：`parseTagDb` 对任何问题都抛错，而加载规则要把「别的格式 → 忽略、不删」
 * 与「自称本格式却解析不了 → 删除/上抛」分开。返回 `undefined` 表示首行不是
 * `#tagdb\t<纯数字>`（别的格式族或生成器写坏），由调用方决定处置；纯数字才返回版本号，
 * 所以 `1.0` / `v2` 不会被误判成「未来的版本」而保留。
 */
export function peekFormat(text: string): number | undefined {
  const end: number = text.indexOf('\n');
  const head: string = end < 0 ? text : text.substring(0, end);
  const cols: string[] = head.split('\t');
  if (cols.length !== 2 || cols[0] !== SEG_TAGDB || cols[1].length === 0) {
    return undefined;
  }
  for (let i = 0; i < cols[1].length; i++) {
    const ch: string = cols[1].charAt(i);
    if (ch < '0' || ch > '9') {
      return undefined;
    }
  }
  return Number(cols[1]);
}

/**
 * 字段 → 单行安全文本。顺序必须是先 `\` 再 TAB/LF，否则转义出来的反斜杠会被二次转义；
 * CR 直接丢弃——行分隔用 LF，CR 只可能来自上游 JSON 里的 CRLF，留着会让字段末尾多一个隐形字符。
 */
export function escapeField(raw: string): string {
  return raw.replaceAll('\\', '\\\\').replaceAll('\t', '\\t').replaceAll('\n', '\\n').replaceAll('\r', '');
}

/**
 * `escapeField` 的严格逆运算。
 * 只认 `\\` / `\t` / `\n`；未知转义与末尾孤立反斜杠原样保留——吞掉它们会让"数据里有反斜杠"
 * 这种情况被静默改写，而正确写法（`\\`）已经能表达反斜杠本身。
 */
export function unescapeField(raw: string): string {
  let out: string = '';
  let i: number = 0;
  while (i < raw.length) {
    const ch: string = raw.charAt(i);
    if (ch !== '\\') {
      out += ch;
      i++;
      continue;
    }
    const next: string = i + 1 < raw.length ? raw.charAt(i + 1) : '';
    if (next === '\\') {
      out += '\\';
      i += 2;
    } else if (next === 't') {
      out += '\t';
      i += 2;
    } else if (next === 'n') {
      out += '\n';
      i += 2;
    } else {
      out += ch;
      i++;
    }
  }
  return out;
}

/**
 * 解析整份快照。
 *
 * 校验的都是"错了之后二分/回退会静默给出错误结果"的东西：头格式、`#source` 存在、三段齐全且 `#tags` 非空、
 * `#tags` 严格递增（含唯一）、每行列数。之所以用原始（未转义）key 校验递增：查询时比对的也是未转义 key，
 * 转义序与解码序在包含 TAB/LF 的极端值上会不一致，按转义序放行会让二分漏命中。
 */
export function parseTagDb(text: string): TagDbData {
  // 格式规定换行只用 LF、字段内 CR 必须已被丢弃；出现裸 CR 说明文件被别的工具用 CRLF 写过，
  // 那样每行末尾都会带一个不可见字符，译名/释义里嵌 CR，UI 上表现为莫名换行——直接拒绝。
  if (text.indexOf('\r') >= 0) {
    throw new Error('tagdb: 含未转义的 CR（换行应只用 LF）');
  }
  const lines: string[] = text.split('\n');
  if (lines.length === 0 || lines[0].length === 0) {
    throw new Error('tagdb: 空文件');
  }
  // 版本规则只在 `peekFormat` 里定义一次（加载器用同一个函数判断是不是本格式族）。
  const version: number | undefined = peekFormat(text);
  if (version === undefined) {
    throw new Error(`tagdb: 首行不是 ${SEG_TAGDB}\t<版本>，而是 "${lines[0]}"`);
  }
  // `peekFormat` 只认纯数字版本，所以 `1.0` / `0x1` 这类写法在上面就已经判成 undefined（不是本格式），
  // 不会因为 `Number()` 的宽松解析被放进来。
  if (version !== TAGDB_FORMAT) {
    throw new Error(`tagdb: 格式版本 ${version} != ${TAGDB_FORMAT}`);
  }
  const format: number = TAGDB_FORMAT;

  let sha: string = '';
  let builtAt: string = '';
  const nsNames: Map<string, string> = new Map<string, string>();
  const keys: string[] = [];
  const names: string[] = [];
  const introLines: string[] = [];
  let section: string = '';
  let seenSource: boolean = false;
  let seenRows: boolean = false;
  let seenTags: boolean = false;
  let seenIntro: boolean = false;
  let prevKey: string = '';

  for (let n = 1; n < lines.length; n++) {
    const line: string = lines[n];
    if (line.length === 0) {
      continue;
    }
    if (line.startsWith('#')) {
      const cols: string[] = line.split('\t');
      switch (cols[0]) {
        case SEG_SOURCE:
          if (cols.length !== 3) {
            throw new Error(`tagdb: #source 行有 ${cols.length} 列（应 3 列，第 ${n + 1} 行）`);
          }
          sha = cols[1];
          builtAt = cols[2];
          seenSource = true;
          section = '';
          break;
        case SEG_ROWS:
          section = 'rows';
          seenRows = true;
          break;
        case SEG_TAGS:
          section = 'tags';
          seenTags = true;
          break;
        case SEG_INTRO:
          section = 'intro';
          seenIntro = true;
          break;
        default:
          throw new Error(`tagdb: 未知段头 "${cols[0]}"（第 ${n + 1} 行）`);
      }
      continue;
    }
    if (section === 'rows') {
      const cols: string[] = line.split('\t');
      if (cols.length !== 2) {
        throw new Error(`tagdb: #rows 行有 ${cols.length} 列（应 2 列，第 ${n + 1} 行）`);
      }
      nsNames.set(unescapeField(cols[0]), unescapeField(cols[1]));
    } else if (section === 'tags') {
      const cols: string[] = line.split('\t');
      if (cols.length !== 3) {
        throw new Error(`tagdb: #tags 行有 ${cols.length} 列（应 3 列，第 ${n + 1} 行）`);
      }
      const ns: string = unescapeField(cols[0]);
      const tag: string = unescapeField(cols[1]);
      const key: string = `${ns}:${tag}`;
      // 严格递增同时覆盖"重复"：相等也抛（重复 key 会让二分命中哪一条变得不确定）。
      if (!(key > prevKey)) {
        throw new Error(`tagdb: #tags 未按 key 严格递增："${key}" 不大于 "${prevKey}"（第 ${n + 1} 行）`);
      }
      prevKey = key;
      keys.push(key);
      names.push(unescapeField(cols[2]));
    } else if (section === 'intro') {
      const cols: string[] = line.split('\t');
      if (cols.length !== 3) {
        throw new Error(`tagdb: #intro 行有 ${cols.length} 列（应 3 列，第 ${n + 1} 行）`);
      }
      // 只在解析期验结构；建表留给 introOf，省掉存活期内的第二份 Map。
      introLines.push(line);
    } else {
      throw new Error(`tagdb: 第 ${n + 1} 行不在任何段内："${line}"`);
    }
  }

  // `#source` 缺了也能解析的话，`sha` / `builtAt` 是空串：状态行会显示「内置快照 ·  · 44,795 条」，
  // 更新流程的「是否已是最新」也失去依据——直接拒绝。
  if (!seenSource) {
    throw new Error('tagdb: 缺 #source 段');
  }
  if (!seenRows || !seenTags || !seenIntro) {
    throw new Error('tagdb: #rows / #tags / #intro 三段必须齐全');
  }
  // 空 `#tags`（只有段头没有行）是"加载出来 0 条还不报错"的唯一来源：宁可让加载器删掉这份。
  if (keys.length === 0) {
    throw new Error('tagdb: #tags 段为空');
  }

  const meta: TagDbMeta = { format: format, sha: sha, builtAt: builtAt };
  return {
    meta: meta,
    nsNames: nsNames,
    keys: keys,
    names: names,
    introRaw: introLines.join('\n'),
    intros: undefined
  };
}

/** 升序数组上的精确查找；找不到回 -1。比较用 `<`（UTF-16 码元序），不用 `localeCompare`。 */
function indexOfKey(keys: string[], key: string): number {
  let lo: number = 0;
  let hi: number = keys.length - 1;
  while (lo <= hi) {
    const mid: number = Math.floor((lo + hi) / 2);
    const cur: string = keys[mid];
    if (cur === key) {
      return mid;
    }
    if (cur < key) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

/**
 * 精确 `ns:tag`，未命中再试整串小写一次。
 * 为什么要有小写兜底：站点对标签值大小写不敏感（`Sample Tags` 与 `sample tags` 同一条），
 * 用户从网页复制来的串可能大小写不同，但快照里只存上游原文。
 */
function lookupTagIndex(db: TagDbData, ns: string, tag: string): number {
  const exact: string = `${ns}:${tag}`;
  let at: number = indexOfKey(db.keys, exact);
  if (at >= 0) {
    return at;
  }
  const lower: string = exact.toLowerCase();
  if (lower !== exact) {
    at = indexOfKey(db.keys, lower);
  }
  return at;
}

/** 未命中回退原文 `tag`（不是空串、不是占位符：没数据时界面必须和没装翻译一模一样）。 */
export function translateTagOf(db: TagDbData, ns: string, tag: string): string {
  const at: number = lookupTagIndex(db, ns, tag);
  return at >= 0 ? db.names[at] : tag;
}

/** 未命中回退原文 `ns`。 */
export function translateNsOf(db: TagDbData, ns: string): string {
  const name: string | undefined = db.nsNames.get(ns);
  return name === undefined ? ns : name;
}

/** `#intro` 原文 → `ns:tag` → 释义。首次调用才建表，之后复用。 */
function introsOf(db: TagDbData): Map<string, string> {
  const cached: Map<string, string> | undefined = db.intros;
  if (cached !== undefined) {
    return cached;
  }
  const map: Map<string, string> = new Map<string, string>();
  const lines: string[] = db.introRaw.length === 0 ? [] : db.introRaw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const cols: string[] = lines[i].split('\t');
    // 列数在 parseTagDb 已校验过；这里再判一次是因为懒解析可能发生在任意查询里，
    // 与其越界拿 undefined，不如把"文件被改坏了"直接抛出来。
    if (cols.length !== 3) {
      throw new Error(`tagdb: #intro 行有 ${cols.length} 列（应 3 列）`);
    }
    map.set(`${unescapeField(cols[0])}:${unescapeField(cols[1])}`, unescapeField(cols[2]));
  }
  db.intros = map;
  return map;
}

/** 释义；没有则 `''`（UI 用空串判断"不显示释义入口"）。 */
export function introOf(db: TagDbData, ns: string, tag: string): string {
  const map: Map<string, string> = introsOf(db);
  let text: string | undefined = map.get(`${ns}:${tag}`);
  if (text === undefined) {
    // 与 translateTagOf 的小写兜底保持一致，否则会出现"译名有、释义没"的错位。
    const lower: string = `${ns}:${tag}`.toLowerCase();
    if (lower !== `${ns}:${tag}`) {
      text = map.get(lower);
    }
  }
  return text === undefined ? '' : text;
}

/** 排序中间态：`index` 指回 `keys`/`names`，`key` 直接参与同分比较。 */
interface ScoredKey {
  score: number;
  key: string;
  index: number;
}

/**
 * 分数规则（spec §3）：名字全等 0 / 名字前缀 1 / 名字包含 2 / 英文 tag 前缀 3（大小写不敏感）。
 * 排序 `(score ↑, 命中列长度 ↑, key ↑)`：同分优先短的那个（更贴近用户想找的），再按字典序保证稳定可预期。
 *
 * 长度取「用户真正在比对的那一列」：按中文名命中的看名字长度，按英文 tag 前缀命中的看 tag 长度——
 * 后者用中文名长度排序毫无意义（`parody:blue archive` 的中文名可能很短，却排在 `parody:blue` 前面）。
 */
function compareScored(a: ScoredKey, b: ScoredKey, names: string[], keys: string[]): number {
  if (a.score !== b.score) {
    return a.score - b.score;
  }
  const la: number = matchedLength(a, names, keys);
  const lb: number = matchedLength(b, names, keys);
  if (la !== lb) {
    return la - lb;
  }
  if (a.key === b.key) {
    return 0;
  }
  return a.key < b.key ? -1 : 1;
}

/** 命中列的长度：score 3 是英文 tag，其余是中文名。 */
function matchedLength(hit: ScoredKey, names: string[], keys: string[]): number {
  if (hit.score !== 3) {
    return names[hit.index].length;
  }
  const key: string = keys[hit.index];
  return key.length - key.indexOf(':') - 1;
}

/** 联想：`kw` 为空（或 `limit <= 0`）直接空数组，其余按分数取前 `limit` 条。 */
export function searchTags(db: TagDbData, kw: string, limit: number): TagCandidate[] {
  const query: string = kw.trim();
  if (query.length === 0 || limit <= 0) {
    return [];
  }
  const queryLower: string = query.toLowerCase();
  const hits: ScoredKey[] = [];
  for (let i = 0; i < db.keys.length; i++) {
    const key: string = db.keys[i];
    const name: string = db.names[i];
    let score: number = -1;
    if (name === query) {
      score = 0;
    } else if (name.startsWith(query)) {
      score = 1;
    } else if (name.indexOf(query) >= 0) {
      score = 2;
    } else {
      const tag: string = key.substring(key.indexOf(':') + 1);
      if (tag.toLowerCase().startsWith(queryLower)) {
        score = 3;
      }
    }
    if (score >= 0) {
      const hit: ScoredKey = { score: score, key: key, index: i };
      hits.push(hit);
    }
  }
  hits.sort((a: ScoredKey, b: ScoredKey): number => compareScored(a, b, db.names, db.keys));
  const count: number = Math.min(limit, hits.length);
  const out: TagCandidate[] = [];
  for (let i = 0; i < count; i++) {
    const hit: ScoredKey = hits[i];
    const at: number = hit.key.indexOf(':');
    const ns: string = hit.key.substring(0, at);
    const tag: string = hit.key.substring(at + 1);
    out.push({ ns: ns, tag: tag, name: db.names[hit.index], intro: introOf(db, ns, tag) });
  }
  return out;
}
