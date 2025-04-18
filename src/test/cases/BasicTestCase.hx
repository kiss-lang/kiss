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

class BasicObject {
    var val:Int;

    public function new(val:Int) {
        this.val = val;
    }

    public function multiply(otherVal:Int) {
        return val * otherVal;
    }
}

@:build(kiss.Kiss.build())
class BasicTestCase extends Test {
    function testSplitByAll() {
        _testSplitByAll();
    }

    function testStaticVar() {
        Assert.equals("Howdy", BasicTestCase.message);
    }

    function testHaxeInsertion() {
        _testHaxeInsertion();
    }

    function testStaticFunction() {
        Assert.equals(6, BasicTestCase.myFloor(6.5));
    }

    function testFuncall() {
        Assert.equals(7, BasicTestCase.funResult);
    }

    function testField() {
        Assert.equals(5, new BasicTestCase().myField);
    }

    function testMethod() {
        Assert.equals(5, new BasicTestCase().myMethod());
    }

    function testArray() {
        var arr = BasicTestCase.myArray;
        Assert.equals(3, arr.length);
        Assert.equals(1, arr[0]);
        Assert.equals(2, arr[1]);
        Assert.equals(3, arr[2]);

        // Kiss arrays can be negatively indexed like Python
        Assert.equals(3, arr[-1]);
        Assert.equals(2, arr[-2]);
        Assert.equals(1, arr[-3]);
    }

    function testArrayAccess() {
        Assert.equals(3, BasicTestCase.myArrayLast);
    }

    function testCollect() {
        _testCollect();
    }

    function testConcat() {
        _testConcat();
    }

    function testVariadicAdd() {
        Assert.equals(6, BasicTestCase.mySum);
    }

    function testSubtraction() {
        _testSubtraction();
    }

    function testMultiplication() {
        _testMultiplication();
    }

    function testVariadicDivide() {
        Assert.equals(0.5, BasicTestCase.myQuotient);
    }

    function testMod() {
        Assert.equals(4, BasicTestCase.myRemainder);
    }

    function testPow() {
        Assert.equals(256, BasicTestCase.myPower);
    }

    function testUnop() {
        Assert.equals(7, BasicTestCase.myInc);
        Assert.equals(7, BasicTestCase.myNum);
    }

    function testMin() {
        Assert.equals(1, BasicTestCase.myMin);
    }

    function testMax() {
        Assert.equals(9, BasicTestCase.myMax);
    }

    function testLessThan() {
        _testLessThan();
    }

    function testLesserEqual() {
        _testLesserEqual();
    }

    function testGreaterThan() {
        _testGreaterThan();
    }

    function testGreaterEqual() {
        _testGreaterEqual();
    }

    function testEqual() {
        _testEqual();
    }

    function testIf() {
        _testIf();
    }

    // TODO to really test typed variable definitions, check for compilation failure on a bad example
    function testTypedDefvar() {
        Assert.equals(8, BasicTestCase.myInt);
    }

    function testTryCatch() {
        Assert.equals(5, BasicTestCase.myTryCatch("string error"));
        Assert.equals(6, BasicTestCase.myTryCatch(404));
        Assert.equals(7, BasicTestCase.myTryCatch(["list error"]));
    }

    function testTypeCheck() {
        Assert.equals(5, BasicTestCase.myTypeCheck());
    }

    function testEnumerate() {
        _testEnumerate();
    }

    function testGroups() {
        _testGroups();
    }

    function testZip() {
        _testZip();
    }

    function testLet() {
        _testLet();
    }

    function testConstructors() {
        Assert.equals("sup", BasicTestCase.myConstructedString);
    }

    function testCond() {
        _testCond();
    }

    function testSetAndDeflocal() {
        Assert.equals("another thing", BasicTestCase.mySetLocal());
    }

    function testOr() {
        _testOr();
    }

    function testAnd() {
        _testAnd();
    }

    function testNot() {
        Assert.equals(false, BasicTestCase.myNot1);
        Assert.equals(false, BasicTestCase.myNot2);
    }

    function testLambda() {
        Assert.equals([5, 6].toString(), BasicTestCase.myFilteredList.toString());
    }

    function testWhen() {
        Assert.equals(6, BasicTestCase.myWhen1);
    }

    function testQuickNths() {
        _testQuickNths();
    }

    function testListDestructuring() {
        _testListDestructuring();
    }

    function testDoFor() {
        _testDoFor();
    }

    function testOptionalArguments() {
        myOptionalFunc(5);
    }

    function testRestArguments() {
        Assert.equals(5, myRest1);
        Assert.equals(5, myRest2);
        Assert.equals(5, myRest3);
    }

    function testCombinedOptRest() {
        Assert.equals("abcd", myCombined1);
        Assert.equals("aboop", myCombined2);
        Assert.equals("ab", myCombined3);
    }

    function testFieldExps() {
        _testFieldExps();
    }

    function testBreakContinue() {
        _testBreakContinue();
    }

    function testAssert() {
        _testAssert();
    }

    function testApply() {
        _testApply();
    }

    function testApplyWithMethod() {
        Assert.equals(30, applyWithMethod(new BasicObject(5)));
        Assert.equals(18, applyWithMethod(new BasicObject(3)));
    }

    function testAnonymousObject() {
        _testAnonymousObject();
    }

    function testCase() {
        _testCase();
    }

    function testMaps() {
        _testMaps();
    }

    function testRange() {
        _testRange();
    }

    function testRest() {
        _testRest();
    }

    function testTypeParsing() {
        _testTypeParsing();
    }

    function testDefmacro() {
        _testDefmacro();
    }

    function testDefmacroWithLogic() {
        _testDefmacroWithLogic();
    }

    function testCallAlias() {
        _testCallAlias();
    }

    function testLoadedFunction() {
        Assert.equals("loaded", BasicTestCase.loadedFunction());
    }

    function testLoadInline() {
        _testLoadInline();
    }

    function testAssignArith() {
        _testAssignArith();
    }

    function testPatternLets() {
        _testPatternLets();
    }

    function testRawString() {
        _testRawString();
    }

    function testKissStrings() {
        _testKissStrings();
    }

    function testArrowLambdas() {
        _testArrowLambdas();
    }

    function testVoid() {
        _testVoid();
    }

    function testLetThrow() {
        _testLetThrow();
    }

    function testDotAccessOnAlias() {
        _testDotAccessOnAlias();
    }

    function testClamp() {
        _testClamp();
    }

    function testCountingLambda() {
        _testCountingLambda();
    }

    function testExpComment() {
        _testExpComment();
    }

    function testEval() {
        #if ((sys || hxnodejs) && !lua)
        _testEvalStatic();
        _testEval();
        #else
        Assert.pass();
        #end
    }

    function testCaseOnNull() {
        _testCaseOnNull();
    }

    function testContains() {
        _testContains();
    }

    function testIntersect() {
        _testIntersect();
    }

    function testWhile() {
        _testWhile();
    }

    function testWhileLet() {
        _testWhileLet();
    }

    function testTrace() {
        _testTrace();
    }

    function testInsertUTestCase() {
        _testInsertUTestCase();
    }

    function testQuickFractions() {
        _testQuickFractions();
    }

    function testWhenLetGuards() {
        _testWhenLetGuards();
    }

    function testImportAndUsingInBuildMacro() {
        _testImportAndUsingInBuildMacro();
    }

    function testPureKissClasses() {
        _testPureKissClasses();
    }

    function testArraysToVariadic() {
        _testArraysToVariadic();
    }

    function testThreadingSupportCheck() {
        #if target.threaded
        Assert.isTrue(_hasThreadSupport());
        #else
        Assert.isFalse(_hasThreadSupport());
        #end
    }

    function testHaxeProperties() {
        _testHaxeProperties();
    }

    function testWithFunctions() {
        _testWithFunctions();
    }

    function testWithTempSet() {
        _testWithTempSet();
    }

    var nullDefinedInHaxe = null;
    static var staticNullDefinedInHaxe = null;

    function testPrintMacros() {
        // TODO Test the warnings
        _testPrintMacrosInstance();
        _testPrintMacrosStatic();
    }

    function testTypeCase() {
        _testTypeCase();
    }

    #if ((sys || hxnodejs) && !lua)
    function testTryProcess() {
        // tryProcess returns null on failure:
        Assert.equals(null, Prelude.tryProcess("_ThisCoMMaNDWillSURElYFaiLLLLLL", [], error->{return;}));
        // tryProcess returns output on success:
        Assert.equals("4.3.1", Prelude.tryProcess("haxe", ["--version"], error->{throw error;}));
    }
    #end

    function testLambdaTypeAnnotations() {
        _testLambdaTypeAnnotations();
    }

    function testCaseMacroError() {
        _testCaseMacroError();
    }

    function testQuickPrintOnSetVar() {
        _testQuickPrintOnSetVar();
    }

    function testSafeAccess() {
        _testSafeAccess();
    }

    function testStreamRecording() {
        _testStreamRecording();
    }

    function testObjectWith() {
        _testObjectWith();
    }

    function testRedefineWithObjectArgs() {
        _testRedefineWithObjectArgs();
    }
    
    function testTypedArrayMacro() {
        _testTypedArrayMacro();
    }
    
    function testDefault() {
        _testDefault();
    }
    
    var aNullToPrint = null;
}