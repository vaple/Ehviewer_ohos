import { describe, it, expect } from '@ohos/hypium';
import { languageOf } from '../../main/ets/parser/ParserUtils';

export default function parserUtilsTest() {
  describe('ParserUtils', () => {
    it('languageOf_maps_site_tag', 0, () => {
      expect(languageOf(['language:chinese'])).assertEqual('ZH');
      expect(languageOf(['other:ai generated', 'language:korean'])).assertEqual('KO');
      expect(languageOf(['language:japanese'])).assertEqual('JA');
      expect(languageOf(['language:english'])).assertEqual('EN');
    });

    it('languageOf_unknown_or_missing_returns_empty', 0, () => {
      expect(languageOf(['language:unknown'])).assertEqual('');
      expect(languageOf(['other:ai generated'])).assertEqual('');
      expect(languageOf([])).assertEqual('');
    });
  });
}
