package test.cases;

import utest.Test;
import utest.Assert;
import kiss.EmbeddedScript;
import kiss.AsyncEmbeddedScript;
import kiss.Prelude;

class DSLTestCase extends Test {
    function testScript() {
        new DSLScript().run();
    }

    function testFork() {
        new DSLScript().fork([(self) -> Assert.equals(5, 5), (self) -> Assert.equals(7, 7)]);
    }

    function testAsync() {
        var script = new AsyncDSLScript();
        script.run();
        Assert.isFalse(script.ranHscriptInstruction);
    }
    
    function testAsyncFromCache() {
        var script = new AsyncDSLScriptThatWillCache();
        script.run();
        var script2 = new AsyncDSLScriptThatWillCache2();
        Assert.isTrue(script.ranHscriptInstruction || script2.ranHscriptInstruction);
    }
}

@:build(kiss.EmbeddedScript.build("DSL.kiss", "DSLScript.dsl"))
class DSLScript extends EmbeddedScript {}

@:build(kiss.AsyncEmbeddedScript.build("", "DSL.kiss", "DSLScript.dsl"))
class AsyncDSLScript extends AsyncEmbeddedScript {}

@:build(kiss.AsyncEmbeddedScript.build("", "DSL.kiss", "DSLScriptThatWillCache.dsl"))
class AsyncDSLScriptThatWillCache extends AsyncEmbeddedScript {}

@:build(kiss.AsyncEmbeddedScript.build("", "DSL.kiss", "DSLScriptThatWillCache.dsl"))
class AsyncDSLScriptThatWillCache2 extends AsyncEmbeddedScript {}