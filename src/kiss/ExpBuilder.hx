package kiss;

import kiss.ReaderExp;
using kiss.Helpers;
using kiss.Reader;
using kiss.ExpBuilder;

class ExpBuilder {
    // Return convenient functions for succinctly making new ReaderExps that link back to an original exp's
    // position in source code
    public static function expBuilder(posRef:ReaderExp) {
        function _symbol(?name:String) {
            return Prelude.symbol(name).withPosOf(posRef);
        }
        function call(func:ReaderExp, args:Array<ReaderExp>) {
            return CallExp(func, args).withPosOf(posRef);
        }
        function callSymbol(symbol:String, args:Array<ReaderExp>) {
            return call(_symbol(symbol), args);
        }
        function field(f:String, exp:ReaderExp, ?safe:Bool) {
            return FieldExp(f, exp, safe != null && safe).withPosOf(posRef);
        }
        function list(exps:Array<ReaderExp>) {
            return ListExp(exps).withPosOf(posRef);
        }
        function objectWith (bindings:Array<ReaderExp>, captures:Array<ReaderExp>) {
            return callSymbol("objectWith", [list(bindings)].concat(captures));
        }
        function str(s:String) {
            return StrExp(s).withPosOf(posRef);
        }
        function raw(code:String) {
            return RawHaxe(code).withPosOf(posRef);
        }
        function int(v:Int) {
            return _symbol(Std.string(v));
        }
        function float(v:Float) {
            return _symbol(Std.string(v));
        }
        function let(bindings:Array<ReaderExp>, body:Array<ReaderExp>) {
            return callSymbol("let", [list(bindings)].concat(body));
        }
        function _if(condition:ReaderExp, then:ReaderExp, ?_else:ReaderExp) {
            var args = [condition, then];
            if (_else != null)
                args.push(_else);
            return callSymbol("if", args);
        }
        function throwAssertOrNeverError(messageExp:ReaderExp) {
            var failureError = KissError.fromExp(posRef, "").toString(AssertionFail);
            var colonsInPrefix = if (Sys.systemName() == "Windows") 5 else 4;
            return callSymbol("throw", [
                callSymbol("kiss.Prelude.runtimeInsertAssertionMessage", [messageExp, str(failureError), int(colonsInPrefix)])
            ]);
        }
        function whenUnless(which:String, condition:ReaderExp, body:Array<ReaderExp>) {
            return callSymbol(which, [condition].concat(body));
        }
        return {
            call: call,
            callSymbol: callSymbol,
            callField: (fieldName:String, callOn:ReaderExp, args:Array<ReaderExp>) -> call(field(fieldName, callOn), args),
            print: (arg:ReaderExp) -> CallExp(Symbol("print").withPosOf(posRef), [arg]).withPosOf(posRef),
            the: (type:ReaderExp, value:ReaderExp) -> callSymbol("the", [type, value]),
            not: (exp:ReaderExp) -> callSymbol("not", [exp]),
            list: list,
            str: str,
            symbol: _symbol,
            _if: _if,
            int: int,
            float: float,
            raw: raw,
            typed: (path:String, exp:ReaderExp) -> TypedExp(path, exp).withPosOf(posRef),
            meta: (m:String, exp:ReaderExp) -> MetaExp(m, exp).withPosOf(posRef),
            field: field,
            keyValue: (key:ReaderExp, value:ReaderExp) -> KeyValueExp(key, value).withPosOf(posRef),
            begin: (exps:Array<ReaderExp>) -> callSymbol("begin", exps),
            set: (v:ReaderExp, value:ReaderExp) -> callSymbol("set", [v, value]),
            when: whenUnless.bind("when"),
            unless: whenUnless.bind("unless"),
            let: let,
            objectWith: objectWith,
            expFromDef: (def:ReaderExpDef) -> def.withPosOf(posRef),
            // Only use within assertion macros
            throwAssertionError: () -> {
                var usage = "throwAssertionError can only be used in a builder of an assertion macro";
                var exps = switch (posRef.def) {
                    case CallExp(_, exps):
                        exps;
                    default:
                        throw KissError.fromExp(_symbol("throwAssertionError"), usage);
                }
                var messageExp = if (exps.length > 1) {
                    exps[1];
                } else {
                    str("");
                };
                throwAssertOrNeverError(messageExp);
            },
            neverCase: () -> {
                switch (posRef.def) {
                    case CallExp({pos: _, def: Symbol("never")}, neverExps):
                        posRef.checkNumArgs(1, 1, '(never <pattern>)');
                        call(neverExps[0], [
                            throwAssertOrNeverError(str('case should never match pattern ${Reader.toString(neverExps[0].def)}'))
                        ]);
                    default:
                        posRef;
                }
            },
            // Compile-time only!
            throwKissError: (reason:String) -> {
                callSymbol("throw", [
                    callSymbol("KissError.fromExpStr", [
                        // pos
                        objectWith([
                            _symbol("file"), str(posRef.pos.file),
                            _symbol("line"), int(posRef.pos.line),
                            _symbol("column"), int(posRef.pos.column),
                            _symbol("absoluteChar"), int(posRef.pos.absoluteChar),
                        ], []),
                        // expStr
                        str(Reader.toString(posRef.def)),
                        str(reason)
                    ])
                ]);
            },
            #if macro
            haxeExpr: (e:haxe.macro.Expr) -> Helpers.withMacroPosOf(e.expr, posRef),
            #end
            none: () -> None.withPosOf(posRef)
        };
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
