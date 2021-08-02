package kiss;

import haxe.macro.Expr;
import haxe.macro.Context;
import kiss.Reader;
import kiss.ReaderExp;
import kiss.Kiss;
import kiss.CompileError;
import kiss.CompilerTools;
import uuid.Uuid;
import hscript.Parser;
import haxe.EnumTools;

using kiss.Kiss;
using kiss.Prelude;
using kiss.Reader;
using kiss.Helpers;
using StringTools;
using tink.MacroApi;

// Macros generate new Kiss reader expressions from the arguments of their call expression.
typedef MacroFunction = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> Null<ReaderExp>;

class Macros {
    public static function builtins() {
        var macros:Map<String, MacroFunction> = [];

        function renameAndDeprecate(oldName:String, newName:String) {
            var form = macros[oldName];
            macros[oldName] = (wholeExp, args, k) -> {
                CompileError.warnFromExp(wholeExp, '$oldName has been renamed to $newName and deprecated');
                form(wholeExp, args, k);
            }
            macros[newName] = form;
        }

        macros["load"] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, 1, '(load "[file]")');
            switch (args[0].def) {
                case StrExp(otherKissFile):
                    return Kiss.load(otherKissFile, k);
                default:
                    throw CompileError.fromExp(args[0], "only argument to load should be a string literal of a .kiss file path");
            }
        };

        macros["loadFrom"] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(2, 2, '(loadFrom "[haxelib name]" "[file]")');

            var libPath = switch (args[0].def) {
                case StrExp(libName):
                    Helpers.libPath(libName);
                default:
                    throw CompileError.fromExp(args[0], "first argument to loadFrom should be a string literal of a haxe library's name");
            };
            switch (args[1].def) {
                case StrExp(otherKissFile):
                    Kiss.load(otherKissFile, k, libPath);
                default:
                    throw CompileError.fromExp(args[1], "second argument to loadFrom should be a string literal of a .kiss file path");
            }
            null;
        };

        function destructiveVersion(op:String, assignOp:String) {
            macros[assignOp] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k) -> {
                wholeExp.checkNumArgs(2, null, '($assignOp [var] [v1] [values...])');
                var b = wholeExp.expBuilder();
                b.call(
                    b.symbol("set"), [
                        exps[0],
                        b.call(
                            b.symbol(op),
                            exps)
                    ]);
            };
        }

        destructiveVersion("%", "%=");
        destructiveVersion("^", "^=");
        destructiveVersion("+", "+=");
        destructiveVersion("-", "-=");
        destructiveVersion("*", "*=");
        destructiveVersion("/", "/=");

        // These shouldn't be ident aliases because they are common variable names
        var opAliases = [
            "min" => "Prelude.min",
            "max" => "Prelude.max"
        ];

        macros["apply"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k) -> {
            wholeExp.checkNumArgs(2, 2, '(apply [func] [argList])');
            var b = wholeExp.expBuilder();

            var callOn = switch (exps[0].def) {
                case FieldExp(field, exp):
                    exp;
                default:
                    b.symbol("null");
            };
            var func = switch (exps[0].def) {
                case Symbol(func) if (opAliases.exists(func)):
                    b.symbol(opAliases[func]);
                default:
                    exps[0];
            };
            var args = exps[1];
            b.call(
                b.symbol("Reflect.callMethod"), [
                    callOn, func, args
                ]);
        };

        macros["range"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k) -> {
            wholeExp.checkNumArgs(1, 3, '(range [?min] [max] [?step])');
            var b = wholeExp.expBuilder();
            var min = if (exps.length > 1) exps[0] else b.symbol("0");
            var max = if (exps.length > 1) exps[1] else exps[0];
            var step = if (exps.length > 2) exps[2] else b.symbol("1");
            b.callSymbol("Prelude.range", [min, max, step]);
        };

        // Most conditional compilation macros are based on this macro:
        macros["#if"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k) -> {
            wholeExp.checkNumArgs(2, 3, '(#if [cond] [then] [?else])');

            var b = wholeExp.expBuilder();
            var conditionExp = exps.shift();
            var thenExp = exps.shift();
            var elseExp = if (exps.length > 0) exps.shift(); else b.none();

            var parser = new Parser();
            var conditionInterp = new KissInterp(true);
            var conditionStr = Reader.toString(conditionExp.def);
            for (flag => value in Context.getDefines()) {
                // Don't overwrite types that are put in all KissInterps, i.e. the kiss namespace
                if (!conditionInterp.variables.exists(flag)) {
                    conditionInterp.variables.set(flag, value);
                }
            }
            try {
                var hscriptStr = Prelude.convertToHScript(conditionStr);
                #if test
                Prelude.print("#if condition hscript: " + hscriptStr);
                #end
                var conditionHScript = parser.parseString(hscriptStr);
                return if (Prelude.truthy(conditionInterp.execute(conditionHScript))) {
                    #if test
                    Prelude.print("using thenExp");
                    #end
                    thenExp;
                } else {
                    #if test
                    Prelude.print("using elseExp");
                    #end
                    elseExp;
                }
            } catch (e) {
                throw CompileError.fromExp(conditionExp, 'condition for #if threw error $e');
            }
        };

        // But not this one:
        macros["#case"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k) -> {
            wholeExp.checkNumArgs(2, null, '(#case [expression] [cases...] [optional: (otherwise [default])])');
            var b = wholeExp.expBuilder();

            var caseVar = exps.shift();
            var matchPatterns = [];
            var matchBodies = [];
            var matchBodySymbols = [];
            var caseArgs = [caseVar];
            for (exp in exps) {
                switch (exp.def) {
                    case CallExp(pattern, bodyExps):
                        matchPatterns.push(pattern);
                        matchBodies.push(b.begin(bodyExps));
                        var gensym = b.symbol();
                        matchBodySymbols.push(gensym);
                        caseArgs.push(b.call(pattern, [gensym]));
                    default:
                        throw CompileError.fromExp(exp, "invalid pattern expression for #case");
                }
            }

            var caseExp = b.callSymbol("case", caseArgs);

            var parser = new Parser();
            var caseInterp = new KissInterp();
            var caseStr = Reader.toString(caseExp.def);
            for (matchBodySymbol in matchBodySymbols) {
                caseInterp.variables.set(Prelude.symbolNameValue(matchBodySymbol), matchBodies.shift());
            }
            for (flag => value in Context.getDefines()) {
                if (flag != "kiss")
                    caseInterp.variables.set(flag, value);
            }
            try {
                var hscriptStr = Prelude.convertToHScript(caseStr);
                #if test
                Prelude.print("#case hscript: " + hscriptStr);
                #end
                var caseHScript = parser.parseString(hscriptStr);
                return caseInterp.execute(caseHScript);
            } catch (e) {
                throw CompileError.fromExp(caseExp, '#case evaluation threw error $e');
            }
        }

        function bodyIf(formName:String, underlyingIf:String, negated:Bool, wholeExp:ReaderExp, args:Array<ReaderExp>, k) {
            wholeExp.checkNumArgs(2, null, '($formName [condition] [body...])');
            var b = wholeExp.expBuilder();
            var condition = if (negated) {
                b.call(
                    b.symbol("not"), [
                        args[0]
                    ]);
            } else {
                args[0];
            }
            return b.call(b.symbol(underlyingIf), [
                condition,
                b.begin(args.slice(1))
            ]);
        }
        macros["when"] = bodyIf.bind("when", "if", false);
        macros["unless"] = bodyIf.bind("unless", "if", true);
        macros["#when"] = bodyIf.bind("#when", "#if", false);
        macros["#unless"] = bodyIf.bind("#unless", "#if", true);

        macros["cond"] = cond.bind("cond", "if");
        macros["#cond"] = cond.bind("#cond", "#if");

        // (or... ) uses (cond... ) under the hood
        macros["or"] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k) -> {
            wholeExp.checkNumArgs(2, null, "(or [v1] [v2] [values...])");
            var b = wholeExp.expBuilder();

            var uniqueVarSymbol = b.symbol();

            b.begin([
                b.call(b.symbol("localVar"), [
                    b.meta("mut", b.typed("Dynamic", uniqueVarSymbol)),
                    b.symbol("null")
                ]),
                b.call(b.symbol("cond"), [
                    for (arg in args) {
                        b.call(
                            b.call(b.symbol("set"), [
                                uniqueVarSymbol,
                                arg
                            ]), [
                                uniqueVarSymbol
                            ]);
                    }
                ])
            ]);
        };

        // (and... uses (cond... ) and (not ...) under the hood)
        macros["and"] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k) -> {
            wholeExp.checkNumArgs(2, null, "(and [v1] [v2] [values...])");
            var b = wholeExp.expBuilder();

            var uniqueVarSymbol = b.symbol();

            var condCases = [
                for (arg in args) {
                    b.call(
                        b.call(
                            b.symbol("not"), [
                                b.call(
                                    b.symbol("set"), [uniqueVarSymbol, arg])
                            ]), [
                                b.symbol("null")
                            ]);
                }
            ];
            condCases.push(b.call(b.symbol("true"), [uniqueVarSymbol]));

            b.begin([
                b.call(
                    b.symbol("localVar"), [
                        b.meta("mut", b.typed("Dynamic", uniqueVarSymbol)),
                        b.symbol("null")
                    ]),
                b.call(
                    b.symbol("cond"),
                    condCases)
            ]);
        };

        function arraySet(wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) {
            var b = wholeExp.expBuilder();
            return b.call(
                b.symbol("set"), [
                    b.call(b.symbol("nth"), [exps[0], exps[1]]),
                    exps[2]
                ]);
        }
        macros["setNth"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(3, 3, "(setNth [list] [index] [value])");
            arraySet(wholeExp, exps, k);
        };
        macros["dictSet"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(3, 3, "(dictSet [dict] [key] [value])");
            arraySet(wholeExp, exps, k);
        };

        macros["assert"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, 2, "(assert [expression] [message])");
            var b = wholeExp.expBuilder();
            var expression = exps[0];
            var basicMessage = 'Assertion ${expression.def.toString()} failed';
            var messageExp = if (exps.length > 1) {
                b.callSymbol("+", [b.str(basicMessage + ": "), exps[1]]);
            } else {
                b.str(basicMessage);
            };
            b.callSymbol("unless", [
                expression,
                b.callSymbol("throw", [messageExp])
            ]);
        };

        function stringsThatMatch(exp:ReaderExp, formName:String) {
            return switch (exp.def) {
                case StrExp(s):
                    [s];
                case ListExp(strings):
                    [
                        for (s in strings)
                            switch (s.def) {
                                case StrExp(s):
                                    s;
                                default:
                                    throw CompileError.fromExp(s, 'initiator list of $formName must only contain strings');
                            }
                    ];
                default:
                    throw CompileError.fromExp(exp, 'first argument to $formName should be a String or list of strings');
            };
        }

        macros["defmacro"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(3, null, '(defMacro [name] [[args...]] [body...])');

            var name = switch (exps[0].def) {
                case Symbol(name): name;
                default: throw CompileError.fromExp(exps[0], "macro name should be a symbol");
            };

            var argList = switch (exps[1].def) {
                case ListExp(macroArgs): macroArgs;
                case CallExp(_, _):
                    throw CompileError.fromExp(exps[1], 'expected a macro argument list. Change the parens () to brackets []');
                default:
                    throw CompileError.fromExp(exps[1], 'expected a macro argument list');
            };

            // This is similar to &opt and &rest processing done by Helpers.makeFunction()
            // but combining them would probably make things less readable and harder
            // to maintain, because defmacro makes an actual function, not a function definition
            var minArgs = 0;
            var maxArgs = 0;
            // Once the &opt meta appears, all following arguments are optional until &rest
            var optIndex = -1;
            // Once the &rest or &body meta appears, no other arguments can be declared
            var restIndex = -1;
            var requireRest = false;
            var argNames = [];

            var macroCallForm = '($name';

            for (arg in argList) {
                if (restIndex != -1) {
                    throw CompileError.fromExp(arg, "macros cannot declare arguments after a &rest or &body argument");
                }
                switch (arg.def) {
                    case Symbol(name):
                        argNames.push(name);
                        if (optIndex == -1) {
                            ++minArgs;
                            macroCallForm += ' [$name]';
                        } else {
                            macroCallForm += ' [?$name]';
                        }
                        ++maxArgs;
                    case MetaExp("opt", {pos: _, def: Symbol(name)}):
                        argNames.push(name);
                        macroCallForm += ' [?$name]';
                        optIndex = maxArgs;
                        ++maxArgs;
                    case MetaExp("rest", {pos: _, def: Symbol(name)}):
                        if (name == "body") {
                            CompileError.warnFromExp(arg, "Consider using &body instead of &rest when writing macros with bodies.");
                        }
                        argNames.push(name);
                        macroCallForm += ' [$name...]';
                        restIndex = maxArgs;
                        maxArgs = null;
                    case MetaExp("body", {pos: _, def: Symbol(name)}):
                        argNames.push(name);
                        macroCallForm += ' [$name...]';
                        restIndex = maxArgs;
                        requireRest = true;
                        maxArgs = null;
                    default:
                        throw CompileError.fromExp(arg, "macro argument should be an untyped symbol or a symbol annotated with &opt or &rest");
                }
            }

            macroCallForm += ')';
            if (optIndex == -1)
                optIndex = minArgs;
            if (restIndex == -1)
                restIndex = optIndex;

            macros[name] = (wholeExp:ReaderExp, innerExps:Array<ReaderExp>, k:KissState) -> {
                wholeExp.checkNumArgs(minArgs, maxArgs, macroCallForm);
                var b = wholeExp.expBuilder();
                var innerArgNames = argNames.copy();

                var args:Map<String, Dynamic> = [];
                for (idx in 0...optIndex) {
                    args[innerArgNames.shift()] = innerExps[idx];
                }
                for (idx in optIndex...restIndex) {
                    args[innerArgNames.shift()] = if (exps.length > idx) innerExps[idx] else null;
                }
                if (innerArgNames.length > 0) {
                    var restArgs = innerExps.slice(restIndex);
                    if (requireRest && restArgs.length == 0) {
                        throw CompileError.fromExp(wholeExp, 'Macro $name requires one or more expression for &body');
                    }
                    args[innerArgNames.shift()] = restArgs;
                }

                // Return the macro expansion:
                return Helpers.runAtCompileTime(b.callSymbol("begin", exps.slice(2)), k, args);
            };

            null;
        };
        renameAndDeprecate("defmacro", "defMacro");

        macros["undefmacro"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, 1, '(undefMacro [name])');

            var name = switch (exps[0].def) {
                case Symbol(name): name;
                default: throw CompileError.fromExp(exps[0], "macro name should be a symbol");
            };

            k.macros.remove(name);
            null;
        };
        renameAndDeprecate("undefmacro", "undefMacro");

        macros["defreadermacro"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(3, null, '(defReaderMacro [optional &start] ["[startingString]" or [startingStrings...]] [[streamArgName]] [body...])');

            // reader macros declared in the form (defreadermacro &start ...) will only be applied
            // at the beginning of lines
            var table = k.readTable;

            // reader macros can define a list of strings that will trigger the macro. When there are multiple,
            // the macro will put back the initiating string into the stream so you can check which one it was
            var strings = switch (exps[0].def) {
                case MetaExp("start", stringsExp):
                    table = k.startOfLineReadTable;
                    stringsThatMatch(stringsExp, "defReaderMacro");
                default:
                    stringsThatMatch(exps[0], "defReaderMacro");
            };
            for (s in strings) {
                switch (exps[1].def) {
                    case ListExp([{pos: _, def: Symbol(streamArgName)}]):
                        table[s] = (stream, k) -> {
                            if (strings.length > 1) {
                                stream.putBackString(s);
                            }
                            var body = CallExp(Symbol("begin").withPos(stream.position()), exps.slice(2)).withPos(stream.position());
                            Helpers.runAtCompileTime(body, k, [streamArgName => stream]).def;
                        };
                    case CallExp(_, []):
                        throw CompileError.fromExp(exps[1], 'expected an argument list. Change the parens () to brackets []');
                    default:
                        throw CompileError.fromExp(exps[1], 'second argument to defreadermacro should be [steamArgName]');
                }
            }

            return null;
        };
        renameAndDeprecate("defreadermacro", "defReaderMacro");

        macros["undefreadermacro"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, 1, '(undefReaderMacro [optional &start] ["[startingString]" or [startingStrings...]])');
            // reader macros undeclared in the form (undefReaderMacro &start ...) will be removed from the table
            // for reader macros that must be at the beginning of lines
            // at the beginning of lines
            var table = k.readTable;

            // reader macros can define a list of strings that will trigger the macro. When there are multiple,
            // this macro will undefine all of them
            var strings = switch (exps[0].def) {
                case MetaExp("start", stringsExp):
                    table = k.startOfLineReadTable;
                    stringsThatMatch(stringsExp, "undefReaderMacro");
                default:
                    stringsThatMatch(exps[0], "undefReaderMacro");
            };
            for (s in strings) {
                table.remove(s);
            }
            return null;
        };
        renameAndDeprecate("undefreadermacro", "undefReaderMacro");

        // Having this floating out here is sketchy, but should work out fine because the variable is always re-set
        // through the next function before being used in defalias or undefalias
        var aliasMap:Map<String, ReaderExpDef> = null;

        function getAliasName(k:KissState, nameExpWithMeta:ReaderExp, formName:String):String {
            var error = CompileError.fromExp(nameExpWithMeta, 'first argument to $formName should be &call [alias] or &ident [alias]');
            var nameExp = switch (nameExpWithMeta.def) {
                case MetaExp("call", nameExp):
                    aliasMap = k.callAliases;
                    nameExp;
                case MetaExp("ident", nameExp):
                    aliasMap = k.identAliases;
                    nameExp;
                default:
                    throw error;
            };
            return switch (nameExp.def) {
                case Symbol(whenItsThis):
                    whenItsThis;
                default:
                    throw error;
            };
        }

        macros["defalias"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(2, 2, "(defAlias [[&call or &ident] whenItsThis] [makeItThis])");
            var name = getAliasName(k, exps[0], "defAlias");

            aliasMap[name] = exps[1].def;
            return null;
        };
        renameAndDeprecate("defalias", "defAlias");

        macros["undefalias"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, 1, "(undefAlias [[&call or &ident] alias])");
            var name = getAliasName(k, exps[0], "undefAlias");

            aliasMap.remove(name);
            return null;
        };
        renameAndDeprecate("undefalias", "undefAlias");

        // Macros that null-check and extract patterns from enums (inspired by Rust)
        function ifLet(wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) {
            wholeExp.checkNumArgs(2, 3, "(ifLet [[enum bindings...]] [thenExp] [?elseExp])");
            var b = wholeExp.expBuilder();

            var thenExp = exps[1];
            var elseExp = if (exps.length > 2) {
                exps[2];
            } else {
                b.symbol("null");
            };

            var bindingList = exps[0].bindingList("ifLet");
            var firstPattern = bindingList.shift();
            var firstValue = bindingList.shift();
            var firstValueSymbol = b.symbol();

            return b.callSymbol("let", [
                b.list([firstValueSymbol, firstValue]),
                b.callSymbol("if", [
                    firstValueSymbol,
                    b.call(
                        b.symbol("case"), [
                            firstValueSymbol,
                            b.call(
                                firstPattern, [
                                    if (bindingList.length == 0) {
                                        exps[1];
                                    } else {
                                        ifLet(wholeExp, [
                                            b.list(bindingList)
                                        ].concat(exps.slice(1)), k);
                                    }
                                ]),
                            b.call(
                                b.symbol("otherwise"), [
                                    elseExp
                                ])
                        ]),
                    elseExp
                ])
            ]);
        }

        macros["ifLet"] = ifLet;

        macros["whenLet"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(2, null, "(whenLet [[enum bindings...]] [body...])");
            var b = wholeExp.expBuilder();
            b.callSymbol("ifLet", [
                exps[0],
                b.begin(exps.slice(1)),
                b.symbol("null")
            ]);
        };

        macros["unlessLet"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(2, null, "(unlessLet [[enum bindings...]] [body...])");
            var b = wholeExp.expBuilder();
            b.callSymbol("ifLet", [
                exps[0],
                b.symbol("null"),
                b.begin(exps.slice(1))
            ]);
        };

        // TODO test this
        function awaitLet(wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) {
            wholeExp.checkNumArgs(2, null, "(awaitLet [[promise bindings...]] [body...])");
            var bindingList = exps[0].bindingList("awaitLet");
            var firstName = bindingList.shift();
            var firstValue = bindingList.shift();
            var b = wholeExp.expBuilder();

            return b.call(b.field("then", firstValue), [
                b.call(b.symbol("lambda"), [
                    b.list([firstName]),
                    if (bindingList.length == 0) {
                        b.call(b.symbol("begin"), exps.slice(1));
                    } else {
                        awaitLet(wholeExp, [b.list(bindingList)].concat(exps.slice(1)), k);
                    }
                ]),
                // Handle rejections:
                b.call(b.symbol("lambda"), [
                    b.list([b.symbol("reason")]),
                    b.call(b.symbol("throw"), [
                        // TODO generalize CompileError to KissError which will also handle runtime errors
                        // with the same source position format
                        b.str("rejected promise")
                    ])
                ])
            ]);
        }

        macros["awaitLet"] = awaitLet;

        // TODO test defNew
        macros["defnew"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, null, "(defNew [[args...]] [[optional property bindings...]] [optional body...]");

            var args = exps.shift();
            var bindingList = [];

            if (exps.length != 0) {
                switch (exps[0].def) {
                    case ListExp(_):
                        bindingList = exps.shift().bindingList("defNew", true);
                    default:
                }
            }
            var bindingPairs = Prelude.groups(bindingList, 2);

            var propertyDefs = [for (bindingPair in bindingPairs) {
                var b = bindingPair[0].expBuilder();
                b.call(b.symbol("prop"), [bindingPair[0]]);
            }];
            var propertySetExps = [for (bindingPair in bindingPairs) {
                var b = bindingPair[1].expBuilder();
                b.call(b.symbol("set"), [b.symbol(Helpers.varName("a prop property binding", bindingPair[0])), bindingPair[1]]);
            }];

            var argList = [];
            // &prop in the argument list defines a property supplied directly as an argument
            for (arg in Helpers.argList(args, "defNew")) {
                var b = arg.expBuilder();
                switch (arg.def) {
                    case MetaExp("prop", propExp):
                        argList.push(propExp);
                        propertyDefs.push(
                            b.call(b.symbol("prop"), [propExp]));
                        // TODO allow &prop &mut or &mut &prop
                        switch (propExp.def) {
                            case TypedExp(_, {pos: _, def: Symbol(name)}):
                                propertySetExps.push(
                                    b.call(b.symbol("set"), [b.field(name, b.symbol("this")), b.symbol(name)]));
                            default:
                                throw CompileError.fromExp(arg, "invalid use of &prop in defNew");
                        }
                    default:
                        argList.push(arg);
                }
            }

            var b = wholeExp.expBuilder();

            return b.begin(propertyDefs.concat([
                b.call(b.symbol("method"), [
                    b.symbol("new"),
                    b.list(argList)
                ].concat(propertySetExps).concat(exps))
            ]));
        };
        renameAndDeprecate("defnew", "defNew");

        macros["collect"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, 1, "(collect [iterator or iterable])");
            var b = wholeExp.expBuilder();
            b.call(b.symbol("for"), [b.symbol("elem"), exps[0], b.symbol("elem")]);
        };

        function once(macroName:String, wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) {
            wholeExp.checkNumArgs(1, null, '($macroName [body...])');
            var b = wholeExp.expBuilder();
            var flag = b.symbol();
            // define the field:
            k.convert(b.call(b.symbol(macroName), [b.meta("mut", flag), b.symbol("true")]));
            return b.call(b.symbol("when"), [flag, b.call(b.symbol("set"), [flag, b.symbol("false")])].concat(exps));
        }

        macros["once"] = once.bind("var");
        macros["oncePerInstance"] = once.bind("prop");

        // Replace "try" with this in a try-catch statement to let all exceptions throw
        // their original call stacks. This is more convenient for debugging than trying to
        // comment out the "try" and its catches, and re-balance parens
        macros["letThrow"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, null, "(letThrow [thing] [catches...])");
            exps[0];
        };

        // The wildest code in Kiss to date
        // TODO test exprCase!!
        macros["exprCase"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(2, null, "(exprCase [expr] [pattern callExps...])");
            var toMatch = exps.shift();

            var b = wholeExp.expBuilder();
            var functionKey = Uuid.v4();

            exprCaseFunctions[functionKey] = (toMatchValue:ReaderExp) -> {
                for (patternExp in exps) {
                    switch (patternExp.def) {
                        case CallExp(pattern, body):
                            if (matchExpr(pattern, toMatchValue)) {
                                return b.begin(body);
                            }
                        default:
                            throw CompileError.fromExp(patternExp, "bad exprCase pattern expression");
                    }
                }

                throw CompileError.fromExp(wholeExp, 'expression ${toMatch.def.toString()} matches no pattern in exprCase');
            };

            return b.call(b.symbol("Macros.exprCase"), [b.str(functionKey), toMatch, b.symbol("k")]);
        };

        // Maybe the NEW wildest code in Kiss?
        macros["#extern"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(4, null, "(#extern <BodyType> <lang> <?compileArgs object> [<typed bindings...>] <body...>)");

            var bodyType = exps.shift();
            var langExp = exps.shift();
            var originalLang = langExp.symbolNameValue();
            // make the lang argument forgiving, because many will assume it can match the compiler defines and command-line arguments of Haxe
            var lang = switch (originalLang) {
                case "python" | "py": "Python";
                case "js" | "javascript": "JavaScript";
                default: originalLang;
            };

            var allowedLangs = EnumTools.getConstructors(CompileLang);
            if (allowedLangs.indexOf(lang) == -1) {
                throw CompileError.fromExp(langExp, 'unsupported lang for #extern: $originalLang should be one of $allowedLangs');
            }
            var langArg = EnumTools.createByName(CompileLang, lang);

            var compileArgsExp = null;
            var bindingListExp = null;
            var nextArg = exps.shift();
            switch (nextArg.def) {
                case CallExp({pos: _, def: Symbol("object")}, _):
                    compileArgsExp = nextArg;
                    nextArg = exps.shift();
                case ListExp(_):
                // Let the next switch handle the binding list
                default:
                    throw CompileError.fromExp(nextArg, "second argument to #extern can either be a CompileArgs object or a list of typed bindings");
            }
            switch (nextArg.def) {
                case ListExp(_):
                    bindingListExp = nextArg;
                default:
                    throw CompileError.fromExp(nextArg, "#extern requires a list of typed bindings");
            }

            var compileArgs:CompilationArgs = if (compileArgsExp != null) {
                Helpers.runAtCompileTimeDynamic(compileArgsExp, k);
            } else {
                {};
            }

            var b = wholeExp.expBuilder();

            // TODO generate tink_json writers and parsers for this
            var bindingList = bindingListExp.bindingList("#extern", true);

            var idx = 0;
            var stringifyExpList = [];
            var parseBindingList = [];
            while (idx < bindingList.length) {
                var type = "";
                var untypedName = switch (bindingList[idx].def) {
                    case TypedExp(_type, symbol = {pos: _, def: Symbol(name)}):
                        type = _type;
                        symbol;
                    default: throw CompileError.fromExp(bindingList[idx], "name in #extern binding list must be a typed symbol");
                };
                switch (bindingList[idx + 1].def) {
                    // _ in the value position of the #extern binding list will reuse the name as the value
                    case Symbol("_"):
                        bindingList[idx + 1] = untypedName;
                    default:
                }
                stringifyExpList.push(b.the(b.symbol("String"), b.callSymbol("tink.Json.stringify", [b.the(b.symbol(type), bindingList[idx + 1])])));
                parseBindingList.push(bindingList[idx]);
                parseBindingList.push(b.callSymbol("tink.Json.parse", [b.callField("readLine", b.callSymbol("Sys.stdin", []), [])]));
                idx += 2;
            }

            var externExps = [
                b.print(
                    b.callSymbol("tink.Json.stringify", [
                        b.the(bodyType, if (bindingList.length > 0) {
                            b.let(parseBindingList, exps);
                        } else {
                            b.begin(exps);
                        })
                    ]))
            ];
            b.the(
                bodyType,
                b.callSymbol("tink.Json.parse", [
                    b.call(b.raw(CompilerTools.compileToScript(externExps, langArg, compileArgs).toString()), [b.list(stringifyExpList)])
                ]));
        };

        return macros;
    }

    static var exprCaseFunctions:Map<String, ReaderExp->ReaderExp> = [];

    public static function exprCase(id:String, toMatchValue:ReaderExp, k:KissState):ReaderExp {
        return Helpers.runAtCompileTime(exprCaseFunctions[id](toMatchValue), k);
    }

    static function matchExpr(pattern:ReaderExp, instance:ReaderExp):Bool {
        switch (pattern.def) {
            case Symbol("_"):
                return true;
            case CallExp({pos: _, def: Symbol("exprOr")}, altPatterns):
                for (altPattern in altPatterns) {
                    if (matchExpr(altPattern, instance))
                        return true;
                }
                return false;
            case Symbol(patternSymbol):
                return switch (instance.def) {
                    case Symbol(instanceSymbol) if (patternSymbol == instanceSymbol):
                        true;
                    default:
                        false;
                };
            case ListExp(patternExps):
                switch (instance.def) {
                    case ListExp(instanceExps) if (patternExps.length == instanceExps.length):
                        for (idx in 0...patternExps.length) {
                            if (!matchExpr(patternExps[idx], instanceExps[idx]))
                                return false;
                        }
                        return true;
                    default:
                        return false;
                }
            case CallExp(patternFuncExp, patternExps):
                switch (instance.def) {
                    case CallExp(instanceFuncExp, instanceExps) if (patternExps.length == instanceExps.length):
                        if (!matchExpr(patternFuncExp, instanceFuncExp))
                            return false;
                        for (idx in 0...patternExps.length) {
                            if (!matchExpr(patternExps[idx], instanceExps[idx]))
                                return false;
                        }
                        return true;
                    default:
                        return false;
                }
            // I don't think I'll ever want to match specific string literals, raw haxe, field expressions,
            // key-value expressions, quasiquotes, unquotes, or UnquoteLists. This function can be expanded
            // later if those features are ever needed.
            default:
                throw CompileError.fromExp(pattern, "unsupported pattern for exprCase");
        }
    }

    // cond expands telescopically into a nested if expression
    static function cond(formName:String, underlyingIf:String, wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) {
        wholeExp.checkNumArgs(1, null, '($formName [cases...])');
        var b = wholeExp.expBuilder();
        return switch (exps[0].def) {
            case CallExp(condition, body):
                b.call(b.symbol(underlyingIf), [
                    condition,
                    b.begin(body),
                    if (exps.length > 1) {
                        cond(formName, underlyingIf, b.callSymbol(formName, exps.slice(1)), exps.slice(1), k);
                    } else {
                        b.symbol("null");
                    }
                ]);
            default:
                throw CompileError.fromExp(exps[0], 'top-level expression of (cond... ) must be a call list starting with a condition expression');
        };
    }
}
