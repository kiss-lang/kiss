package kiss;

import haxe.macro.Expr;
import haxe.macro.Context;
import kiss.Reader;
import kiss.ReaderExp;
import kiss.Helpers;
import kiss.Stream;
import kiss.KissError;
import kiss.Kiss;

using kiss.Kiss;
using kiss.Helpers;
using kiss.Reader;
using StringTools;

// Field forms convert Kiss reader expressions into Haxe macro class fields
typedef FieldFormFunction = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> Field;

class FieldForms {
    public static function addBuiltins(k:KissState):Void {
        varOrProperty("var", k);
        varOrProperty("prop", k);

        funcOrMethod("function", k);
        funcOrMethod("method", k);

        k.doc("redefineWithObjectArgs", 2, 3, '(redefineWithObjectArgs <function or method name> <new function or method name> <optional [<preserved list args...>]>)');
        k.fieldForms["redefineWithObjectArgs"] = redefineWithObjectArgs;
    }

    static function fieldAccess(formName:String, fieldName:String, nameExp:ReaderExp, ?access:Array<Access>) {
        if (access == null) {
            access = if (["defvar", "defprop", "var", "prop"].indexOf(formName) != -1) {
                [AFinal];
            } else {
                [];
            };
        }
        // AMacro access is not allowed because it wouldn't make sense to write Haxe macros in Kiss
        // when you can write Kiss macros which are just as powerful
        return switch (nameExp.def) {
            case MetaExp("mut", nameExp):
                access.remove(AFinal);
                fieldAccess(formName, fieldName, nameExp, access);
            case MetaExp("override", nameExp):
                access.push(AOverride);
                fieldAccess(formName, fieldName, nameExp, access);
            case MetaExp("dynamic", nameExp):
                access.push(ADynamic);
                fieldAccess(formName, fieldName, nameExp, access);
            case MetaExp("inline", nameExp):
                access.push(AInline);
                fieldAccess(formName, fieldName, nameExp, access);
            case MetaExp("final", nameExp):
                access.push(AFinal);
                fieldAccess(formName, fieldName, nameExp, access);
            case MetaExp("public", nameExp):
                access.push(APublic);
                fieldAccess(formName, fieldName, nameExp, access);
            case MetaExp("private", nameExp):
                access.push(APrivate);
                fieldAccess(formName, fieldName, nameExp, access);
            default:
                if (["defvar", "defun", "var", "function"].indexOf(formName) != -1) {
                    access.push(AStatic);
                }
                // If &public or &private is not used, a shortcut to make a private field is
                // to start its name with _
                if (access.indexOf(APrivate) == -1 && access.indexOf(APublic) == -1) {
                    access.push(if (fieldName.startsWith("_")) APrivate else APublic);
                }
                access;
        };
    }

    static function isVoid(nameExp:ReaderExp) {
        return switch (nameExp.def) {
            case MetaExp(_, nameExp):
                isVoid(nameExp);
            case TypedExp("Void", _) | Symbol("new"):
                true;
            default:
                false;
        }
    }

    static function varOrProperty(formName:String, k:KissState) {
        k.doc(formName, 1, 3, '($formName <optional &mut> <optional :Type> <name> <optional value>)');
        k.fieldForms[formName] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> {
            var name = Helpers.varName(formName, args[0]);
            checkPrintFieldsCalledWarning(name, wholeExp, k);
            var access = fieldAccess(formName, name, args[0]);

            var type = Helpers.explicitType(args[0], k);
            k.addVarInScope(
                {name: name, type: type}, 
                false,
                access.indexOf(AStatic) != -1);
                
            function varOrPropKind(args:Array<ReaderExp>) {
                return if (args.length > 1) {
                    switch (args[1].def) {
                        case CallExp({pos:_, def:Symbol("property")}, innerArgs):
                            args[1].checkNumArgs(2, 3, "(property <read access> <write access> <?value>)");
                            function accessType(read, arg) {
                                var acceptable = ["default", "null", if (read) "get" else "set", "dynamic", "never"];
                                return switch (arg.def) {
                                    case Symbol(access) if (acceptable.contains(access)):
                                        access;
                                    default: throw KissError.fromExp(arg, 'Expected a haxe property access keyword: one of [${acceptable.join(", ")}]');
                                };
                            }
                            var readAccess = accessType(true, innerArgs[0]);
                            var writeAccess = accessType(false, innerArgs[1]);
                            var value = if (innerArgs.length > 2) k.convert(innerArgs[2]) else null;
                            FProp(readAccess, writeAccess, type, value);
                        default:
                            FVar(type, k.convert(args[1]));
                    };
                } else {
                    FVar(type, null);
                };
            }

            ({
                name: name,
                access: access,
                kind: varOrPropKind(args), 
                pos: wholeExp.macroPos()
            } : Field);
        }
    }

    static function redefineWithObjectArgs(wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState):Field {
        switch (args[0].def) {
            case Symbol(field):
                var originalFunction = k.fieldDict[field];

                if (originalFunction == null) {
                    throw KissError.fromExp(wholeExp, 'Function or method $field does not exist to be redefined');
                }

                switch (args[1].def) {
                    case Symbol(newFieldName):
                        var newField = {
                            pos: wholeExp.macroPos(),
                            name: newFieldName,
                            meta: originalFunction.meta,
                            access: originalFunction.access,
                            kind: FFun(switch(originalFunction.kind) {
                                case FFun({ret: ret, params: params, args: originalArgs}):
                                    var argIndexMap = new Map<String,Int>();
                                    var argMap = new Map<String,Null<FunctionArg>>();
                                    for (idx in 0... originalArgs.length) {
                                        var originalArg = originalArgs[idx];
                                        argIndexMap[originalArg.name] = idx;
                                        argMap[originalArg.name] = originalArg;
                                    }

                                    var callExpArgs:Array<Expr> = [for (_ in 0... originalArgs.length) macro null];
                                    var newArgs = if (args.length > 2) {
                                        [for (argSymbol in Helpers.argList(args[2], "redefineWithObjectArgs"))
                                            switch (argSymbol.def) {
                                                case Symbol(argName):
                                                    if (!argMap.exists(argName)) {
                                                        throw KissError.fromExp(argSymbol, '$argName is not an argument in the original function or method $field');
                                                    }
                                                    var arg = argMap[argName];
                                                    var index = argIndexMap[argName];
                                                    argMap.remove(argName);
                                                    argIndexMap.remove(argName);
                                                    callExpArgs[index] = macro $i{argName};
                                                    arg;
                                                default:
                                                    throw KissError.fromExp(argSymbol, 'arguments in an arg list for (redefineWithObjectArgs...) should be plain symbols matching arg names of the original function or method');
                                            }
                                        ];
                                    } else {
                                        []; 
                                    };

                                    var additionalArgsName = 'additionalArgs${uuid.Uuid.v4().replace("-", "_")}';
                                    var isOpt = true;
                                    var fields:Array<Field> = [];
                                    for (argName => arg in argMap) {
                                        if (arg.opt == null || arg.opt == false)
                                            isOpt = false;
                                        fields.push({
                                            name: argName,
                                            pos: wholeExp.macroPos(),
                                            meta: arg.meta,
                                            kind: FVar(arg.type, null)
                                        });
                                        callExpArgs[argIndexMap[argName]] = macro $i{additionalArgsName}?.$argName;
                                    }
                                    var additionalArgType = TAnonymous(fields);
                                    newArgs.push({
                                        name: additionalArgsName,
                                        opt: isOpt,
                                        type: additionalArgType
                                    });

                                    var exp = macro $i{field}($a{callExpArgs});
                                    switch (ret) {
                                        case TPath({pack:[], name: "Void"}):
                                        default:
                                            exp = macro return $exp;
                                    }

                                    {
                                        ret: ret,
                                        params: params,
                                        args: newArgs,
                                        expr: exp
                                    };
                                default:
                                    throw KissError.fromExp(args[0], '$field is not a function or method');
                            })
                        };

                        return newField;

                    default:
                        throw KissError.fromExp(wholeExp, "The second argument to (redefineWithObjectArgs...) should be a plain symbol of a new function or method name");
                }


            default:
                throw KissError.fromExp(args[0], "The first argument to (redefineWithObjectArgs...) should be a plain symbol of a function or method name");
        }
    }

    static function funcOrMethod(formName:String, k:KissState) {
        k.doc(formName, 2, null, '($formName <optional &dynamic> <optional :Type> <name> [<argNames...>] <body...>)');
        k.fieldForms[formName] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> {
            var name = Helpers.varName(formName, args[0]);
            var access = fieldAccess(formName, name, args[0]);
            var inStaticFunction = access.indexOf(AStatic) != -1;
            var returnsValue = !isVoid(args[0]);

            var wasInStatic = k.inStaticFunction;
            var typeParams = switch (args[1].def) {
                case TypeParams(p):
                    args.splice(1, 1);    
                    p;
                default:
                    [];
            } 

            var f:Field = {
                name: name,
                access: access,
                kind: FFun(
                    Helpers.makeFunction(
                        args[0],
                        returnsValue,
                        args[1],
                        args.slice(2),
                        k.forStaticFunction(inStaticFunction),
                        formName,
                        typeParams)),
                pos: wholeExp.macroPos()
            };

            k = k.forStaticFunction(wasInStatic);
            return f;
        }
    }

    static function checkPrintFieldsCalledWarning(name, exp:ReaderExp, k:KissState) {
        if (k.printFieldsCalls.length > 0) {
            KissError.warnFromExp(exp, 'new field "$name" defined here will not be printed by preceding print macro(s)');
            for (printCall in k.printFieldsCalls) {
                KissError.warnFromExp(printCall, "print macro used here");
            }
        }
    }
}
