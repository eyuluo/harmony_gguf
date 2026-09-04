import localUnitTest from './LocalUnit.test';
import napiIntegrationTest from './NapiIntegration.test';

export default function testsuite() {
  localUnitTest();
  napiIntegrationTest();
}
