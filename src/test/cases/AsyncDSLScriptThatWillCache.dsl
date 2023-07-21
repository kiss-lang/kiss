{goop (cc)}
{gloop (cc)}
{(Assert.isTrue (FuzzyMapTools.isFuzzy fuzzyMap))(cc)}
{(Assert.isFalse (FuzzyMapTools.isFuzzy nonFuzzyMap))(cc)}

{
    (dictSet fuzzyMap "lowercase" true)
    (dictSet nonFuzzyMap "lowercase" true)
    (Assert.isTrue (dictGet fuzzyMap "LOWERCASE"))
    (Assert.isFalse ?(dictGet nonFuzzyMap "LOWERCASE"))
    (cc)
}

{(set wholeScriptDone true) (cc)}