package kiss;

#if (macro || ((sys || hxnodejs) && !frontend))
import sys.io.File;
#end
import haxe.ds.Option;

using StringTools;
using Lambda;
using kiss.Stream;

typedef Position = {
    file:String,
    line:Int,
    column:Int,
    absoluteChar:Int
};

class StreamError {
    var position:Position;
    public var message(default,null):String;

    public function new(position:Position, message:String) {
        this.position = position;
        this.message = message;
    }

    public function toString() {
        return '\nKiss reader error!\n'
            + position.toPrint()
            + ': $message\n';
    }
}

class Stream {
    public var content(default, null):String;

    var file:String;
    var line:Int;
    var column:Int;
    var absoluteChar:Int;

    var absolutePerNewline = 1;

    public var startOfLine = true;

    #if (macro || ((sys || hxnodejs) && !frontend))
    public static function fromFile(file:String) {
        return new Stream(file, File.getContent(file));
    }
    #end

    public static function fromString(content:String, position:Position = null) {
        var file = "string";
        if (position != null) {
            file = position.file;
        }
        var s = new Stream(file, content);
        if (position != null) {
            s.line = position.line;
            s.column = position.column;
            s.absoluteChar = position.absoluteChar;
        }
        return s;
    }

    private function new(file:String, content:String) {
        this.file = file.replace('\\', '/');

        // Banish ye Windows line-endings
        if (content.indexOf('\r') >= 0) {
            absolutePerNewline = 2;
            content = content.replace('\r', '');
        }

        // Life is easier with a trailing newline
        if (content.charAt(content.length - 1) != "\n")
            content += "\n";

        this.content = content;

        line = 1;
        column = 1;
        absoluteChar = 0;
    }

    public function peekChars(chars:Int):Option<String> {
        if (content.length < chars)
            return None;
        return Some(content.substr(0, chars));
    }

    public function isEmpty() {
        return content.length == 0;
    }

    public function position():Position {
        return {
            file: file,
            line: line,
            column: column,
            absoluteChar: absoluteChar
        };
    }

    public static function toPrint(p:Position) {
        return '${p.file}:${p.line}:${p.column}';
    }

    public function startsWith(s:String) {
        return switch (peekChars(s.length)) {
            case Some(s1) if (s == s1): true;
            default: false;
        };
    }

    public function startsWithOneOf(strings:Array<String>) {
        for (s in strings) if (startsWith(s)) return true;
        return false;
    }

    var lineLengths = [];

    /** Every drop call should end up calling dropChars() or the position tracker and recording will be wrong. **/
    public function dropChars(count:Int, taking:Bool) {
        if (count < 0) {
            error(this, "Can't drop negative characters");
        }
        for (idx in 0...count) {
            switch (content.charAt(idx)) {
                // newline
                case "\n":
                    _currentTab = "";
                    absoluteChar += absolutePerNewline;
                    line += 1;
                    lineLengths.push(column);
                    column = 1;
                    startOfLine = true;
                // other whitespace character
                case c if (c.trim() == ""):
                    _currentTab += c;
                    absoluteChar += 1;
                    column += 1;
                // non-whitespace
                default:
                    absoluteChar += 1;
                    column += 1;
                    startOfLine = false;
            }
        }

        function record() {
            recording += content.substr(0, count);
        }

        switch (recordingType) {
            case Both:
                record();
            case Take if (taking):
                record();
            case Drop if (!taking):
                record();
            default:
        }

        content = content.substr(count);
    }

    public function putBackString(s:String) {
        if (recordingType != Neither) {
            recording = recording.substr(0, recording.length - s.length);
        }
        #if macro
        Kiss.measure("Stream.putBackString", () -> {
        #end
            var idx = s.length - 1;
            while (idx >= 0) {
                absoluteChar -= 1;
                switch (s.charAt(idx)) {
                    case "\n":
                        line -= 1;
                        column = lineLengths.pop();
                    default:
                        column -= 1;
                }
                --idx;
            }
            content = s + content;
        #if macro
        }, true);
        #end
    }

    var _currentTab = "";

    public function currentTab():String {
        return _currentTab;
    }

    public var linePrefix = '';

    public function takeChars(count:Int):Option<String> {
        if (count > content.length)
            return None;
        var toReturn = content.substr(0, count);
        if (linePrefix.length > 0) {
            toReturn = toReturn.replace('\n{linePrefix}', '\n');
        }
        dropChars(count, true);
        return Some(toReturn);
    }

    public function dropString(s:String) {
        var toDrop = content.substr(0, s.length);
        if (toDrop != s) {
            error(this, 'Expected $s');
        }
        dropChars(s.length, false);
    }

    public function dropStringIf(s:String):Bool {
        var toDrop = content.substr(0, s.length);
        if (toDrop == s) {
            dropString(toDrop);
            return true;
        }
        return false;
    }

    public function dropUntil(s:String) {
        dropChars(content.indexOf(s), false);
    }

    public function tryDropUntil(s:String) {
        if (content.indexOf(s) != -1) {
            dropUntil(s);
        }
    }

    public function dropWhitespace() {
        var trimmed = content.ltrim();
        dropChars(content.length - trimmed.length, false);
    }

    public function takeUntilOneOf(terminators:Array<String>, allowEOF:Bool = false):Option<String> {
        var indices = [for (term in terminators) content.indexOf(term)].filter((idx) -> idx >= 0);
        if (indices.length == 0) {
            return if (allowEOF) {
                Some(takeRest());
            } else {
                None;
            }
        }
        var firstIndex = Math.floor(indices.fold(Math.min, indices[0]));
        return takeChars(firstIndex);
    }

    public function takeUntil(s:String, allowEOF:Bool = false):Option<String> {
        return takeUntilOneOf([s], allowEOF);
    }

    public function takeUntilAndDrop(s:String, allowEOF:Bool = false):Option<String> {
        return _takeUntilAndDrop(s, allowEOF, false);
    }

    public function takeUntilLastAndDrop(s:String, allowEOF:Bool = false):Option<String> {
        return _takeUntilAndDrop(s, allowEOF, true);
    }

    public function _takeUntilAndDrop(s:String, allowEOF:Bool, last:Bool):Option<String> {
        var idx = if (last)
            content.lastIndexOf(s);
        else
            content.indexOf(s);

        if (idx < 0) {
            return if (allowEOF) {
                Some(takeRest());
            } else {
                None;
            }
        }

        var toReturn = content.substr(0, idx);
        dropChars(toReturn.length, true);
        dropChars(s.length, false);
        return Some(toReturn);
    }

    public function dropOneOf(options:Array<String>) {
        switch(_dropWhileOneOf(options, true, true)) {
            case None:
                error(this, 'expected to drop one of ${options}');
            default:
        }
    }

    public function takeOneOf(options:Array<String>) {
        return _dropWhileOneOf(options, true, true);
    }

    function _dropOneOf(options:Array<String>, take:Bool) {
        _dropWhileOneOf(options, take, true);
    }

    public function dropWhileOneOf(options:Array<String>) {
        _dropWhileOneOf(options, false);
    }

    public function takeWhileOneOf(options:Array<String>) {
        return _dropWhileOneOf(options, true);
    }

    function _dropWhileOneOf(options:Array<String>, take:Bool, justOnce=false):Option<String> {
        var taken = "";

        var lengths = [for (option in options) option.length => true];
        var optsMap = [for (option in options) option => true];

        var nextIs = false;
        do {
            nextIs = false;
            for (length => _ in lengths) {
                var sample = content.substr(0, length);
                if (optsMap.exists(sample)) {
                    nextIs = !justOnce && true;
                    if (take) {
                        taken += sample;
                    }
                    dropChars(length, take);
                }
            }

        } while(nextIs);


        if (taken.length == 0)
            return None;

        return Some(taken);
    }

    // If the stream starts with the opening delimiter, return the text between it and the closing delimiter.
    // Allow either delimiter to appear immediately after escapeSeq,
    // otherwise throw if open occurs again before close, and end on finding close
    public function takeBetween(open:String, close:String, ?escapeSeq:String):Option<String> {
        if (!startsWith(open)) return None;
        dropString(open);
        var taken = "";
        while (true) {
            if (startsWith(close)) {
                dropString(close);
                return Some(taken);
            } else if (startsWith(open)) {
                error(this, "takeBetween() does not support nested delimiter pairs");
            } else if (escapeSeq != null && startsWith(escapeSeq)) {
                dropString(escapeSeq);
                if (startsWith(open)) {
                    dropString(open);
                    taken += open;
                } else if (startsWith(close)) {
                    dropString(close);
                    taken += close;
                } else if (startsWith(escapeSeq)) {
                    dropString(escapeSeq);
                    taken += escapeSeq;
                } else {
                    error(this, 'invalid escape sequence');
                }
            } else {
                var next = switch (takeChars(1)) {
                    case Some(n): n;
                    default: error(this, 'Ran out of characters before closing delimiter $close'); "";
                }
                taken += next;
            }
        }
    }

    public function takeRest():String {
        var toReturn = content;
        dropChars(content.length, true);
        return toReturn;
    }

    public function dropRest() {
        dropChars(content.length, false);
    }

    public function takeLine():Option<String> {
        return switch (takeUntilAndDrop("\n")) {
            case Some(line): Some(line);
            case None if (content.length > 0): Some(takeRest());
            default: None;
        };
    }

    public function takeLineAsStream():Option<Stream> {
        var lineNo = this.line;
        var column = this.column;
        var absoluteChar = this.absoluteChar;
        return switch (takeLine()) {
            case Some(line): Some({
                var s = Stream.fromString(line);
                s.line = lineNo;
                s.column = column;
                s.file = this.file;
                s.absoluteChar = absoluteChar;
                s;
            });
            default: None;
        };
    }

    public function expect(whatToExpect:String="something unspecified", f:Void->Option<String>):String {
        var position = position();
        switch (f()) {
            case Some(s):
                return s;
            default:
                error(this, 'Expected $whatToExpect');
                return null;
        }
    }

    public static function error(stream:Stream, message:String) {
        throw new StreamError(stream.position(), message);
    }

    private var recordingType:StreamRecordType = Neither;
    private var recording = "";

    public function recordTransaction(type:StreamRecordType = Both, transaction:Void->Void) {
        if (type == Neither) {
            error(this, "Tried to start recording a transaction that would always return an empty string");
        }
        if (recordingType != Neither) {
            error(this, "Tried to start recording a transaction before finishing the current one");
        }
        recordingType = type;
        recording = "";

        transaction();

        recordingType = Neither;

        return recording;
    }
}

enum StreamRecordType {
    Neither;
    Drop;
    Take;
    Both;
}