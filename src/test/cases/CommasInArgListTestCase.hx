package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;

@:build(kiss.Kiss.buildExpectingError(kiss.EType.EAny))
class CommasInArgListTestCase extends Test {
    function testExpectedError() {
        _testExpectedError();
    }
}