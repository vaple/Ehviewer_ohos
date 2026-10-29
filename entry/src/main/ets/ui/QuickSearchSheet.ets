import { common } from '@kit.AbilityKit';
import { HdsListItem } from '@kit.UIDesignKit';
import { QuickSearch } from '../model/QuickSearch';
import { QuickSearchDao } from '../db/dao/QuickSearchDao';
import { DbHelper } from '../db/DbHelper';
import { Logger } from '../common/Logger';
import { SearchParam } from '../model/SearchParam';
import { quickSearchToParam, quickSearchSummary } from '../search/QuickSearchQuery';

/**
 * 快搜 sheet（半模态）：存过的快搜点行运行，左滑 `trash` 删除。
 * 无“存当前”入口——保存走搜索页书签（`SearchPage.saveQuick`）。
 */
@ComponentV2
export struct QuickSearchSheet {
  @Event onRun: (param: SearchParam) => void = (_p: SearchParam) => {};
  @Local items: QuickSearch[] = [];
  @Local message: string = '加载中…';

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async reload(): Promise<void> {
    try {
      await DbHelper.init(this.context());
      this.items = await QuickSearchDao.queryAll();
      this.message = this.items.length === 0 ? '还没有快速搜索' : '';
    } catch (e) {
      Logger.error('QSearch', `sheet load failed: ${e}`);
      this.message = '加载失败';
    }
  }

  private async deleteOne(item: QuickSearch): Promise<void> {
    try {
      await DbHelper.init(this.context());
      await QuickSearchDao.delete(item.id);
      await this.reload();
    } catch (e) {
      Logger.error('QSearch', `sheet delete failed id=${item.id}: ${e}`);
      this.message = '删除失败，请重试';
    }
  }

  build() {
    Column() {
      if (this.items.length > 0) {
        // 行间距：HdsListItemCard 自带左右 16vp 缩进，行间不叠（叠起来会互相压字）。
        List({ space: 8 }) {
          Repeat(this.items)
            .virtualScroll({ reusable: false })
            .each((ri: RepeatItem<QuickSearch>) => {
              HdsListItem({
                hdsListItemCard: {
                  textItem: {
                    primaryText: { text: ri.item.name },
                    secondaryText: quickSearchSummary(ri.item).length > 0
                      ? { text: quickSearchSummary(ri.item) }
                      : undefined
                  },
                  onClick: () => {
                    this.onRun(quickSearchToParam(ri.item));
                  }
                },
                swipeActionOptions: {
                  deleteIconOptions: {
                    onAction: () => {
                      this.deleteOne(ri.item);
                    }
                  }
                }
              })
            })
            .key((item: QuickSearch) => `${item.id}`)
        }
        .width('100%')
        .layoutWeight(1)
      }
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .padding(12)
      }
    }
    .width('100%')
    // 不铺不透明底：sheet 的官方材质由 `SheetOptions.systemMaterial` 提供，铺底色会把材质整块盖死。
    .backgroundColor(Color.Transparent)
    .onAppear(() => {
      this.reload();
    })
  }
}
