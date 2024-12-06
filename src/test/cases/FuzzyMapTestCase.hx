package test.cases;

import utest.Test;
import utest.Assert;
import kiss.Prelude;
import kiss.List;
import kiss.Stream;
import haxe.ds.Option;
import kiss.Kiss;
import kiss.FuzzyMapTools;

using StringTools;

@:build(kiss.Kiss.build())
class FuzzyMapTestCase extends Test {
    function testFuzzyGet() {
        _testFuzzyGet();
    }
}