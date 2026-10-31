import { describe, it, expect } from '@ohos/hypium';
import { PreviewStripSource } from '../../main/ets/ui/PreviewStripSource';
import { PreviewCell } from '../../main/ets/model/PreviewCell';

class RecordingListener implements DataChangeListener {
  changes: number[] = [];

  onDataReloaded(): void {}
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(index: number): void {
    this.changes.push(index);
  }
  onDatasetChange(_operations: DataOperation[]): void {}
}

function cellOf(page: number, url: string): PreviewCell {
  const cell: PreviewCell = new PreviewCell();
  cell.page = page;
  cell.url = url;
  cell.x = 1;
  cell.y = 2;
  cell.w = 3;
  cell.h = 4;
  return cell;
}

export default function previewStripSourceTest() {
  describe('PreviewStripSource', () => {
    it('starts_with_empty_placeholders', 0, () => {
      const source: PreviewStripSource = new PreviewStripSource(5);
      expect(source.totalCount()).assertEqual(5);
      expect(source.getData(4).page).assertEqual(4);
      expect(source.getData(4).url).assertEqual('');
    });

    it('setCell_writes_and_notifies_only_that_row', 0, () => {
      const source: PreviewStripSource = new PreviewStripSource(5);
      const listener: RecordingListener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.setCell(cellOf(2, 'https://e/x.jpg'));
      expect(source.getData(2).url).assertEqual('https://e/x.jpg');
      expect(source.getData(2).w).assertEqual(3);
      // 写入只覆盖缩略图字段，页码是数据源的身份，不能被覆盖。
      expect(source.getData(2).page).assertEqual(2);
      expect(listener.changes.join(',')).assertEqual('2');
    });

    it('setCell_ignores_out_of_range_page', 0, () => {
      const source: PreviewStripSource = new PreviewStripSource(5);
      const listener: RecordingListener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.setCell(cellOf(9, 'https://e/x.jpg'));
      expect(listener.changes.length).assertEqual(0);
    });

    it('unregister_stops_notifications', 0, () => {
      const source: PreviewStripSource = new PreviewStripSource(5);
      const listener: RecordingListener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.unregisterDataChangeListener(listener);
      source.setCell(cellOf(1, 'https://e/y.jpg'));
      expect(listener.changes.length).assertEqual(0);
    });
  });
}
