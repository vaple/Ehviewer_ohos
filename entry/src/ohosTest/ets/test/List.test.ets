import httpClientTest from './HttpClient.test';
import dbTest from './Db.test';
import servicesTest from './Services.test';
import schemaTest from './Schema.test';
import galleryDaosTest from './GalleryDaos.test';
import otherDaosTest from './OtherDaos.test';
import ehClientTest from './EhClient.test';
import ehClientDetailTest from './EhClientDetail.test';
import readerPageTest from './ReaderPage.test';
import persistenceReadbackTest from './PersistenceReadback.test';

export default function testsuite() {
  httpClientTest();
  dbTest();
  servicesTest();
  schemaTest();
  galleryDaosTest();
  otherDaosTest();
  ehClientTest();
  ehClientDetailTest();
  readerPageTest();
  persistenceReadbackTest();
}
