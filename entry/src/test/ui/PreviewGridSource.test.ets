import { describe, it, expect } from '@ohos/hypium';
import { PreviewGridSource, PreviewRow } from '../../main/ets/ui/PreviewGridSource';
import { PreviewCell } from '../../main/ets/model/PreviewCell';

class RecordingListener implements DataChangeListener {
  reloads: number = 0;

  onDataReloaded(): void {
    this.reloads += 1;
  }
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(_index: number): void {}
  onDatasetChange(_operations: DataOperation[]): void {}
}

function cellOf(page: number, url: string): PreviewCell {
  const cell: PreviewCell = new PreviewCell();
  cell.page = page;
  cell.url = url;
  cell.x = 1;
  cell.y = 2;
  cell.w = 200;
  cell.h = 137;
  return cell;
}

export default function previewGridSourceTest() {
  describe('PreviewGridSource', () => {
    it('reset_builds_one_row_per_three_pages', 0, () => {
      const source: PreviewGridSource = new PreviewGridSource(3);
      source.reset(7);
      expect(source.totalCount()).assertEqual(3);
      expect(source.getData(0).cells.length).assertEqual(3);
      expect(source.getData(2).cells.length).assertEqual(1);
      expect(source.getData(2).cells[0].page).assertEqual(6);
      // 未取到：url 全空 → 渲染端显示页码占位。
      expect(source.getData(0).cells[0].url).assertEqual('');
    });

    it('reset_without_pages_is_empty', 0, () => {
      const source: PreviewGridSource = new PreviewGridSource(3);
      source.reset(5);
      source.reset(0);
      expect(source.totalCount()).assertEqual(0);
    });

    it('reset_notifies_reload', 0, () => {
      const source: PreviewGridSource = new PreviewGridSource(3);
      const listener: RecordingListener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.reset(20);
      expect(listener.reloads).assertEqual(1);
      expect(source.generation).assertEqual(1);
      source.reset(20);
      expect(source.generation).assertEqual(2);
    });

    it('reset_drops_previous_cells', 0, () => {
      const source: PreviewGridSource = new PreviewGridSource(3);
      source.reset(20);
      source.apply([cellOf(4, 'https://e/x.jpg')]);
      expect(source.getData(1).cells[1].url).assertEqual('https://e/x.jpg');
      // 换画廊 = 重建：上一本的图不能留在格子里。
      source.reset(20);
      expect(source.getData(1).cells[1].url).assertEqual('');
    });

    it('apply_writes_fields_and_keeps_page_identity', 0, () => {
      const source: PreviewGridSource = new PreviewGridSource(3);
      source.reset(20);
      source.apply([cellOf(4, 'https://e/x.jpg')]);
      const cell: PreviewCell = source.getData(1).cells[1];
      expect(cell.page).assertEqual(4);
      expect(cell.url).assertEqual('https://e/x.jpg');
      expect(cell.w).assertEqual(200);
      expect(cell.h).assertEqual(137);
    });

    it('apply_ignores_out_of_range_page', 0, () => {
      const source: PreviewGridSource = new PreviewGridSource(3);
      source.reset(20);
      source.apply([cellOf(99, 'https://e/x.jpg')]);
      const rows: number = source.totalCount();
      let filled: number = 0;
      for (let r = 0; r < rows; r++) {
        const row: PreviewRow = source.getData(r);
        for (let c = 0; c < row.cells.length; c++) {
          if (row.cells[c].url.length > 0) {
            filled += 1;
          }
        }
      }
      expect(filled).assertEqual(0);
    });

    it('apply_ignores_missing_slot_in_short_row', 0, () => {
      // pages=4 → 第 2 行只有 page 3 一格；page 4 落在同一行的空位上，必须丢弃。
      const source: PreviewGridSource = new PreviewGridSource(3);
      source.reset(4);
      expect(source.getData(1).cells.length).assertEqual(1);
      source.apply([cellOf(4, 'https://e/x.jpg')]);
      expect(source.getData(1).cells.length).assertEqual(1);
      expect(source.getData(1).cells[0].url).assertEqual('');
    });

    it('unregister_stops_reload_notifications', 0, () => {
      const source: PreviewGridSource = new PreviewGridSource(3);
      const listener: RecordingListener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.unregisterDataChangeListener(listener);
      source.reset(20);
      expect(listener.reloads).assertEqual(0);
    });
  });
}
