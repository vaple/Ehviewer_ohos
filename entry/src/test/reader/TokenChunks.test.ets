import { describe, it, expect } from '@ohos/hypium';
import { TokenChunks } from '../../main/ets/reader/TokenChunks';

/** 绝对页号-1 索引（与 `GalleryDetailParser.parsePreviewTokens` 的约定一致）。 */
function chunkTokens(pages: number[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < pages.length; i++) {
    out[pages[i]] = `tok${pages[i]}`;
  }
  return out;
}

export default function tokenChunksTest() {
  describe('TokenChunks', () => {
    it('concurrent_ensure_for_same_chunk_loads_once', 0, async () => {
      let loads: number = 0;
      const tokens: string[] = chunkTokens([20, 21]);
      const chunks: TokenChunks = new TokenChunks(async (_chunk: number): Promise<string[]> => {
        loads += 1;
        return tokens;
      }, 20);
      const results: (string | undefined)[] = await Promise.all([
        chunks.ensure(20), chunks.ensure(21), chunks.ensure(22), chunks.ensure(23)
      ]);
      // 4 个并发调用落在同一个 chunk：只允许发一次。
      expect(loads).assertEqual(1);
      expect(results[0]).assertEqual('tok20');
      expect(results[1]).assertEqual('tok21');
      expect(results[2] === undefined).assertTrue();
    });

    it('failed_load_is_retried', 0, async () => {
      let loads: number = 0;
      const tokens: string[] = chunkTokens([20]);
      const chunks: TokenChunks = new TokenChunks(async (_chunk: number): Promise<string[]> => {
        loads += 1;
        if (loads === 1) {
          throw new Error('boom');
        }
        return tokens;
      }, 20);
      let firstFailed: boolean = false;
      try {
        await chunks.ensure(20);
      } catch (e) {
        firstFailed = true;
      }
      expect(firstFailed).assertTrue();
      // 失败的 promise 必须被摘掉，否则这个 chunk 之后永远拿到 rejected。
      expect(await chunks.ensure(20)).assertEqual('tok20');
      expect(loads).assertEqual(2);
    });

    it('put_supplies_token_without_loading', 0, async () => {
      let loads: number = 0;
      const chunks: TokenChunks = new TokenChunks(async (_chunk: number): Promise<string[]> => {
        loads += 1;
        return [];
      }, 20);
      chunks.put(41, 'next41');
      expect(await chunks.ensure(41)).assertEqual('next41');
      expect(loads).assertEqual(0);
    });

    it('different_chunks_load_separately', 0, async () => {
      let loads: number = 0;
      const chunks: TokenChunks = new TokenChunks(async (_chunk: number): Promise<string[]> => {
        loads += 1;
        return [];
      }, 20);
      await Promise.all([chunks.ensure(5), chunks.ensure(25)]);
      expect(loads).assertEqual(2);
    });

    it('seed_prefills_first_chunk', 0, async () => {
      let loads: number = 0;
      const chunks: TokenChunks = new TokenChunks(async (_chunk: number): Promise<string[]> => {
        loads += 1;
        return [];
      }, 20);
      chunks.seed(chunkTokens([0, 1, 19]));
      expect(await chunks.ensure(0)).assertEqual('tok0');
      expect(await chunks.ensure(19)).assertEqual('tok19');
      expect(loads).assertEqual(0);
    });
  });
}
