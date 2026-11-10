import { describe, it, expect } from '@ohos/hypium';
import { PreviewChunk, PreviewChunkStore } from '../../main/ets/service/PreviewChunkStore';
import { PreviewItem } from '../../main/ets/model/PreviewItem';

function item(page: number, token: string): PreviewItem {
  return { page: page, pToken: token, imageUrl: `https://x/${page}.jpg`,
    x: 0, y: 0, w: 100, h: 150 };
}

export default function previewChunkStoreTest() {
  describe('PreviewChunkStore', () => {
    it('concurrent_ensure_for_same_chunk_loads_once', 0, async () => {
      let loads: number = 0;
      const store: PreviewChunkStore = new PreviewChunkStore();
      const fetch: () => Promise<PreviewItem[]> = async () => {
        loads += 1;
        return [item(20, 't20'), item(21, 't21')];
      };
      const results: PreviewChunk[] = await Promise.all([
        store.ensure(1, 1, fetch), store.ensure(1, 1, fetch)
      ]);
      expect(loads).assertEqual(1);
      expect(results[0].tokens[20]).assertEqual('t20');
      expect(results[0].cells.length).assertEqual(2);
      expect(results[1].cells[1].page).assertEqual(21);
    });

    it('cached_chunk_does_not_refetch', 0, async () => {
      let loads: number = 0;
      const store: PreviewChunkStore = new PreviewChunkStore();
      const fetch: () => Promise<PreviewItem[]> = async () => {
        loads += 1;
        return [item(0, 't0')];
      };
      await store.ensure(1, 0, fetch);
      await store.ensure(1, 0, fetch);
      expect(loads).assertEqual(1);
    });

    it('failed_chunk_cools_down_then_retries', 0, async () => {
      let loads: number = 0;
      let now: number = 1000;
      const store: PreviewChunkStore = new PreviewChunkStore(() => now, 3000);
      const failing: () => Promise<PreviewItem[]> = async () => {
        loads += 1;
        throw new Error('boom');
      };
      let first: boolean = false;
      try { await store.ensure(1, 0, failing); } catch (e) { first = true; }
      expect(first).assertTrue();
      let second: boolean = false;
      try { await store.ensure(1, 0, failing); } catch (e) { second = true; }
      expect(second).assertTrue();
      expect(loads).assertEqual(1);
      now += 3000;
      await store.ensure(1, 0, async (): Promise<PreviewItem[]> => {
        loads += 1;
        return [item(0, 't0')];
      });
      expect(loads).assertEqual(2);
    });

    it('seed_maps_tokens_and_does_not_overwrite', 0, async () => {
      let loads: number = 0;
      const store: PreviewChunkStore = new PreviewChunkStore();
      const seeded: PreviewChunk = store.seed(9, 0, [item(0, 'a'), item(19, 'b')]);
      expect(seeded.tokens[0]).assertEqual('a');
      expect(seeded.tokens[19]).assertEqual('b');
      const again: PreviewChunk = store.seed(9, 0, [item(0, 'z')]);
      expect(again.tokens[0]).assertEqual('a');
      await store.ensure(9, 0, async (): Promise<PreviewItem[]> => {
        loads += 1;
        return [];
      });
      expect(loads).assertEqual(0);
    });

    it('gid_change_clears_previous_gallery', 0, async () => {
      const store: PreviewChunkStore = new PreviewChunkStore();
      store.seed(1, 0, [item(0, 'a')]);
      expect(store.peek(1, 0) !== undefined).assertTrue();
      store.seed(2, 0, [item(0, 'b')]);
      expect(store.peek(1, 0) === undefined).assertTrue();
      expect(store.peek(2, 0)?.tokens[0]).assertEqual('b');
    });

    it('stale_response_after_gid_change_is_not_cached', 0, async () => {
      const store: PreviewChunkStore = new PreviewChunkStore();
      let release: (items: PreviewItem[]) => void = (_items: PreviewItem[]) => {};
      const slow: Promise<PreviewItem[]> = new Promise<PreviewItem[]>(
        (resolve: (items: PreviewItem[]) => void) => { release = resolve; });
      const pending: Promise<PreviewChunk> = store.ensure(1, 0, () => slow);
      store.seed(2, 0, [item(0, 'b')]);
      release([item(0, 'a')]);
      let failed: boolean = false;
      try { await pending; } catch (e) { failed = true; }
      expect(failed).assertTrue();
      expect(store.peek(2, 0)?.tokens[0]).assertEqual('b');
      expect(store.peek(2, 0)?.cells.length).assertEqual(1);
    });

    it('empty_result_is_failure_and_not_cached', 0, async () => {
      let loads: number = 0;
      let now: number = 1000;
      const store: PreviewChunkStore = new PreviewChunkStore(() => now, 3000);
      const empty: () => Promise<PreviewItem[]> = async () => {
        loads += 1;
        return [];
      };
      let first: boolean = false;
      try { await store.ensure(1, 0, empty); } catch (e) { first = true; }
      expect(first).assertTrue();
      expect(store.peek(1, 0) === undefined).assertTrue();
      // 冷却期内第二次不再发请求（空块不能永久钉住）。
      let second: boolean = false;
      try { await store.ensure(1, 0, empty); } catch (e) { second = true; }
      expect(second).assertTrue();
      expect(loads).assertEqual(1);
      now += 3000;
      const ok: PreviewChunk = await store.ensure(1, 0, async (): Promise<PreviewItem[]> => {
        loads += 1;
        return [item(0, 't0')];
      });
      expect(loads).assertEqual(2);
      expect(ok.cells.length).assertEqual(1);
    });

    it('seed_with_empty_items_does_not_pin_chunk', 0, async () => {
      let loads: number = 0;
      const store: PreviewChunkStore = new PreviewChunkStore();
      store.seed(1, 0, []);
      expect(store.peek(1, 0) === undefined).assertTrue();
      const ok: PreviewChunk = await store.ensure(1, 0, async (): Promise<PreviewItem[]> => {
        loads += 1;
        return [item(0, 't0')];
      });
      expect(loads).assertEqual(1);
      expect(ok.tokens[0]).assertEqual('t0');
    });
  });
}
