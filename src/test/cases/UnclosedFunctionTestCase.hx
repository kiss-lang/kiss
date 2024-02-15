package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;
import kiss.List;
import kiss.Stream;
import haxe.ds.Option;
import kiss.Kiss;
#if js
import js.lib.Promise;
#end

using StringTools;

@:build(kiss.Kiss.buildExpectingError(kiss.EType.EStream('Ran out of expressions before ) was found.')))
class UnclosedFunctionTestCase extends Test {
    function testSplitByAll() {
        Assert.pass();
    }

    function testExpectedError() {
        _testExpectedError();
    }
}