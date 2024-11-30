package kiss;

import hscript.Parser;
import hscript.Interp;
import hscript.Expr;
import kiss.Prelude;

using  hscript.Tools;

typedef InterpMap = haxe.ds.StringMap<Dynamic>;

/**
 * Specialized hscript interpreter for hscript generated from Kiss expressions.
 * When macrotest is defined by the compiler, many functions run without
 * try/catch statements that are required for correct behavior -- this
 * is actually helpful sometimes because it preserves callstacks from errors in
 * macro definitions.
 */
class KissInterp extends Interp {
    var nullForUnknownVar:Bool;
    var parser = new Parser();

    public static function prepare(interp:Interp) {
        interp.variables.set("Reflect", Reflect);
        interp.variables.set("Type", Type);
        interp.variables.set("Prelude", Prelude);
        interp.variables.set("Lambda", Lambda);
        interp.variables.set("Std", Std);
        interp.variables.set("Keep", ExtraElementHandling.Keep);
        interp.variables.set("Drop", ExtraElementHandling.Drop);
        interp.variables.set("Throw", ExtraElementHandling.Throw);
        interp.variables.set("Math", Math);
        interp.variables.set("Json", haxe.Json);
        interp.variables.set("StringMap", InterpMap);
        interp.variables.set("FuzzyMapTools", FuzzyMapTools);
        interp.variables.set("StringTools", StringTools);
        interp.variables.set("Path", haxe.io.Path);
        #if ((sys || hxnodejs) && !frontend)
        interp.variables.set("Sys", Sys);
        interp.variables.set("FileSystem", sys.FileSystem);
        interp.variables.set("File", sys.io.File);
        #end
        #if (sys && !cs)
        interp.variables.set("Http", sys.Http);
        #end
    }

    public function new(nullForUnknownVar = false) {
        super();

        this.nullForUnknownVar = nullForUnknownVar;
        prepare(this);

        #if macro
        variables.set("KissError", kiss.KissError);
        variables.set("Reader", kiss.Reader);
        #end

        // Might eventually need to simulate types in the namespace:
        variables.set("kiss", {});

        variables.set("dumpVars", dumpVars);
    }

    public var cacheConvertedHScript = false;

    public function evalKiss(kissStr:String):Dynamic {
        #if !((sys || hxnodejs) && !frontend)
        if (cacheConvertedHScript) {
            throw "Cannot used cacheConvertedHScript on a non-sys target";
        }
        #end

        var convert =
            #if ((sys || hxnodejs) && !frontend)
            if (cacheConvertedHScript) {
                Prelude.cachedConvertToHScript;
            } else
            #end
                Prelude.convertToHScript;
        return evalHaxe(convert(kissStr));
    }

    public function evalHaxe(hscriptStr:String):Dynamic {
        return execute(parser.parseString(hscriptStr));
    }

    // In some contexts, undefined variables should just return "null" as a falsy value
    override function resolve(id:String):Dynamic {
        if (nullForUnknownVar) {
            return try {
                super.resolve(id);
            } catch (e:Dynamic) {
                null;
            }
        } else {
            return super.resolve(id);
        }
    }

    override function exprReturn(e):Dynamic {
        // the default exprReturn() contains a try-catch which, though it is important (break, continue, and return statements require it), hides very important macroexpansion callstacks sometimes
        #if macrotest
        return expr(e);
        #else
        return super.exprReturn(e);
        #end
    }

    #if macrotest
    override function forLoop(n, it, e) {
        var old = declared.length;
        declared.push({n: n, old: locals.get(n)});
        var it = makeIterator(expr(it));
        while (it.hasNext()) {
            locals.set(n, {r: it.next()});
            // try {
            expr(e);
            /*} catch( err : Stop ) {
                switch( err ) {
                case SContinue:
                case SBreak: break;
                case SReturn: throw err;
                }
            }*/
        }
        restore(old);
    }
    #end
    
    public function publicExprReturn(e) {
        return exprReturn(e);
    }

    public function getLocals() {
        return locals;
    }

    public function setLocals(l) {
        locals = l;
    }

    public function dumpVars(file="KissInterpVars.txt", truncateLongVars=0) {
        var varDump = "LOCALS\n";
        varDump    += "======\n";
        for (key => value in locals) {
            varDump += '$key: $value\n'; 
        }
        varDump    += "GLOBALS\n";
        varDump    += "=======\n";
        for (key => value in variables) {
            varDump += '$key: $value\n'; 
        }

        if (truncateLongVars > 0) {
            varDump = [for (line in varDump.split("\n")) line.substr(0, truncateLongVars + line.indexOf(":") + 1)].join("\n");
        }

        kiss.Prelude.print(varDump);
        #if ((sys || hxnodejs) && !frontend)
        sys.io.File.saveContent(file, varDump);
        #end
    }

}
