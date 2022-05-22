package kiss;

import haxe.ds.StringMap;

using hx.strings.Strings;

@:forward(clear, copy, iterator, keyValueIterator, keys, toString)
abstract FuzzyMap<T>(StringMap<T>) from StringMap<T> to StringMap<T> {
    public inline function new(?m:StringMap<T>) {
        this = if (m != null) m else new StringMap<T>();
    }

    @:from
    static public function fromMap<T>(m:StringMap<T>) {
        return new FuzzyMap<T>(m);
    }

    @:to
    public function toMap() {
        return this;
    }

    static var threshold = 0.4;
    public static function fuzzyMatchScore(key:String, fuzzySearchKey:String) {
        return 1 - (key.toLowerCase().getLevenshteinDistance(fuzzySearchKey.toLowerCase()) / Math.max(key.length, fuzzySearchKey.length));
    }

    function bestMatch(fuzzySearchKey:String, ?throwIfNone=true):String {
        if (this.exists(fuzzySearchKey)) return fuzzySearchKey;

        var bestScore = 0.0;
        var bestKey = null;

        for (key in this.keys()) {
            var score = fuzzyMatchScore(key, fuzzySearchKey);
            if (score > bestScore) {
                bestScore = score;
                bestKey = key;
            }
        }

        if (bestScore < threshold) {
            if (throwIfNone)
                throw 'No good match for $fuzzySearchKey in $this -- best was $bestKey with $bestScore';
            else
                return null;
        }

        #if (test || debug)
        trace('Fuzzy match $bestKey for $fuzzySearchKey score: $bestScore');
        #end
        
        return bestKey;
    }

    @:arrayAccess
    public inline function get(fuzzySearchKey:String):Null<T> {
        var match = bestMatch(fuzzySearchKey);
        var value = this.get(match);
        if (match != null) {
            FuzzyMapTools.onMatchMade(this, fuzzySearchKey, value);
        }
        return value;
    }

    public inline function remove(fuzzySearchKey:String):Bool {
        var key = bestMatch(fuzzySearchKey, false);
        if (key == null) return false;
        return this.remove(key);
    }

    public inline function exists(fuzzySearchKey:String):Bool {
        return bestMatch(fuzzySearchKey, false) != null;
    }

    public inline function existsExactly(searchKey:String):Bool {
        return this.exists(searchKey);
    }

    @:arrayAccess
    public inline function set(key:String, v:T):T {
        this.set(key, v);
        return v;
    }
}
