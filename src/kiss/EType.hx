package kiss;

enum EType {
    EStream(message:String);
    EKiss(message:String);
    EUnmatchedBracket(type:String);
    EException(message:String);
    EExpected(e:EType);
    EUnexpected(e:Dynamic);
    EAny;
}
