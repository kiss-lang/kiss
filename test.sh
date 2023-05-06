#! /bin/bash

KISS_TARGET=${KISS_TARGET:-$1}
KISS_TARGET=${KISS_TARGET:-interp}

if [ -n "$CI_OS_NAME" ]; then
    lix download
fi

if [ "$KISS_TARGET" = cpp ]; then
    lix install haxelib:hxcpp
elif [ "$KISS_TARGET" = cs ]; then
    lix install haxelib:hxcs
fi
elif [ "$KISS_TARGET" = nodejs ]; then
    lix install haxelib:hxnodejs
fi

if [ ! -z "$2" ]; then
    haxe -D cases=$2 build-scripts/common-args.hxml build-scripts/common-test-args.hxml build-scripts/$KISS_TARGET/test.hxml
else
    haxe build-scripts/common-args.hxml build-scripts/common-test-args.hxml build-scripts/$KISS_TARGET/test.hxml
fi