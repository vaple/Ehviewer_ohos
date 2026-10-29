import { AppShell } from '../ui/AppShell';

/** 页面根：铺满窗口；安全区由 HDS 标题栏与各页内容自行避让（运行时读，不写死）。 */
@Entry
@ComponentV2
struct Index {
  build() {
    Column() {
      AppShell()
    }
    .width('100%')
    .height('100%')
  }
}
