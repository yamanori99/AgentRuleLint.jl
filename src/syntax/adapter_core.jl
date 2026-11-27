# Single boundary for JuliaSyntax tree access from rules (and shared kind constants for syntax/).

using JuliaSyntax: GreenNode, children, head, is_infix_op_call, is_leaf, kind, span, summary

const SyntaxTree = GreenNode

const KAssign = JuliaSyntax.K"="
const KAt = JuliaSyntax.K"@"
const KBool = JuliaSyntax.K"Bool"
const KBlock = JuliaSyntax.K"block"
const KCall = JuliaSyntax.K"call"
const KCatch = JuliaSyntax.K"catch"
const KCharExpr = JuliaSyntax.K"char"
const KCmdString = JuliaSyntax.K"CmdString"
const KCmdstring = JuliaSyntax.K"cmdstring"
const KComma = JuliaSyntax.K","
const KComparison = JuliaSyntax.K"comparison"
const KConst = JuliaSyntax.K"const"
const KDot = JuliaSyntax.K"."
const KElse = JuliaSyntax.K"else"
const KElseif = JuliaSyntax.K"elseif"
const KFloat = JuliaSyntax.K"Float"
const KFunction = JuliaSyntax.K"function"
const KIdentifier = JuliaSyntax.K"Identifier"
const KIf = JuliaSyntax.K"if"
const KInteger = JuliaSyntax.K"Integer"
const KMacro = JuliaSyntax.K"macro"
const KMacroName = JuliaSyntax.K"macro_name"
const KMacrocall = JuliaSyntax.K"macrocall"
const KModule = JuliaSyntax.K"module"
const KNewlineWs = JuliaSyntax.K"NewlineWs"
const KOpenParen = JuliaSyntax.K"("
const KOr = JuliaSyntax.K"||"
const KParameters = JuliaSyntax.K"parameters"
const KParens = JuliaSyntax.K"parens"
const KPlaceholder = JuliaSyntax.K"Placeholder"
const KQuote = JuliaSyntax.K"quote"
const KRef = JuliaSyntax.K"ref"
const KReturn = JuliaSyntax.K"return"
const KSemicolon = JuliaSyntax.K";"
const KStringExpr = JuliaSyntax.K"string"
const KStringLeaf = JuliaSyntax.K"String"
const KToplevel = JuliaSyntax.K"toplevel"
const KTry = JuliaSyntax.K"try"
const KTuple = JuliaSyntax.K"tuple"
const KVect = JuliaSyntax.K"vect"

const _CALL_KINDS = (KCall, KMacrocall, KMacro)
const _STMT_TRIVIA_KINDS = (KNewlineWs, KSemicolon)

syntax_kind(node) = kind(node)
syntax_span(node) = span(node)
syntax_head(node) = head(node)
syntax_children(node) = children(node)
syntax_is_trivia(node) = JuliaSyntax.is_trivia(head(node))
syntax_is_infix_op_call(node) = is_infix_op_call(head(node))
syntax_is_leaf(node) = is_leaf(node)
syntax_node_summary(node) = summary(node)

function syntax_interpolation_child(node)::Bool
    return string(kind(node)) == "\$"
end