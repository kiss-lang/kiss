package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;

@:build(kiss.Kiss.build())
class KissCacheTestCase extends Test {
    public function testFirstCompile() {
        _testFirstCompile();
    }
}