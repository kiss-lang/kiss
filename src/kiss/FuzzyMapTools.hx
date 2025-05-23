package kiss;

import haxe.Json;
import haxe.ds.StringMap;
using hx.strings.Strings;
import kiss.Prelude;

typedef MapInfo = {
    file:String,
    matches:Map<String,Dynamic>
};

enum FuzzyGetResult<T> {
    Found(realKey:String, value:T, score:Float);
    NotFound;
}

class FuzzyMapTools {
    static var serializingMaps = new Map<StringMap<Dynamic>, MapInfo>();

    @:allow(kiss.FuzzyMap)
    static var fuzzyMaps:Map<FuzzyMap<Dynamic>,Bool> = [];

    public static function isFuzzy(map:Map<String,Dynamic>) {
        return fuzzyMaps.exists(map);
    }

    /**
    * FuzzyMap is highly inefficient, so you may wish to memoize the matches that it makes before
    * releasing your project. FuzzyMapTools.serializeMatches() helps with this
    */
    public static function serializeMatches(m:StringMap<Dynamic>, file:String) {
        serializingMaps[m] = { file: file, matches: new Map() };
    }

    public static function fuzzyMatchScore(key:String, fuzzySearchKey:String) {
        return 1 - (key.toLowerCase().getLevenshteinDistance(fuzzySearchKey.toLowerCase()) / Math.max(key.length, fuzzySearchKey.length));
    }

    static var threshold = 0.4;

    public static function bestMatch<T>(map:FuzzyMap<T>, fuzzySearchKey:String, ?throwIfNone=true):String {
        if (map.existsExactly(fuzzySearchKey)) return fuzzySearchKey;

        var bestScore = 0.0;
        var bestKey = null;

        for (key in map.keys()) {
            var score = fuzzyMatchScore(key, fuzzySearchKey);
            if (score > bestScore) {
                bestScore = score;
                bestKey = key;
            }
        }

        if (bestScore < threshold) {
            if (throwIfNone)
                throw 'No good match for $fuzzySearchKey in $map -- best was $bestKey with $bestScore';
            else
                return null;
        }

        #if (test || debug)
        if (bestScore != 1)
            Prelude.print('Fuzzy match $bestKey for $fuzzySearchKey score: $bestScore');
        #end
        
        return bestKey;
    }

    public static function fuzzyGet<T>(map:FuzzyMap<T>, fuzzySearchKey:String): FuzzyGetResult<T> {
        return switch (bestMatch(map, fuzzySearchKey, false)) {
            case null:
                NotFound;
            case key:
                Found(key, map[key], fuzzyMatchScore(key, fuzzySearchKey));
        };
    }

    @:allow(kiss.FuzzyMap)
    static function onMatchMade(m:StringMap<Dynamic>, key:String, value:Dynamic) {
        #if ((sys || hxnodejs) && !frontend)
        if (serializingMaps.exists(m)) {
            var info = serializingMaps[m];
            info.matches[key] = value;
            sys.io.File.saveContent(info.file, Json.stringify(info.matches));
        }
        #end
    }

    public static function loadMatches(m:StringMap<Dynamic>, json:String) {
        var savedMatches:haxe.DynamicAccess<Dynamic> = Json.parse(json);
        for (key => value in savedMatches.keyValueIterator()) {
            m.set(key, value);
        }
    }
}