package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;

@:build(kiss.Kiss.buildExpectingError(kiss.EType.EUnmatchedBracket("}")))
class UnmatchedBracketTestCase extends Test {
    function testExpectedError() {
        _testExpectedError();
    }
}