package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;
import kiss.List;
import haxe.ds.Option;

using StringTools;

@:build(kiss.Kiss.build("kiss/src/test/cases/MacroTestCase.kiss"))
class MacroTestCase extends Test {
    function testMultipleFieldForms() {
        Assert.equals(5, myVar);
        Assert.equals(6, myFunc());
    }
}
