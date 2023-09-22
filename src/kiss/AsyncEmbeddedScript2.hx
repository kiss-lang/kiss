package kiss;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.PositionTools;
import sys.io.File;
import haxe.io.Path;
using haxe.io.Path;
import kiss.Helpers;
using kiss.Helpers;
using tink.MacroApi;

#end

import haxe.CallStack;
import kiss.Kiss;
using kiss.Kiss;
import kiss.ReaderExp;
import kiss.Prelude;
import kiss.cloner.Cloner;
using StringTools;
import hscript.Parser;
import hscript.Interp;

typedef Continuation2 = () -> Void;
// (this, skipping, cc) -> Void
typedef AsyncCommand2 = (AsyncEmbeddedScript2, Bool, Continuation2) -> Void;

class ObjectInterp2<T> extends Interp {
    var obj:T;
    var fields:Map<String,Bool> = []; 
    public function new(obj:T) {
        this.obj = obj;
        
        for (field in Type.getInstanceFields(Type.getClass(obj))) {
            fields[field] = true;
        }

        super();
    }

    override function resolve(id:String):Dynamic {
        var fieldVal = Reflect.field(obj, id);
        if (fieldVal != null)
            return fieldVal;
        else
            return super.resolve(id);
    }

    // TODO every method of setting variables should try to set them on the object,
    // but there are a lot of them and I might have missed some.

    override function setVar(name:String, v:Dynamic) {
        if (Reflect.field(obj, name) != null) {
            Reflect.setField(obj, name, v);
        } else {
            super.setVar(name, v);
        }
    }
 
	public override function expr( e : hscript.Expr ) : Dynamic {
        var curExpr = e;
        #if hscriptPos
		var e = e.e;
		#end
        switch( e ) {
            // Handle fuzzyMaps correctly:
            case EArray(e, index):
                var arr:Dynamic = expr(e);
                var index:Dynamic = expr(index);
                if (isMap(arr)) {
                    if (kiss.FuzzyMapTools.isFuzzy(arr))
                        return getMapValue(arr, kiss.FuzzyMapTools.bestMatch(arr, index));
                    return getMapValue(arr, index);
                }
                else {
                    return arr[index];
                }
            case ECall(e,params):
                switch( hscript.Tools.expr(e) ) {
                    case EIdent(name) if (fields.exists(name)):
                        var args = new Array();
                        for( p in params )
                            args.push(expr(p));
                        return call(obj,expr(e),args);
                    default:
                }
            default:
        }
        return super.expr(curExpr);
    }
}

/**
    Utility class for making statically typed, debuggable, ASYNC-BASED embedded Kiss-based DSLs.
    Examples are in the hollywoo project.
**/
class AsyncEmbeddedScript2 {
    private var instructions:Array<AsyncCommand2> = null;
    private var breakPoints:Map<Int, () -> Bool> = [];
    private var onBreak:AsyncCommand2 = null;
    public var lastInstructionPointer(default,null):Int = -1;
    private var labels:Map<String,Int> = [];
    private var noSkipInstructions:Map<Int,Bool> = [];
    
    private var parser = new Parser();
    private var interp:ObjectInterp2<AsyncEmbeddedScript2>;
    public var interpVariables(get, null):Map<String,Dynamic>;
    private function get_interpVariables() {
        return interp.variables;
    }

    private var hscriptInstructions:Map<Int,String> = [];    
    private function hscriptInstructionFile() return "";

    public function setBreakHandler(handler:AsyncCommand2) {
        onBreak = handler;
    }

    public function addBreakPoint(instruction:Int, ?condition:() -> Bool) {
        if (condition == null) {
            condition = () -> true;
        }
        breakPoints[instruction] = condition;
    }

    public function removeBreakPoint(instruction:Int) {
        breakPoints.remove(instruction);
    }

    public function new() {
        interp = new ObjectInterp2(this);
        kiss.KissInterp.prepare(interp);
        if (hscriptInstructionFile().length > 0) {
            #if (sys || hxnodejs)
            var cacheJson:haxe.DynamicAccess<String> = haxe.Json.parse(sys.io.File.getContent(hscriptInstructionFile()));
            for (key => value in cacheJson) {
                hscriptInstructions[Std.parseInt(key)] = value;
            }
            #end
        }
    }

    private function resetInstructions() {}

    public function instructionCount() { 
        if (instructions == null)
            resetInstructions();
        return instructions.length;
    }

    #if test
    public var ranHscriptInstruction = false;
    #end
    private function runHscriptInstruction(instructionPointer:Int, skipping:Bool, cc:Continuation2) {
        #if test
        ranHscriptInstruction = true;
        #end
        interp.variables['skipping'] = skipping;
        interp.variables['cc'] = cc;
        if (printCurrentInstruction)
            Prelude.print(hscriptInstructions[instructionPointer]);
        interp.execute(parser.parseString(hscriptInstructions[instructionPointer]));
    }

    public var skipTarget(default, null):Null<Int> = null;

    public var running(default, null):Bool = false;
    
    // There are two ways to keep the callstack unwound. The default is to use haxe.Timer.delay,
    // which is automatic, but might introduce frame-skippy behaviors. The alternative is to
    // set unwindWithTimerDelay to false, and use your own event loop to call ccToCall whenever
    // it is non-null at the desired point in your update logic. Calling ccToCall will clear ccToCall.
    public var unwindWithTimerDelay(default, default) = true;
    public var ccToCall(default, null): Continuation2 = null;

    public var onSkipStart(default, null):Continuation2 = null;
    public var onSkipEnd(default, null):Continuation2 = null;
        
    // When skipping, you might end up with hundreds of instructions running in a single frame.
    // This flag forces the skipped instructions to run one-per-frame so your program doesn't hang.
    public var skipAsync(default, null):Bool = false;

    private function runInstruction(instructionPointer:Int, withBreakPoints = true):Void {
        var wasRunning = running;
        running = true;
        var skipping = false;
        if (skipTarget != null) {
            if (instructionPointer == skipTarget) {
                skipTarget = null;
                lastLabel = potentialLastLabel;
                if (onCommitLabel != null) {
                    onCommitLabel(potentialLastLabel);
                }
                if (onSkipEnd != null) {
                    onSkipEnd();
                }
            }
            else {
                if (!wasRunning && onSkipStart != null) {
                    onSkipStart();
                }
                skipping = true;
            }
        }
        
        lastInstructionPointer = instructionPointer;
        if (instructions == null)
            resetInstructions();
        if (withBreakPoints && breakPoints.exists(instructionPointer) && breakPoints[instructionPointer]()) {
            if (onBreak != null) {
                onBreak(this, false, () -> runInstruction(instructionPointer, false));
            }
        }
        var tryCallNextWithTailRecursion = false;
        var nextCalledWithTailRecursion = false;
        var continuation = if (instructionPointer < instructions.length - 1) {
            () -> {
                // runInstruction may be called externally to skip through the script.
                // When this happens, make sure other scheduled continuations are canceled
                // by verifying that lastInstructionPointer hasn't changed
                if (lastInstructionPointer == instructionPointer) {
                    if (!skipping || !skipAsync)
                        tryCallNextWithTailRecursion = true;
                    if (unwindWithTimerDelay) {
                        haxe.Timer.delay(()->{
                            if (!nextCalledWithTailRecursion)
                                runInstruction(instructionPointer + 1, withBreakPoints);
                        }, 0);
                    } else {
                        ccToCall = ()->{
                            ccToCall = null;
                            runInstruction(instructionPointer + 1, withBreakPoints);
                        };
                    }
                }
                return;
            };
        } else {
            () -> {};
        }

        runWithErrorChecking(() -> {
            if (hscriptInstructions.exists(instructionPointer)) {
                runHscriptInstruction(instructionPointer, skipping, continuation);
            } else {
                instructions[instructionPointer](this, skipping, continuation);
            }
        });

        if (tryCallNextWithTailRecursion) {
            nextCalledWithTailRecursion = true;
            ccToCall = null;
            runInstruction(instructionPointer + 1, withBreakPoints);
        }
    }

    public function run(withBreakPoints = true) {
        runInstruction(0, withBreakPoints);
    }

    public function runFromInstruction(ip:Int, withBreakpoints = true) {
        skipTarget = ip;
        runInstruction(0, withBreakpoints);
    }

    public function runFromLabel(label:String) {
        runFromInstruction(labels[label]);
    }

    public function runFromNextLabel(newScript:AsyncEmbeddedScript2, withBreakpoints = true) {
        var labelPointers = [for (ip in labels) ip];
        labelPointers.sort(Reflect.compare);
        for (ip in labelPointers) {
            if (ip > lastInstructionPointer) {
                newScript.runFromInstruction(ip);
                break;
            }
        }
    }

    public var lastLabel(default, null):String = "";
    private var potentialLastLabel:String = "";
    
    // Will be called EVERY time a label is reached, even if skipping past it:
    public var onLabel:String->Void;
    // Will be called when labels are reached without skipping, AND on the last label skipped when skipping ends
    public var onCommitLabel:String->Void;

    public function labelRunners(withBreakpoints = true):Map<String,AsyncEmbeddedScript2->Void> {
        if (instructions == null)
            resetInstructions();
        return [for (label => ip in labels) label => (newScript:AsyncEmbeddedScript2) -> newScript.runFromInstruction(ip, withBreakpoints)];
    }

    public var printCurrentInstruction = true;

    public function runWithErrorChecking(process:Void->Void) {
        try {
            process();
        } catch (e:haxe.Exception) {
            Prelude.print("ERROR STACK:");
            logStack(e.stack);
            Prelude.print("ERROR MESSAGE:");
            Prelude.printStr(e.message);
            if (onError != null) {
                onError(e);
            }
            #if (sys || hxnodejs)
            Sys.exit(1);
            #end
            throw e;
        }
    }

    function logStack(c:CallStack):Void {
        var lastFilePos = "";
        var lastS:StackItem = null;
        var consecutiveCalls = 0;
        var nextFrame = null;

        for (idx in 0... c.length) {
            switch (nextFrame = c.get(idx)) {
                case null:
                    break;
                case FilePos(s, file, line, column):
                    var filePos = '${file}:${line}';
                    if (column != null) filePos += ':${column}';

                    if (filePos == lastFilePos) {
                        ++consecutiveCalls;
                    } else {
                        if (lastFilePos.length > 0) {
                            var line = '${lastS} at ${lastFilePos}';
                            if (consecutiveCalls > 1) {
                                line += ' x${consecutiveCalls}';
                            }
                            Prelude.print(line);
                        }
                        consecutiveCalls = 1;
                    }
                    lastFilePos = filePos;
                    lastS = s;
                default:
                    Prelude.print(nextFrame);
            }
        }
        if (lastFilePos.length > 0) {
            var line = '${lastS} at ${lastFilePos}';
            if (consecutiveCalls > 1) {
                line += ' x${consecutiveCalls}';
            }
            Prelude.print(line);
        }
    }

    public var onError:Any->Void;

    #if macro
    public static function build(dslHaxelib:String, dslFile:String, scriptFile:String):Array<Field> {
        // trace('AsyncEmbeddedScript.build $dslHaxelib $dslFile $scriptFile');
        var k = Kiss.defaultKissState();

        k.file = scriptFile;
        var classPath = Context.getPosInfos(Context.currentPos()).file;
        var loadingDirectory = Path.directory(classPath);
        var classFields = []; // Kiss.build() will already include Context.getBuildFields()

        var hscriptInstructions:Map<String,String> = [];
        var cache:Map<String,String> = [];
        #if kissCache
        var cacheFile = scriptFile.withoutExtension().withoutDirectory() + ".cache.json";
        if (sys.FileSystem.exists(cacheFile)) {
            var cacheJson:haxe.DynamicAccess<String> = haxe.Json.parse(sys.io.File.getContent(cacheFile));
            for (key => value in cacheJson)
                cache[key] = value;
        }
        #end

        var hscriptInstructionFile = scriptFile.withoutExtension().withoutDirectory() + ".hscript.json";

        var commandList:Array<Expr> = [];
        var labelsList:Array<Expr> = [];
        var noSkipList:Array<Expr> = [];

        var labelNum = 0;
        k.macros["label"] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> {
            wholeExp.checkNumArgs(1, 1, '(label <labelSymbol for debug-only or "label string" for release>)');
            switch (args[0].def) {
                // Unless it's a debug build, ignore symbol labels
                #if !debug
                case Symbol(label):
                    wholeExp.expBuilder().callSymbol("cc", []);
                #end
                case Symbol(label) | StrExp(label):
                    k.stateChanged = true;
                
                    label = '${++labelNum}. '.lpad("0", 5) + label;
                    labelsList.push(macro labels[$v{label}] = $v{commandList.length});
                    
                    var b = wholeExp.expBuilder();
                    
                    b.begin([
                        b._if(b.symbol("skipping"),
                                b.set(b.symbol("potentialLastLabel"), b.str(label)),
                            b.begin([
                                b.callSymbol("when", [b.symbol("onCommitLabel"), b.callSymbol("onCommitLabel", [b.str(label)])]),
                                b.set(b.symbol("lastLabel"), b.str(label))
                            ])),
                        b.callSymbol("when", [b.symbol("onLabel"), b.callSymbol("onLabel", [b.str(label)])]),
                        b.callSymbol("cc", [])
                    ]);
                default:
                    throw KissError.fromExp(wholeExp, "bad (label) statement");
            }
        };

        // Or if you're subclassing this before implementing your script, add this macro to the subclass dsl:
        //  (defMacro makeCC [&body b]
        //      `->:Void [] (runWithErrorChecking ->:Void {,@b}))

        k.macros["makeCC"] = (wholeExp:ReaderExp, args:Array<ReaderExp>, k:KissState) -> {
            var b = wholeExp.expBuilder();
            b.callSymbol("lambda", [b.list([]),
                b.callSymbol("runWithErrorChecking", [
                    b.callSymbol("lambda", [b.list([])].concat(args))
                ])]);
        };

        if (dslHaxelib.length > 0) {
            dslFile = Path.join([Helpers.libPath(dslHaxelib), dslFile]);
        }

        // This brings in the DSL's functions and global variables.
        // As a side-effect, it also fills the KissState with the macros and reader macros that make the DSL syntax
        classFields = classFields.concat(Kiss.build(dslFile, k));

        if (Lambda.count(cache) > 0) {
            classFields.push({
                name: "hscriptInstructionFile",
                access: [AOverride],
                pos: Context.currentPos(),
                kind: FFun({
                    args: [],
                    expr: macro return $v{hscriptInstructionFile}
                })
            });
        }

        scriptFile = Path.join([loadingDirectory, scriptFile]);
        
        Context.registerModuleDependency(Context.getLocalModule(), scriptFile);
        k.fieldList = [];
        Kiss._try(() -> {
            #if profileKiss
            Kiss.measure('Compiling kiss: $scriptFile', () -> {
            #end
                function process(nextExp) {
                    #if kissCache
                    var cacheKey = Reader.toString(nextExp.def);
                    if (cache.exists(cacheKey)) {
                        hscriptInstructions[Std.string(commandList.length)] = cache[cacheKey];
                        commandList.push(macro null);
                        return;
                    }
                    #end

                    nextExp = Kiss.macroExpand(nextExp, k);
                    var stateChanged = k.stateChanged;
                    
                    // Allow packing multiple commands into one exp with a (commands <...>) statement
                    switch (nextExp.def) {
                        case CallExp({pos: _, def: Symbol("commands")}, 
                        commands):
                            for (exp in commands) {
                                process(exp);
                            }
                            return;
                        default:
                    }
                    
                    var exprString = Reader.toString(nextExp.def);
                    var fieldCount = k.fieldList.length;
                    var expr = Kiss.readerExpToHaxeExpr(nextExp, k);
                    if (expr == null || Kiss.isEmpty(expr))
                        return;
                    expr = macro { if (printCurrentInstruction) Prelude.print($v{exprString}); $expr; };
                    expr = expr.expr.withMacroPosOf(nextExp);
                    if (expr != null) {
                        var c = macro function(self, skipping, cc) {
                            $expr;
                        };
                        // If the expression didn't change the KissState when macroExpanding, it can be cached
                        #if kissCache
                        if (!stateChanged) {
                            var expr = Kiss.readerExpToHaxeExpr(nextExp, k.forHScript());
                            cache[cacheKey] = expr.toString();
                        }
                        #end

                        commandList.push(c.expr.withMacroPosOf(nextExp));
                    }

                    // This return is essential for type unification of concat() and push() above... ugh.
                    return;
                }
                Reader.readAndProcess(Stream.fromFile(scriptFile), k, process);
                null;
            #if profileKiss
            });
            #end
        });

        classFields = classFields.concat(k.fieldList);

        classFields.push({
            pos: PositionTools.make({
                min: 0,
                max: File.getContent(scriptFile).length,
                file: scriptFile
            }),
            name: "resetInstructions",
            access: [APrivate, AOverride],
            kind: FFun({
                ret: null,
                args: [],
                expr: macro {
                    this.instructions = [$a{commandList}];
                    $b{labelsList};
                    $b{noSkipList};
                }
            })
        });

        #if kissCache
        sys.io.File.saveContent(cacheFile, haxe.Json.stringify(cache));
        sys.io.File.saveContent(hscriptInstructionFile, haxe.Json.stringify(hscriptInstructions));
        #end

        return classFields;
    }
    #end
}
