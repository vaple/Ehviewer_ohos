/**
 * 内置快照 `rawfile/tagdb.v1.tsv` 的元信息。
 *
 * **由 `scripts/tagdb/build_tagdb.py` 生成，不要手改**：值与 TSV 的 `#source` 是同一次生成的产物，
 * `--check` 会逐字比对；手改等于让「内置快照的生成时间」和实际文件说的不是一回事。
 *
 * 为什么编成常量：加载器要判断沙箱副本是否比内置新。读 TSV 头部得先把整份 3 MB 文本读进来，
 * 而省掉这一步正是冷启动的目标；编进代码后比较只是一次字符串比较。
 *
 * `BUILTIN_ETAG` 只被构建期用（条件请求判断上游有没有变），运行期从不读它。
 */
export const BUILTIN_SHA: string = '3124985720e542fd666e856342ce9f7b5f12e970';
export const BUILTIN_BUILT_AT: string = '2026-11-02T16:44:14Z';
export const BUILTIN_COUNT: number = 44816;
export const BUILTIN_ETAG: string = '"2a50f89cbd4ef1dab5139e0c12476342bc7ba3fd15a16946dec26da84d963eb4"';
