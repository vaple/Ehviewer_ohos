import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { DbHelper } from '../../../main/ets/db/DbHelper';
import { HistoryDao } from '../../../main/ets/db/dao/HistoryDao';
import { HistoryInfo } from '../../../main/ets/model/HistoryInfo';

async function ctx(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function galleryDaosTest() {
  describe('GalleryDaos', () => {
    it('history_put_query_delete', 0, async () => {
      await DbHelper.init(await ctx());
      await HistoryDao.clear();
      const info: HistoryInfo = {
        gid: 101, token: 'tok', title: 'Title', titleJpn: '', thumb: 'th',
        category: 1, posted: '2024', uploader: 'up', rating: 4.5, simpleLanguage: 'EN',
        pages: 0, mode: 2, time: 111
      };
      await HistoryDao.put(info);
      const all: HistoryInfo[] = await HistoryDao.queryAll();
      expect(all.length).assertEqual(1);
      expect(all[0].gid).assertEqual(101);
      expect(all[0].title).assertEqual('Title');
      expect(all[0].mode).assertEqual(2);
      expect(all[0].time).assertEqual(111);
      await HistoryDao.delete(101);
      expect((await HistoryDao.queryAll()).length).assertEqual(0);
    });

    it('history_put_twice_keeps_single', 0, async () => {
      await DbHelper.init(await ctx());
      await HistoryDao.clear();
      const first: HistoryInfo = {
        gid: 404, token: 't1', title: 'First', titleJpn: '', thumb: '',
        category: 0, posted: '', uploader: '', rating: 0, simpleLanguage: '',
        pages: 0, mode: 0, time: 100
      };
      const second: HistoryInfo = {
        gid: 404, token: 't1', title: 'Second', titleJpn: '', thumb: '',
        category: 0, posted: '', uploader: '', rating: 0, simpleLanguage: '',
        pages: 0, mode: 0, time: 200
      };
      await HistoryDao.put(first);
      await HistoryDao.put(second);
      const all: HistoryInfo[] = await HistoryDao.queryAll();
      expect(all.length).assertEqual(1);
      expect(all[0].title).assertEqual('Second');
      expect(all[0].time).assertEqual(200);
    });

    it('history_trimTo_keeps_latest_max', 0, async () => {
      await DbHelper.init(await ctx());
      await HistoryDao.clear();
      for (let i = 0; i < 5; i++) {
        const info: HistoryInfo = {
          gid: 900 + i, token: 't', title: `T${i}`, titleJpn: '', thumb: '',
          category: 0, posted: '', uploader: '', rating: 0, simpleLanguage: '',
          pages: 0, mode: 0, time: 1000 + i
        };
        await HistoryDao.put(info);
      }
      await HistoryDao.trimTo(3);
      const all: HistoryInfo[] = await HistoryDao.queryAll();
      expect(all.length).assertEqual(3);
      expect(all[0].gid).assertEqual(904);
      expect(all[2].gid).assertEqual(902);
    });
  });
}
