package kiss;

import kiss.ReaderExp;
using kiss.Helpers;
using kiss.Reader;
using kiss.ExpBuilder;

// Has convenient functions for succinctly making new ReaderExps that link back to an original exp's
// position in source code
class ExpBuilder {
    var posRef:ReaderExp;

    function new(posRef:ReaderExp) {
        this.posRef = posRef;
    }

    public static function expBuilder(posRef:ReaderExp) {
        return new ExpBuilder(posRef);
    }

    public function symbol(?name:String) {
        return Prelude.symbol(name).withPosOf(posRef);
    }

    public function call(func:ReaderExp, args:Array<ReaderExp>) {
        return CallExp(func, args).withPosOf(posRef);
    }

    public function callSymbol(_symbol:String, args:Array<ReaderExp>) {
        return call(symbol(_symbol), args);
    }

    public function field(f:String, exp:ReaderExp, ?safe:Bool) {
        return FieldExp(f, exp, safe != null && safe).withPosOf(posRef);
    }

    public function list(exps:Array<ReaderExp>) {
        return ListExp(exps).withPosOf(posRef);
    }
    public function objectWith (bindings:Array<ReaderExp>, captures:Array<ReaderExp>) {
        return callSymbol("objectWith", [list(bindings)].concat(captures));
    }
    public function str(s:String) {
        return StrExp(s).withPosOf(posRef);
    }
    public function raw(code:String) {
        return RawHaxe(code).withPosOf(posRef);
    }
    public function int(v:Int) {
        return symbol(Std.string(v));
    }
    public function float(v:Float) {
        return symbol(Std.string(v));
    }
    public function let(bindings:Array<ReaderExp>, body:Array<ReaderExp>) {
        return callSymbol("let", [list(bindings)].concat(body));
    }
    public function _if(condition:ReaderExp, then:ReaderExp, ?_else:ReaderExp) {
        var args = [condition, then];
        if (_else != null)
            args.push(_else);
        return callSymbol("if", args);
    }
#if (sys || hxnodejs)
    public function throwAssertOrNeverError(messageExp:ReaderExp) {
        var failureError = KissError.fromExp(posRef, "").toString(AssertionFail);
        var colonsInPrefix = if (Sys.systemName() == "Windows") 5 else 4;
        return callSymbol("throw", [
            callSymbol("kiss.Prelude.runtimeInsertAssertionMessage", [messageExp, str(failureError), int(colonsInPrefix)])
        ]);
    }
#end
    function _whenUnless(which:String, condition:ReaderExp, body:Array<ReaderExp>) {
        return callSymbol(which, [condition].concat(body));
    }
    public function when(condition:ReaderExp, body:Array<ReaderExp>) {
        return _whenUnless("when", condition, body);
    }
    public function unless(condition:ReaderExp, body:Array<ReaderExp>) {
        return _whenUnless("unless", condition, body);
    }

    public function callField(fieldName:String, callOn:ReaderExp, args:Array<ReaderExp>) {
        return call(field(fieldName, callOn), args);
    }
    public function print(arg:ReaderExp) {
        return CallExp(Symbol("print").withPosOf(posRef), [arg]).withPosOf(posRef);
    }
    public function the(type:ReaderExp, value:ReaderExp) {
        return callSymbol("the", [type, value]);
    }
    public function not(exp:ReaderExp) {
        return callSymbol("not", [exp]);
    }
    public function typed(path:String, exp:ReaderExp) {
        return TypedExp(path, exp).withPosOf(posRef);
    }
    public function meta(m:String, exp:ReaderExp) {
        return MetaExp(m, exp).withPosOf(posRef);
    }
    public function keyValue(key:ReaderExp, value:ReaderExp) {
        return KeyValueExp(key, value).withPosOf(posRef);
    }
    public function begin(exps:Array<ReaderExp>) {
        return callSymbol("begin", exps);
    }
    public function set(v:ReaderExp, value:ReaderExp) {
        return callSymbol("set", [v, value]);
    }
    public function expFromDef(def:ReaderExpDef) {
        return def.withPosOf(posRef);
    }
#if (sys || hxnodejs)
    // Only use within assertion macros
    public function throwAssertionError() {
        var usage = "throwAssertionError can only be used in a builder of an assertion macro";
        var exps = switch (posRef.def) {
            case CallExp(_, exps):
                exps;
            default:
                throw KissError.fromExp(symbol("throwAssertionError"), usage);
        }
        var messageExp = if (exps.length > 1) {
            exps[1];
        } else {
            str("");
        };
        return throwAssertOrNeverError(messageExp);
    }
    public function neverCase() {
        return switch (posRef.def) {
            case CallExp({pos: _, def: Symbol("never")}, neverExps):
                posRef.checkNumArgs(1, 1, '(never <pattern>)');
                call(neverExps[0], [
                    throwAssertOrNeverError(str('case should never match pattern ${Reader.toString(neverExps[0].def)}'))
                ]);
            default:
                posRef;
        }
    }
#end
    // Compile-time only!
    public function throwKissError(reason:String) {
        return callSymbol("throw", [
            callSymbol("KissError.fromExpStr", [
                // pos
                objectWith([
                    symbol("file"), str(posRef.pos.file),
                    symbol("line"), int(posRef.pos.line),
                    symbol("column"), int(posRef.pos.column),
                    symbol("absoluteChar"), int(posRef.pos.absoluteChar),
                ], []),
                // expStr
                str(Reader.toString(posRef.def)),
                str(reason)
            ])
        ]);
    }
#if macro
    public function haxeExpr(e:haxe.macro.Expr) {
        return Helpers.withMacroPosOf(e.expr, posRef);
    }
#end
    public function none() {
        return None.withPosOf(posRef);
    }

    public static function checkNumArgs(wholeExp:ReaderExp, min:Null<Int>, max:Null<Int>, ?expectedForm:String) {
        if (expectedForm == null) {
            expectedForm = if (max == min) {
                '$min arguments';
            } else if (max == null) {
                'at least $min arguments';
            } else if (min == null) {
                'no more than $max arguments';
            } else if (min == null && max == null) {
                throw 'checkNumArgs() needs a min or a max';
            } else {
                'between $min and $max arguments';
            };
        }

        var args = switch (wholeExp.def) {
            case CallExp(_, args): args;
            default: throw KissError.fromExp(wholeExp, "Can only check number of args in a CallExp");
        };

        if (min != null && args.length < min) {
            throw KissError.fromExp(wholeExp, 'Not enough arguments. Expected $expectedForm');
        } else if (max != null && args.length > max) {
            throw KissError.fromExp(wholeExp, 'Too many arguments. Expected $expectedForm');
        }
    }
}
