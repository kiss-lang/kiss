package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;
import kiss.List;
import haxe.ds.Option;
import kiss.Kiss;
#if js
import js.lib.Promise;
#end

using StringTools;

@:build(kiss.Kiss.build())
class MacroExpandTestCase extends Test {
    function testObjectFormWithAlias() {
        _testObjectFormWithAlias();
    }

    function testLambdaFormWithAlias() {
        _testLambdaFormWithAlias();
    }
}
 