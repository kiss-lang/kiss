package kiss;

#if macro
import kiss.Kiss;
import kiss.Prelude;
import sys.FileSystem;
import haxe.macro.Expr;

typedef CachedFile = {
    path:String,
    loadedFiles:Array<String>,
    timeLastCompiled:Date,
    compiledState:KissState,
    compiledCode:Null<ReaderExp>
};

@:allow(kiss.Kiss)
class KissCache {
    var cachedFiles:Map<String,CachedFile> = [];
    var cachedExps:Map<String,Expr> = [];

    function new() {}

    function needsRecompile(file:String) {
        var cachedFile = cachedFiles[file];
        var latestModifiedTime = Prelude._max([
            for (file in [file].concat(cachedFile.loadedFiles)) {
                FileSystem.stat(file).mtime.getTime();
            }
        ]);
        return latestModifiedTime > cachedFile.timeLastCompiled.getTime();
    }
}

#end