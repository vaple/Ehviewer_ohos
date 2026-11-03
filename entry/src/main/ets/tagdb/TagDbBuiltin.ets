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
export const BUILTIN_SHA: string = '155790ce55900fb0fa0f1b4e270a694940c04446';
export const BUILTIN_BUILT_AT: string = '2026-11-03T07:05:20Z';
export const BUILTIN_COUNT: number = 44817;
export const BUILTIN_ETAG: string = '"36029e3d55195c06b99f556743bdb3cc2aad35947d4eb4a90da7e9caea954515"';
