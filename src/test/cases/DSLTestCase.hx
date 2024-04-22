package test.cases;

import utest.Test;
import utest.Assert;
import kiss.AsyncEmbeddedScript2;
import kiss.Prelude;
import kiss.FuzzyMap;
import kiss.FuzzyMapTools;

class DSLTestCase extends Test {
    function testAsync() {
        var script = new AsyncDSLScript();
        script.run();
        #if !lua
        Assert.isFalse(script.ranHscriptInstruction);
        #end
        Assert.isTrue(script.wholeScriptDone);
    }

    #if (sys || hxnodejs)
    function testAsyncFromCache() {
        var script = new AsyncDSLScriptThatWillCache();
        script.run();
        var script2 = new AsyncDSLScriptThatWillCache2();
        script2.run();
        #if !lua
        Assert.isTrue(script.ranHscriptInstruction || script2.ranHscriptInstruction);
        Assert.isFalse(script.ranHscriptInstruction && script2.ranHscriptInstruction);
        #end
        Assert.isTrue(script.wholeScriptDone);
        Assert.isTrue(script2.wholeScriptDone);
    }
    #end

    function testAsyncAutoCC() {
        var scriptWithAutoCC = new AsyncDSLScriptWithAutoCC();
        var scriptWithoutAutoCC = new AsyncDSLScriptWithAutoCC();
        scriptWithoutAutoCC.autoCC = false;

        scriptWithAutoCC.run();
        scriptWithoutAutoCC.run();

        Assert.isTrue(scriptWithAutoCC.finished);
        Assert.isFalse(scriptWithoutAutoCC.finished);
    }
}

@:build(kiss.AsyncEmbeddedScript2.build("", "DSL.kiss", "AsyncDSLScript.dsl"))
class AsyncDSLScript extends AsyncEmbeddedScript2 {}

// One of these two classes will reuse instructions from the cache, but
// I can't guarantee which one compiles first:

@:build(kiss.AsyncEmbeddedScript2.build("", "DSL.kiss", "AsyncDSLScriptThatWillCache.dsl"))
class AsyncDSLScriptThatWillCache extends AsyncEmbeddedScript2 {}

@:build(kiss.AsyncEmbeddedScript2.build("", "DSL.kiss", "AsyncDSLScriptThatWillCache.dsl"))
class AsyncDSLScriptThatWillCache2 extends AsyncEmbeddedScript2 {}

// Auto-call cc when the scripter forgets to:

@:build(kiss.AsyncEmbeddedScript2.build("", "DSL.kiss", "AsyncDSLScriptWithAutoCC.dsl"))
class AsyncDSLScriptWithAutoCC extends AsyncEmbeddedScript2 {}