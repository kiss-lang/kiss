package test.cases;

import utest.Test;
import utest.Assert;
import kiss.EmbeddedScript;
import kiss.AsyncEmbeddedScript;
import kiss.Prelude;
import kiss.FuzzyMap;
import kiss.FuzzyMapTools;

class DSLTestCase extends Test {
    function testScript() {
        var script = new DSLScript();
        script.run();
        Assert.isTrue(script.wholeScriptDone);
    }

    function testFork() {
        new DSLScript().fork([(self) -> Assert.equals(5, 5), (self) -> Assert.equals(7, 7)]);
    }

    function testAsync() {
        var script = new AsyncDSLScript();
        script.run();
        Assert.isFalse(script.ranHscriptInstruction);
        Assert.isTrue(script.wholeScriptDone);
    }
    
    #if (sys || hxnodejs)
    function testAsyncFromCache() {
        var script = new AsyncDSLScriptThatWillCache();
        script.run();
        var script2 = new AsyncDSLScriptThatWillCache2();
        script2.run();
        Assert.isTrue(script.ranHscriptInstruction || script2.ranHscriptInstruction);
        Assert.isFalse(script.ranHscriptInstruction && script2.ranHscriptInstruction);
        Assert.isTrue(script.wholeScriptDone);
        Assert.isTrue(script2.wholeScriptDone);
    }
    #end
}

@:build(kiss.EmbeddedScript.build("DSL.kiss", "DSLScript.dsl"))
class DSLScript extends EmbeddedScript {}

@:build(kiss.AsyncEmbeddedScript.build("", "DSL.kiss", "AsyncDSLScript.dsl"))
class AsyncDSLScript extends AsyncEmbeddedScript {}

// One of these two classes will reuse instructions from the cache, but
// I can't guarantee which one compiles first:

@:build(kiss.AsyncEmbeddedScript.build("", "DSL.kiss", "AsyncDSLScriptThatWillCache.dsl"))
class AsyncDSLScriptThatWillCache extends AsyncEmbeddedScript {}

@:build(kiss.AsyncEmbeddedScript.build("", "DSL.kiss", "AsyncDSLScriptThatWillCache.dsl"))
class AsyncDSLScriptThatWillCache2 extends AsyncEmbeddedScript {}