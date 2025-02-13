package kiss;

#if macro
import haxe.Exception;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.PositionTools;
import haxe.io.Path;
import sys.io.File;
import kiss.Prelude;
import kiss.Stream;
import kiss.Reader;
import kiss.ReaderExp;
import kiss.FieldForms;
import kiss.SpecialForms;
import kiss.Macros;
import kiss.KissError;
import kiss.cloner.Cloner;
import tink.syntaxhub.*;
import tink.macro.Exprs;
import haxe.ds.Either;
import kiss.EType;
import haxe.ds.HashMap;

using kiss.Kiss;
using kiss.Helpers;
using kiss.Reader;
using tink.MacroApi;
using haxe.io.Path;
using StringTools;
using hx.strings.Strings;

typedef ExprConversion = (ReaderExp) -> Expr;

typedef FormDoc = {
    minArgs:Null<Int>,
    maxArgs:Null<Int>,
    ?expectedForm:String,
    ?doc:String
};

typedef KissState = {
    > HasReadTables,
    className:String,
    pack:Array<String>,
    file:String,
    fieldForms:Map<String, FieldFormFunction>,
    specialForms:Map<String, SpecialFormFunction>,
    specialFormMacroExpanders:Map<String, MacroFunction>,
    macros:Map<String, MacroFunction>,
    formDocs:Map<String, FormDoc>,
    doc:(String, Null<Int>, Null<Int>, ?String, ?String)->Void,
    wrapListExps:Bool,
    loadedFiles:Map<String, Null<ReaderExp>>,
    callAliases:Map<String, ReaderExpDef>,
    typeAliases:Map<String, String>,
    fieldList:Array<Field>,
    // TODO This map was originally created to track whether the programmer wrote their own main function, but could also
    // be used to allow macros to edit fields that were already defined (for instance, to decorate a function or add something
    // to the constructor body)
    fieldDict:Map<String, Field>,
    loadingDirectory:String,
    hscript:Bool,
    macroVars:Map<String, Dynamic>,
    collectedBlocks:Map<String, Array<ReaderExp>>,
    inStaticFunction:Bool,
    typeHints:Array<Var>,
    varsInScope:Array<Var>,
    varsInScopeAreStatic:Array<Bool>,
    localVarsInScope:Array<Var>,
    conversionStack:Array<ReaderExp>,
    stateChanged:Bool,
    printFieldsCalls:Array<ReaderExp>,
    localVarCalls:Array<ReaderExp>
};
#end

class Kiss {
    #if macro
    public static function defaultKissState(?context:FrontendContext):KissState {
        Sys.putEnv("KISS_BUILD_HXML", Prelude.joinPath(Helpers.libPath("kiss"), "build.hxml"));

        var className = "";
        var pack = [];
        if (context == null) {
            var clazz = Context.getLocalClass().get();
            className = clazz.name;
            pack = clazz.pack;
        } else {
            className = context.name;
            pack = context.pack;
        }
        var k = {
            className: className,
            pack: pack,
            file: "",
            readTable: Reader.builtins(),
            startOfLineReadTable: new ReadTable(),
            startOfFileReadTable: new ReadTable(),
            endOfFileReadTable: new ReadTable(),
            fieldForms: new Map(),
            specialForms: null,
            specialFormMacroExpanders: null,
            macros: null,
            formDocs: new Map(),
            doc: null,
            wrapListExps: true,
            loadedFiles: new Map<String, ReaderExp>(),
            // Helpful built-in aliases
            // These ones might conflict with a programmer's variable names, so they only apply in call expressions:
            callAliases: [
                // TODO some of these probably won't conflict, and could be passed as functions for a number of reasons
                "print" => Symbol("Prelude.print"),
                "sort" => Symbol("Prelude.sort"),
                "sortBy" => Symbol("Prelude.sortBy"),
                "groups" => Symbol("Prelude.groups"),
                "pairs" => Symbol("Prelude.pairs"),
                "reverse" => Symbol("Prelude.reverse"),
                "memoize" => Symbol("Prelude.memoize"),
                "fsMemoize" => Symbol("Prelude.fsMemoize"),
                "symbolName" => Symbol("Prelude.symbolName"),
                "symbolNameValue" => Symbol("Prelude.symbolNameValue"),
                "typeNameValue" => Symbol("Prelude.typeNameValue"),
                "metaNameValue" => Symbol("Prelude.metaNameValue"),
                "typeName" => Symbol("Prelude.typeNameValue"),
                "symbol" => Symbol("Prelude.symbol"),
                "expList" => Symbol("Prelude.expList"),
                "map" => Symbol("Lambda.map"),
                "filter" => Symbol("Prelude.filter"),
                "flatten" => Symbol("Lambda.flatten"),
                "has" => Symbol("Lambda.has"),
                "count" => Symbol("Lambda.count"),
                "enumerate" => Symbol("Prelude.enumerate"),
                "assertProcess" => Symbol("Prelude.assertProcess"),
                "tryProcess" => Symbol("Prelude.tryProcess"),
                "userHome" => Symbol("Prelude.userHome"),
                "random" => Symbol("Std.random"),
                "walkDirectory" => Symbol("Prelude.walkDirectory"),
                "purgeDirectory" => Symbol("Prelude.purgeDirectory"),
                "getTarget" => Symbol("Prelude.getTarget"),
                "fuzzyGet" => Symbol("kiss.FuzzyMapTools.fuzzyGet"),
                // These work with (apply) because they are added as "opAliases" in Macros.hx:
                "min" => Symbol("Prelude.min"),
                "max" => Symbol("Prelude.max"),
                "iHalf" => Symbol("Prelude.iHalf"),
                "iThird" => Symbol("Prelude.iThird"),
                "iFourth" => Symbol("Prelude.iFourth"),
                "iFifth" => Symbol("Prelude.iFifth"),
                "iSixth" => Symbol("Prelude.iSixth"),
                "iSeventh" => Symbol("Prelude.iSeventh"),
                "iEighth" => Symbol("Prelude.iEighth"),
                "iNinth" => Symbol("Prelude.iNinth"),
                "iTenth" => Symbol("Prelude.iTenth"),
                "fHalf" => Symbol("Prelude.fHalf"),
                "fThird" => Symbol("Prelude.fThird"),
                "fFourth" => Symbol("Prelude.fFourth"),
                "fFifth" => Symbol("Prelude.fFifth"),
                "fSixth" => Symbol("Prelude.fSixth"),
                "fSeventh" => Symbol("Prelude.fSeventh"),
                "fEighth" => Symbol("Prelude.fEighth"),
                "fNinth" => Symbol("Prelude.fNinth"),
                "fTenth" => Symbol("Prelude.fTenth"),
                "uuid" => Symbol("Prelude.uuid"),
            ],
            identAliases: [
                // These ones won't conflict with variables and might commonly be used with (apply)
                "+" => Symbol("Prelude.add"),
                "-" => Symbol("Prelude.subtract"),
                "*" => Symbol("Prelude.multiply"),
                "/" => Symbol("Prelude.divide"),
                "%" => Symbol("Prelude.mod"),
                "^" => Symbol("Prelude.pow"),
                ">" => Symbol("Prelude.greaterThan"),
                ">=" => Symbol("Prelude.greaterEqual"),
                "<" => Symbol("Prelude.lessThan"),
                "<=" => Symbol("Prelude.lesserEqual"),
                "=" => Symbol("Prelude.areEqual"),
                // These ones *probably* won't conflict with variables and might be passed as functions
                "chooseRandom" => Symbol("Prelude.chooseRandom"),
                // These ones *probably* won't conflict with variables and might commonly be used with (apply) because they are variadic
                "joinPath" => Symbol("Prelude.joinPath"),
                "readDirectory" => Symbol("Prelude.readDirectory"),
                "substr" => Symbol("Prelude.substr"),
                "isListExp" => Symbol("Prelude.isListExp"),
                "isNull" => Symbol("Prelude.isNull"),
                "isNotNull" => Symbol("Prelude.isNotNull")
                /* zip functions used to live here as aliases but now they are macros that also
                apply (the Array<Array<Dynamic>>) to the result */
                /* intersect used to live here as an alias but now it is in a macro that also
                applies (the Array<Array<Dynamic>>) to the result */
                /* concat used to live here as an alias but now it is in a macro that also
                applies (the Array<Dynamic>) to the result */
            ],
            typeAliases: new Map(),
            fieldList: [],
            fieldDict: new Map(),
            loadingDirectory: "",
            hscript: false,
            macroVars: new Map(),
            collectedBlocks: new Map(),
            inStaticFunction: false,
            typeHints: [],
            varsInScope: [],
            varsInScopeAreStatic: [],
            localVarsInScope: [],
            conversionStack: [],
            stateChanged: false,
            printFieldsCalls: [],
            localVarCalls: []
        };

        k.doc = (form:String, minArgs:Null<Int>, maxArgs:Null<Int>, expectedForm = "", doc = "") -> {
            k.formDocs[form] = {
                minArgs: minArgs,
                maxArgs: maxArgs,
                expectedForm: expectedForm,
                doc: doc
            };
            return;
        };

        FieldForms.addBuiltins(k);
        k.specialForms = SpecialForms.builtins(k, context);
        k.specialFormMacroExpanders = SpecialForms.builtinMacroExpanders(k, context);
        k.macros = Macros.builtins(k);

        return k;
    }

    public static function _try<T>(operation:() -> T, ?expectedError:EType):Null<T> {
        #if !macrotest
        try {
        #end
            return operation();
        #if !macrotest
        } catch (err:StreamError) {
            function printErr() {
                Sys.stderr().writeString(err + "\n");
            }
            switch (expectedError) {
                case EAny:
                    throw EExpected(EAny);
                case EStream(message) if (message == err.message):
                    throw EExpected(expectedError);
                case null:
                    printErr();
                    Sys.exit(1);
                    return null;
                default:
                    printErr();
                    throw EUnexpected(err);
            }
        } catch (err:KissError) {
            function printErr() {
                Sys.stderr().writeString(err + "\n");
            }
            switch (expectedError) {
                case EAny:
                    throw EExpected(EAny);
                case EKiss(message) if (message == err.message):
                    throw EExpected(expectedError);
                case null:
                    printErr();
                    Context.onGenerate((types) -> {
                        Sys.exit(1);
                    });
                    return null;
                default:
                    printErr();
                    throw EUnexpected(err);
            }
        } catch (err:UnmatchedBracketSignal) {
            function printErr() {
                Sys.stderr().writeString(Stream.toPrint(err.position) + ': Unmatched ${err.type}\n');
            }
            switch (expectedError) {
                case EAny:
                    throw EExpected(EAny);
                case EUnmatchedBracket(type) if (type == err.type):
                    throw EExpected(expectedError);
                case null:
                    printErr();
                    Context.onGenerate((types) -> {
                        Sys.exit(1);
                    });
                    return null;
                default:
                    printErr();
                    throw EUnexpected(err);
            }
        } catch (err:EType) {
            throw err;
        } catch (err:Exception) {
            function printErr() {
                Sys.stderr().writeString("Error: " + err.message + "\n");
                Sys.stderr().writeString(err.stack.toString() + "\n");
            }
            switch (expectedError) {
                case EAny:
                    throw EExpected(EAny);
                case EException(message) if (message == err.message):
                    throw EExpected(expectedError);
                case null:
                    printErr();
                    Context.onGenerate((types) -> {
                        Sys.exit(1);
                    });
                    return null;
                default:
                    printErr();
                    throw EUnexpected(err);
            }
        }
        #end
    }

    #end
    
    #if macro
    static function addContextFields(k:KissState, useClassFields:Bool) {
        if (useClassFields) {
            k.fieldList = Context.getBuildFields();
            for (field in k.fieldList) {
                k.fieldDict[field.name] = field;
                switch (field.kind) {
                    case FVar(t, e) | FProp(_, _, t, e):
                        var v = {
                            name: field.name,
                            type: t,
                            expr: e
                        };
                        k.addVarInScope(v, false, field.access.indexOf(AStatic) != -1);
                    default:
                }

            }
        }
    }

    // This is only for testing:
    public static function buildExpectingError(expectedError:ExprOf<EType>, ?kissFile:String, ?k:KissState, useClassFields = true, ?context:FrontendContext):Array<Field> {
        var buildFields = Context.getBuildFields();
        var hasTestExpectedError = false;
        for (field in buildFields) {
            switch (field) {
                case {
                    name: "testExpectedError",
                    kind: FFun({
                        params: [],
                        expr: {
                            expr: EBlock([{expr: ECall({expr: EConst(CIdent("_testExpectedError"))}, [])}])
                        }
                    })
                }:
                    hasTestExpectedError = true;
                default:
            }
        }
        if (!hasTestExpectedError) {
            throw "When building with Kiss.buildExpectingError(), you must add this Haxe function: " +
                "function testExpectedError() { _testExpectedError(); }";
        }

        var expectedError = Exprs.eval(expectedError);
        var s = Std.string(expectedError);

        try {
            build(kissFile, k, useClassFields, context, expectedError);

            // Build success, which is bad:
            buildFields.push({
                pos: Context.currentPos(),
                name: "_testExpectedError",
                kind: FFun({
                    args: [],
                    expr: macro utest.Assert.fail('Build succeeded when an error was expected: ' + $v{s})
                })
            });
        } catch (e:EType) {
            switch (e) {
                case EExpected(e):
                    buildFields.push({
                        pos: Context.currentPos(),
                        name: "_testExpectedError",
                        kind: FFun({
                            args: [],
                            expr: macro utest.Assert.pass()
                        })
                    });
                case EUnexpected(e):
                    buildFields.push({
                        pos: Context.currentPos(),
                        name: "_testExpectedError",
                        kind: FFun({
                            args: [],
                            expr: macro utest.Assert.fail('Build failed in an unexpected way. Expected: ' + $v{s})
                        })
                    });
                default:
                    throw "unexpected error is neither expected nor unexpected ¯\\_(ツ)_/¯";
            }
        }

        return buildFields;
    }

    /**
        Build macro: add fields to a class from a corresponding .kiss file
    **/
    public static function build(?kissFile:String, ?k:KissState, useClassFields = true, ?context:FrontendContext, ?expectedError:EType):Array<Field> {

        var classPath = Context.getPosInfos(Context.currentPos()).file;
        // (load... ) relative to the original file
        var loadingDirectory = if (classPath == '?') {
            var p = Path.directory(kissFile);
            kissFile = kissFile.withoutDirectory();
            p;
        } else {
            Path.directory(classPath);
        }
        if (kissFile == null) {
            kissFile = classPath.withoutDirectory().withoutExtension().withExtension("kiss");
        }
        //trace('kiss build $kissFile');

        var result = _try(() -> {
            #if profileKiss
            Kiss.measure('Compiling kiss: $kissFile', () -> {
            #end
                if (k == null)
                    k = defaultKissState(context);

                k.addContextFields(useClassFields);
                k.loadingDirectory = loadingDirectory;

                var topLevelBegin = load(kissFile, k, null, null, null, expectedError);

                if (topLevelBegin != null) {
                    // If no main function is defined manually, Kiss expressions at the top of a file will be put in a main function.
                    // If a main function IS defined, this will result in an error
                    if (k.fieldDict.exists("main")) {
                        throw KissError.fromExp(topLevelBegin, '$kissFile has expressions outside of field definitions, but already defines its own main function.');
                    }
                    var b = topLevelBegin.expBuilder();
                    // This doesn't need to be added to the fieldDict because all code generation is done
                    k.fieldList.push({
                        name: "main",
                        access: [AStatic,APublic],
                        kind: FFun(Helpers.makeFunction(
                            b.symbol("main"),
                            false,
                            b.list([]),
                            [topLevelBegin],
                            k,
                            "function",
                            [])),
                        pos: topLevelBegin.macroPos()
                    });
                }

            #if (profileKiss == 1)
            });
            #elseif (profileKiss > 1)
            });
            // Sort and print detailed compilation profiling output:
            var zippedInfo = [
                for (label => timeSpent in profileAggregates) {
                    var usageCount = profileUsageCounts[label];
                    
                    var averageTime = (timeSpent / usageCount);
                    if (averageTime >= SIGNIFICANT_AVERAGE_TIME || timeSpent >= SIGNIFICANT_TIME_SPENT) {
                        var arr:Array<Dynamic> = [];
                        arr.push(label);
                        arr.push(averageTime);
                        arr.push(usageCount);
                        arr.push(timeSpent);
                        arr;
                    }
                }
            ];
            zippedInfo.sort((a, b) -> Std.int(b[3] * 1000) - Std.int(a[3] * 1000));
            for (info in zippedInfo) {
                var label = info[0];
                var averageTime = info[1];
                var usageCount = info[2];
                var timeSpent = info[3];
                var averageEgregious = averageTime >= SIGNIFICANT_AVERAGE_TIME * EGREGIOUS;
                var totalEgregious = timeSpent >= SIGNIFICANT_TIME_SPENT * EGREGIOUS;
                
                if (averageEgregious || totalEgregious) {
                    Sys.print(Prelude.ANSI.RED);
                }
                Sys.print('${info[0]}: ');
                Sys.print(Prelude.ANSI.RESET);
                
                if (averageEgregious) {
                    Sys.print(Prelude.ANSI.RED);
                }
                Sys.print('${info[1]} x ');
                Sys.print(Prelude.ANSI.RESET);

                Sys.print('${usageCount} = ');
                
                if (totalEgregious) {
                    Sys.print(Prelude.ANSI.RED);
                }
                Sys.println(timeSpent);
                Sys.print(Prelude.ANSI.RESET);
            }

            #end
            k.fieldList;
        }, expectedError);
        #if kissCache
        File.saveContent(cacheFile, haxe.Json.stringify([for (key => value in expCache) key.value => value]));
        #end
        return result;
    }

    static final fossilStart = "\n\t// BEGIN KISS FOSSIL CODE\n\t// "; // TODO remove the boneyard comments
    static final fossilEnd = "\t// END KISS FOSSIL CODE\n";

    static function complexTypeToString(type:ComplexType, emptyForVoid = false) {
        var fossilCode = "";
        switch (type) {
            case TPath(path):
                if (path.pack.length > 0) {
                    fossilCode += path.pack.join(".") + ".";
                }
                fossilCode += path.name;
                if (path.sub != null) {
                    fossilCode += "." + path.sub;
                }
                if (path.params != null && path.params.length > 0) {
                    fossilCode += "<";
                    fossilCode += [for (param in path.params) {
                        switch (param) {
                            case TPType(t):
                                complexTypeToString(t);
                            default:
                                '{type parameter $param is not supported for fossilization}';
                        }
                    }].join(",");
                    fossilCode += ">";
                }
            case TFunction(args, ret):
                fossilCode += "(";
                fossilCode += [for (arg in args) complexTypeToString(arg, true)].join(",");
                fossilCode += ")->";
                fossilCode += complexTypeToString(ret);
            case TAnonymous(fields):
                fossilCode += "{";
                fossilCode += [for (field in fields) {
                    field.name + ":" + switch(field.kind) {
                        case FVar(type, _):
                            complexTypeToString(type);
                        default:
                            '{field type $type not supported in anonymous object typedef fossilization}';
                    }
                }].join(",");
                fossilCode += "}";

            default:
                fossilCode += '{ComplexType $type not supported for fossilization}';
        }
        if (emptyForVoid && fossilCode == "Void") return "";
        return fossilCode;
    }

    public static function typeParamDeclToString(param:TypeParamDecl) {
        var str = param.name;

        if (param.params != null && param.params.length > 0) {
            str += "<";
            str += [for (innerParam in param.params) typeParamDeclToString(innerParam)].join(",");
            str += ">";
        }

        if (param.defaultType != null || (param.constraints != null && param.constraints.length > 0)) {
            str += "{type paramater default types and constraints are not supported for fossilization}";
        }

        return str;
    }

    public static function toStringTabbed(e:Expr) {
        var str = e.toString();
        return str.replace("\n", "\n\t");
    }

    public static function fossilBuild(?kissFile:String, ?k:KissState, useClassFields = true, ?context:FrontendContext, ?expectedError:EType):Array<Field> {
        var pos = Context.currentPos();
        var haxeFile = Context.getPosInfos(pos).file;

        if (kissFile == null) {
            kissFile = haxeFile.withoutDirectory().withoutExtension().withExtension("kiss");
        }

        var haxeMTime = sys.FileSystem.stat(haxeFile).mtime;
        var haxeContent = File.getContent(haxeFile).replace("\r", "");
        
        var fossilToolsPath = Prelude.joinPath(Helpers.libPath("kiss"), "src/kiss/Kiss.hx");
        var pathsWhichTriggerRebuild = [fossilToolsPath];

        if (haxeContent.contains(fossilStart)) {
            var loadedFilesIndex = haxeContent.indexOf(fossilStart) + fossilStart.length;
            var loadedFilesStr = haxeContent.substring(loadedFilesIndex, haxeContent.indexOf("\n", loadedFilesIndex));
            pathsWhichTriggerRebuild = pathsWhichTriggerRebuild.concat(haxe.Json.parse(loadedFilesStr));
        } else {
            pathsWhichTriggerRebuild.push(Path.join([Path.directory(haxeFile), kissFile]));
        }

        var rebuildMTime = Math.NEGATIVE_INFINITY;
        for (path in pathsWhichTriggerRebuild) {
            var fileMTime = sys.FileSystem.stat(path).mtime.getTime();
            if (fileMTime > rebuildMTime) {
                rebuildMTime = fileMTime;
            }
        }

        
        // return blank array if haxefile is changed more recently than the Kiss
        if (haxeMTime.getTime() > rebuildMTime && haxeContent.contains(fossilStart)) {
            return Context.getBuildFields();
        } else {
            if (k == null) k = defaultKissState(context);

            // Kiss generate the fields, which we then add to the Haxe
            var fields = build(kissFile, k, false, context, expectedError);

            var loadedFiles = [for (file => _ in k.loadedFiles) file];

            var haxeContentStart = haxeContent;

            if (haxeContent.contains(fossilStart)) {
                var fossilStartIdx = haxeContent.indexOf(fossilStart);
                var fossilEndIdx = haxeContent.indexOf(fossilEnd) + fossilEnd.length;

                haxeContentStart = haxeContent.substr(0, fossilStartIdx) + haxeContent.substr(fossilEndIdx);
            }

            var fossilCode = haxe.Json.stringify(loadedFiles) + "\n";
            var buildFieldNames = [for (field in Context.getBuildFields()) field.name => field];
            for (field in fields) {
                fossilCode += "\t";
                if (buildFieldNames.exists(field.name)) {
                    buildFieldNames.remove(field.name);
                }

                // Field modifiers:
                var accessOrder = [
                    APublic,
                    APrivate,
                    AStatic,
                    AOverride,
                    ADynamic,
                    AFinal
                ];
                
                var isFinal = false;
                for (access in accessOrder) {
                    if (field.access.contains(access)) {
                        if (access == AFinal) isFinal = true;
                        else fossilCode += Std.string(access).substr(1).toLowerCase() + " ";
                    }
                }

                switch(field.kind) {
                    case FVar(type, e):
                        // Variables:
                        if (isFinal)
                            fossilCode += "final ";
                        if (!isFinal)
                            fossilCode += "var ";
                        fossilCode += field.name;
                        if (type != null) {
                            fossilCode += ":";
                            fossilCode += complexTypeToString(type);
                        }
                        if (e != null) {
                            fossilCode += ' = ' + toStringTabbed(e);
                        }
                        fossilCode += ';';
                    case FFun(f):
                        fossilCode += "function " + field.name;
                        if (f.params != null && f.params.length > 0) {
                            fossilCode += "<";
                            fossilCode += [
                                for (param in f.params) {
                                    typeParamDeclToString(param);
                                }
                            ].join(",");
                            fossilCode += ">";
                        }
                        fossilCode += "(";
                        var firstArg = true;
                        for (arg in f.args) {
                            if (!firstArg) {
                                fossilCode += ', ';
                            }
                            firstArg = false;

                            if (arg.opt == true) {
                                fossilCode += '?';
                            }
                            fossilCode += arg.name;
                            if (arg.type != null) {
                                fossilCode += ':';
                                fossilCode += complexTypeToString(arg.type);
                            }
                            if (arg.value != null) {
                                fossilCode += " = " + toStringTabbed(arg.value);
                            }
                        }
                        fossilCode += ")";
                        if (f.ret != null) {
                            fossilCode += ':' + complexTypeToString(f.ret) + " ";
                        } 
                        if (f.expr != null) {
                            var funcExpToString = toStringTabbed(f.expr); 
                            fossilCode += " " + funcExpToString;
                            if (!funcExpToString.contains("\n") && !funcExpToString.endsWith(";"))
                                fossilCode += ";";
                        } else {
                            // I think this case would never happen from a Kiss file,
                            // but it's easy enough to handle.
                            fossilCode += ';';
                        }
                    case FProp(get, set, type, e):
                        fossilCode += "var " + field.name + "(" + get + "," + set + "):" + complexTypeToString(type);
                        if (e != null) {
                            fossilCode += " = " + toStringTabbed(e);
                        }
                        fossilCode += ";";
                    default:
                        fossilCode += '{Field type ${field.kind} not supported for fossilization}';
                }

                fossilCode += "\n";
            }

            var newFossilStart = haxeContentStart.lastIndexOf("}");
            var haxeContentEnd = haxeContentStart.substr(0, newFossilStart) + fossilStart + fossilCode + fossilEnd + haxeContentStart.substr(newFossilStart);
            File.saveContent(haxeFile + ".bak", haxeContent);
            File.saveContent(haxeFile, haxeContentEnd);
            return fields.concat([for (name => field in buildFieldNames) field]);
        }
    }

    static final SIGNIFICANT_AVERAGE_TIME = 0.1;
    static final SIGNIFICANT_TIME_SPENT = 1;
    // EGREGIOUS * SIGNIFICANT -> print in red
    static final EGREGIOUS = 15;

    public static function load(kissFile:String, k:KissState, ?loadingDirectory:String, loadAllExps = false, ?fromExp:ReaderExp, ?expectedError:EType):Null<ReaderExp> {
        if (loadingDirectory == null)
            loadingDirectory = k.loadingDirectory;

        var fullPath = if (Path.isAbsolute(kissFile)) {
            kissFile;
        } else {
            Path.join([loadingDirectory, kissFile]);
        };

        var module = Context.getLocalModule();
        if (module.length > 0)
            Context.registerModuleDependency(module, fullPath);

        var previousFile = k.file;
        var isNested = previousFile != null;
        k.file = fullPath;

        if (k.loadedFiles.exists(fullPath)) {
            return k.loadedFiles[fullPath];
        }
        var stream = try {
            Stream.fromFile(fullPath);
        } catch (m:Any) {
            var message =  'Kiss file not found: $kissFile';
            if (fromExp != null)
                throw KissError.fromExp(fromExp, message);
            Sys.println(message);
            Sys.exit(1);
            null;
        }
        var startPosition = stream.position();
        var loadedExps = [];
        Reader.readAndProcess(stream, k, (nextExp, str) -> {
            #if test
            Sys.println(str);
            #end

            // readerExpToHaxeExpr must be called to process readermacro, alias, and macro definitions
            macroUsed = false;
            var expr = _try(()->readerExpToHaxeExpr(nextExp, k), expectedError);

            // exps in the loaded file that actually become haxe expressions can be inserted into the
            // file that loaded them at the position (load) was called.
            // conditional compiler macros like (#when) tend to return empty blocks, or blocks containing empty blocks
            // when they contain field forms, so this should also be ignored

            // When calling from build(), we can't add all expressions to the (begin) returned by (load), because that will
            // cause double-evaluation of field forms
            if (loadAllExps) {
                loadedExps.push(nextExp);
            } else if (expr != null && !isEmpty(expr)) {
                // don't double-compile macros:
                if (macroUsed) {
                    loadedExps.push(RawHaxe(expr.toString()).withPosOf(nextExp));
                } else {
                    loadedExps.push(nextExp);
                }
            }
        }, isNested);

        var exp = if (loadedExps.length > 0) {
            CallExp(Symbol("begin").withPos(startPosition), loadedExps).withPos(startPosition);
        } else {
            null;
        }
        k.loadedFiles[fullPath] = exp;
        k.file = previousFile;
        return exp;
    }

    /**
     * Build macro: add fields to a Haxe class by compiling multiple Kiss files in order with the same KissState
     */
    public static function buildAll(kissFiles:Array<String>, ?k:KissState, useClassFields = true, ?context:FrontendContext):Array<Field> {
        if (k == null)
            k = defaultKissState(context);

        k.addContextFields(useClassFields);

        for (file in kissFiles) {
            build(file, k, false, context);
        }

        return k.fieldList;
    }

    static var macroUsed = false;
    static var expCache:HashMap<HashableString,String> = null;
    static var cacheFile = ".kissCache.json";
    static var cacheThreshold = 0.05;
    
    public static function readerExpToHaxeExpr(exp, k): Expr {
        return switch (macroExpandAndConvert(exp, k, false)) {
            case Right(expr): expr;
            case e: throw 'macroExpandAndConvert is broken: ${e}';
        };
    }

    public static function macroExpand(exp, k):ReaderExp {
        return switch (macroExpandAndConvert(exp, k, true)) {
            case Left(exp): exp;
            case e: throw 'macroExpandAndConvert is broken: ${e}';
        };
    }

    // Core functionality of Kiss: returns ReaderExp when macroExpandOnly is true, and haxe.macro.Expr otherwise
    public static function macroExpandAndConvert(exp:ReaderExp, k:KissState, macroExpandOnly:Bool, ?metaNames, ?metaParams:Array<Array<Expr>>, ?metaPos:Array<haxe.macro.Expr.Position>):Either<ReaderExp,Expr> {
        #if kissCache
        var str = Reader.toString(exp.def);
        if (!macroExpandOnly) {
            if (expCache == null) {
                var expCacheDynamic:haxe.DynamicAccess<String> = if (sys.FileSystem.exists(cacheFile)) {
                    haxe.Json.parse(File.getContent(cacheFile));
                } else {
                    {};
                }

                expCache = new HashMap();
                for (key => value in expCacheDynamic) {
                    expCache[Prelude.hashableString(key)] = value;
                }
            }

            if (expCache.exists(Prelude.hashableString(str))) {
                return Right(Context.parse(expCache[Prelude.hashableString(str)], Helpers.macroPos(exp)));
            }
        }
        #end

        if (k.conversionStack.length == 0) k.stateChanged = false;
        k.conversionStack.push(exp);

        var macros = k.macros;
        var fieldForms = k.fieldForms;
        var specialForms = k.specialForms;
        var specialFormMacroExpanders = k.specialFormMacroExpanders;
        var formDocs = k.formDocs;

        // Bind the table arguments of this function for easy recursive calling/passing
        var convert = macroExpandAndConvert.bind(_, k, macroExpandOnly);

        function left (c:Either<ReaderExp,Expr>) {
            return switch (c) {
                case Left(exp): exp;
                default: throw "macroExpandAndConvert is broken";
            };
        }

        function right (c:Either<ReaderExp,Expr>) {
            return switch (c) {
                case Right(exp): exp;
                default: throw "macroExpandAndConvert is broken";
            };
        }

        function leftForEach(convertedExps:Array<Either<ReaderExp,Expr>>) {
            return convertedExps.map(left);
        }

        function rightForEach(convertedExps:Array<Either<ReaderExp,Expr>>) {
            return convertedExps.map(right);
        }

        function checkNumArgs(form:String) {
            if (formDocs.exists(form)) {
                var docs = formDocs[form];
                // null docs can get passed around by renameAndDeprecate functions. a check here is more DRY
                if (docs != null)
                    exp.checkNumArgs(docs.minArgs, docs.maxArgs, docs.expectedForm);
            }
        }

        if (k.hscript)
            exp = Helpers.removeTypeAnnotations(exp);

        var none = EBlock([]).withMacroPosOf(exp);

        var startTime = haxe.Timer.stamp();
        var expr:Either<ReaderExp,Expr> = switch (exp.def) {
            case None:
                if (macroExpandOnly) Left(exp) else Right(none);
            case HaxeMeta(name, params, exp):
                if (macroExpandOnly) {
                    Left(HaxeMeta(name, params, left(macroExpandAndConvert(exp, k, true))).withPosOf(exp));
                } else {
                    if (metaNames == null) metaNames = [];
                    if (metaParams == null) metaParams = [];
                    if (metaPos == null) metaPos = [];
                    metaNames.push(name);
                    if (params == null)
                        metaParams.push(null);
                    else
                        metaParams.push([for (param in params) right(macroExpandAndConvert(param, k, false))]);
                    metaPos.push(Helpers.macroPos(exp));
                    Right(right(macroExpandAndConvert(exp, k, false, metaNames, metaParams, metaPos)));
                }
            case Symbol(alias) if (k.identAliases.exists(alias)):
                var substitution = k.identAliases[alias].withPosOf(exp);
                if (macroExpandOnly) Left(substitution) else macroExpandAndConvert(substitution, k, false);
            case Symbol(name) if (!macroExpandOnly):
                if (name.endsWith(",")) {
                    throw KissError.fromExp(exp, "trailing comma on symbol");
                }
                try {
                    Right(Context.parse(name, exp.macroPos()));
                } catch (err:haxe.Exception) {
                    throw KissError.fromExp(exp, "invalid symbol");
                };
            case StrExp(s) if (!macroExpandOnly):
                Right(EConst(CString(s)).withMacroPosOf(exp));
            case CallExp({pos: _, def: Symbol(ff)}, args) if (fieldForms.exists(ff) && !macroExpandOnly):
                checkNumArgs(ff);
                var field = fieldForms[ff](exp, args.copy(), k);
                if (metaNames != null && metaNames.length > 0) {
                    field.meta = [];
                    while (metaNames.length > 0) {
                        field.meta.push({
                            name: metaNames.shift(),
                            params: metaParams.shift(),
                            pos: metaPos.shift()
                        });
                    }
                }
                k.fieldList.push(field);
                k.fieldDict[field.name] = field;
                k.stateChanged = true;
                Right(none); // Field forms are no-ops
            case CallExp({pos: _, def: Symbol(mac)}, args) if (macros.exists(mac)):
                checkNumArgs(mac);
                macroUsed = true;
                var expanded =
                    #if !macrotest
                    try {
                    #end
                        Kiss.measure(mac, ()->macros[mac](exp, args.copy(), k), true);
                    #if !macrotest
                    } catch (err:UnmatchedBracketSignal) {
                        throw err;
                    } catch (error:KissError) {
                        throw error;
                    } catch (error:Dynamic) {
                        throw KissError.fromExp(exp, 'Macro expansion error: $error');
                    };
                    #end
                    if (expanded != null) {
                        convert(expanded);
                    } else if (macroExpandOnly) {
                        Left(None.withPosOf(exp));
                    } else{
                        Right(none);
                    };
            case CallExp({pos: _, def: Symbol(specialForm)}, args) if (specialForms.exists(specialForm) && !macroExpandOnly):
                checkNumArgs(specialForm);
                Right(Kiss.measure(specialForm, ()->specialForms[specialForm](exp, args.copy(), k), true));
            case CallExp({pos: _, def: Symbol(specialForm)}, args) if (specialFormMacroExpanders.exists(specialForm) && macroExpandOnly):
                checkNumArgs(specialForm);
                Left(specialFormMacroExpanders[specialForm](exp, args.copy(), k));
            case CallExp({pos: _, def: Symbol(alias)}, args) if (k.callAliases.exists(alias)):
                convert(CallExp(k.callAliases[alias].withPosOf(exp), args).withPosOf(exp));
            case CallExp(func, args):
                var convertedArgs = [for (argExp in args) convert(argExp)];
                if (macroExpandOnly) {
                    var convertedArgs = leftForEach(convertedArgs);
                    Left(CallExp(func, convertedArgs).withPosOf(exp));
                }
                else {
                    var convertedArgs = rightForEach(convertedArgs);
                    Right(ECall(right(convert(func)), convertedArgs).withMacroPosOf(exp));
                }

            case ListExp(elements):
                var isMap = false;
                var convertedElements = [
                    for (elementExp in elements) {
                        switch (elementExp.def) {
                            case KeyValueExp(_, _):
                                isMap = true;
                            default:
                        }
                        convert(elementExp);
                    }
                ];
                if (macroExpandOnly)
                    Left(ListExp(leftForEach(convertedElements)).withPosOf(exp));
                else {
                    var arrayDecl = EArrayDecl(rightForEach(convertedElements)).withMacroPosOf(exp);
                    Right(if (!isMap && k.wrapListExps && !k.hscript) {
                        ENew({
                            pack: ["kiss"],
                            name: "List"
                        }, [arrayDecl]).withMacroPosOf(exp);
                    } else {
                        arrayDecl;
                    });
                }
            case RawHaxe(code) if (!macroExpandOnly):
                try {
                    Right(Context.parse(code, exp.macroPos()));
                } catch (err:Exception) {
                    throw KissError.fromExp(exp, 'Haxe parse error: $err');
                };
            case RawHaxeBlock(code) if (!macroExpandOnly):
                try {
                    Right(Context.parse('{$code}', exp.macroPos()));
                } catch (err:Exception) {
                    throw KissError.fromExp(exp, 'Haxe parse error: $err');
                };
            case FieldExp(field, innerExp, safe):
                var convertedInnerExp = convert(innerExp);
                if (macroExpandOnly)
                    Left(FieldExp(field, left(convertedInnerExp), safe).withPosOf(exp));
                else
                    Right(EField(right(convertedInnerExp), field, if (safe) Safe else Normal).withMacroPosOf(exp));
            case KeyValueExp(keyExp, valueExp) if (!macroExpandOnly):
                Right(EBinop(OpArrow, right(convert(keyExp)), right(convert(valueExp))).withMacroPosOf(exp));
            case Quasiquote(innerExp) if (!macroExpandOnly):
                // This statement actually turns into an HScript expression before running
                Right(macro {
                    Helpers.evalUnquotes($v{innerExp});
                });
            default:
                if (macroExpandOnly)
                    Left(exp);
                else
                    throw KissError.fromExp(exp, 'conversion not implemented');
        };
        var conversionTime = haxe.Timer.stamp() - startTime;
        k.conversionStack.pop();
        #if kissCache
        if (!macroExpandOnly) {
            if (conversionTime > cacheThreshold && !k.stateChanged) {
                expCache[Prelude.hashableString(str)] = switch (expr) {
                    case Right(expr): expr.toString();
                    default: throw "macroExpandAndConvert is broken";
                }
            }
        }
        #end
        if (metaNames != null && metaNames.length > 0 && !macroExpandOnly) {
            expr = Right(EMeta({
                            name: metaNames.pop(),
                            params: metaParams.pop(),
                            pos: metaPos.pop()
                        }, right(expr)).withMacroPosOf(exp));
        }
        return expr;
    }

    public static function addVarInScope(k: KissState, v:Var, local:Bool, isStatic:Bool=false) {
        if (v.type != null)
            k.typeHints.push(v);
        k.varsInScope.push(v);
        k.varsInScopeAreStatic.push(isStatic);
        if (local)
            k.localVarsInScope.push(v);
    }

    public static function removeVarInScope(k: KissState, v:Var, local:Bool) {
        function removeLast(list:Array<Var>, v:Var) {
            var index = list.lastIndexOf(v);
            list.splice(index, 1);
            return index;
        }
        if (v.type != null)
            removeLast(k.typeHints, v);
        var idx = removeLast(k.varsInScope, v);
        k.varsInScopeAreStatic.splice(idx, 1);
        if (local)
            removeLast(k.localVarsInScope, v);
    }

    static function disableMacro(copy:KissState, m:String, reason:String) {
        copy.macros[m] = (wholeExp:ReaderExp, exps, k) -> {
            var b = wholeExp.expBuilder();
            // have this throw during macroEXPANSION, not before (so assertThrows will catch it)
            b.throwKissError('$m is unavailable in macros because $reason');
        };
    }

    // This doesn't clone k because k might be modified in important ways :(
    public static function forStaticFunction(k:KissState, inStaticFunction:Bool) {
        k.inStaticFunction = inStaticFunction;
        return k;
    }

    // Return an identical Kiss State, but without type annotations or wrapping list expressions as kiss.List constructor calls.
    public static function forHScript(k:KissState):KissState {
        var copy = new Cloner().clone(k);
        copy.hscript = true;

        // disallow macros that will error when run in hscript:
        disableMacro(copy, "ifLet", "hscript doesn't support pattern-matching");
        disableMacro(copy, "whenLet", "hscript doesn't support pattern-matching");
        disableMacro(copy, "unlessLet", "hscript doesn't support pattern-matching");

        copy.macros["cast"] = (wholeExp:ReaderExp, exps, k) -> {
            exps[0];
        };

        return copy;
    }

    public static function forMacroEval(k:KissState): KissState {
        var copy = k.forHScript();
        // Catch accidental misuse of (set) on macroVars
        var setLocal = copy.specialForms["set"];
        copy.specialForms["set"] = (wholeExp:ReaderExp, exps, k:KissState) -> {
            switch (exps[0].def) {
                case Symbol(varName) if (k.macroVars.exists(varName)):
                    var b = wholeExp.expBuilder();
                    // have this throw during macroEXPANSION, not before (so assertThrows will catch it)
                    copy.convert(b.throwKissError('If you intend to change macroVar $varName, use setMacroVar instead. If not, rename your local variable for clarity.'));
                default:
                    setLocal(wholeExp, exps, copy);
            };
        };

        copy.macros["expect"] = (wholeExp:ReaderExp, exps:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(3, null, "(expect <stream> <description> <stream method> <args...>)");
            var b = wholeExp.expBuilder();
            var streamSymbol = exps.shift();
            b.callField("expect", streamSymbol, [exps.shift(), b.callSymbol("lambda", [b.list([]), b.callField(Prelude.symbolNameValue(exps.shift()), streamSymbol, exps)])]);
        };

        // TODO should this also be in forHScript()?
        // In macro evaluation,
        copy.macros.remove("eval");
        // BECAUSE it is provided as a function instead.

        return copy;
    }

    // Return an identical Kiss State, but without wrapping list expressions as kiss.List constructor calls.
    public static function withoutListWrapping(k:KissState) {
        var copy = new Cloner().clone(k);
        copy.wrapListExps = false;
        return copy;
    }

    // Return an identical Kiss State, but prepared for parsing a branch pattern of a (case...) expression
    public static function forCaseParsing(k:KissState):KissState {
        var copy = withoutListWrapping(k);
        copy.macros.remove("or");
        copy.specialForms["or"] = SpecialForms.caseOr;
        copy.specialForms["as"] = SpecialForms.caseAs;
        return copy;
    }

    public static function convert(k:KissState, exp:ReaderExp) {
        return readerExpToHaxeExpr(exp, k);
    }

    public static function localVarWarning(k:KissState) {
        if (k.localVarCalls.length > 0 && k.printFieldsCalls.length > 0) {
            for (call in k.localVarCalls) {
                KissError.warnFromExp(call, 'variables declared with with `localVar` are incompatible with printAll macros. Use `let` instead.');
            }
            k.localVarCalls = [];
        }
    }

    static var profileAggregates:Map<String,Float> = [];
    static var profileUsageCounts:Map<String,Int> = [];

    public static function measure<T>(processLabel:String,  process:Void->T, aggregate=false) {
        var start = Sys.time();
        if (aggregate) {
            if (!profileAggregates.exists(processLabel)) {
                profileAggregates[processLabel] = 0.0;
                profileUsageCounts[processLabel] = 0;
            }
        } else {
            Sys.print('${processLabel}... ');
        }
        var result = process();
        var end = Sys.time();
        if (aggregate) {
            profileAggregates[processLabel] += (end - start);
            profileUsageCounts[processLabel] += 1;
        } else {
            Sys.println('${end-start}s');
        }
        return result;
    }

    public static function isEmpty(expr:Expr) {
        switch (expr.expr) {
            case EBlock([]):
            case EBlock(blockExps):
                for (exp in blockExps) {
                    if (!isEmpty(exp))
                        return false;
                }
            default:
                return false;
        }
        return true;
    }

    #end
}
