import abilityTest from './Ability.test';
import napiIntegrationTest from './NapiIntegration.test';

export default function testsuite() {
  abilityTest();
  napiIntegrationTest();
}
