package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;

@:build(kiss.Kiss.buildExpectingError(kiss.EType.EKiss('trailing comma on function argument')))
class CommasInArgListTestCase extends Test {
    function testExpectedError() {
        _testExpectedError();
    }
}