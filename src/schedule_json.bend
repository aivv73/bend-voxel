import Base

def hex(+c: U32) -> Char:
  Chr{(c + Bool.pick(U32,(c < 10 : U32),48,87) : U32)}
def hex4(+c: U32) -> String:
  "\\u" ++ SCon{hex(((c >> 12n : U32) .&. 15 : U32)),
    SCon{hex(((c >> 8n : U32) .&. 15 : U32)),
      SCon{hex(((c >> 4n : U32) .&. 15 : U32)),SCon{hex((c .&. 15 : U32)),SNil{}}}}}
def escaped.unicode(+c: U32) -> String:
  Bool.pick(String,(c <= 65535 : U32),hex4(c),
    hex4((55296 + ((c - 65536 : U32) >> 10n : U32) : U32)) ++ hex4((56320 + (c .&. 1023 : U32) : U32)))
def escaped(+c: U32) -> String:
  match c:
    case 34: "\\\""
    case 92: "\\\\"
    case 8: "\\b"
    case 9: "\\t"
    case 10: "\\n"
    case 12: "\\f"
    case 13: "\\r"
    case c: Bool.pick(String,((c < 32) || (c >= 127) : U32),escaped.unicode(c),SCon{Chr{c},SNil{}})
def quote.tail(s: String) -> String:
  match s:
    case SNil{}: "\""
    case SCon{Chr{c},rest}: escaped(c) ++ quote.tail(rest)
def quote(s: String) -> String: "\"" ++ quote.tail(s)
def number(n: U32) -> String: quote(U32.show(n))
def boolean(b: Bool) -> String:
  match b:
    case True{}: "true"
    case False{}: "false"
def tail(xs: List<&2,String>) -> String:
  match xs:
    case Nil{}: "]"
    case x <> rest: "," ++ x ++ tail(rest)
def array(xs: List<&2,String>) -> String:
  match xs:
    case Nil{}: "[]"
    case x <> rest: "[" ++ x ++ tail(rest)
def field(name: String, value: String) -> String: quote(name) ++ ":" ++ value
def fields(xs: List<&2,String>) -> String:
  match xs:
    case Nil{}: "}"
    case x <> Nil{}: x ++ "}"
    case x <> rest: x ++ "," ++ fields(rest)
# Schedule field names are fixed ASCII identifiers. Sorting their encoded
# fields preserves the canonical key order, including names with a common prefix.
def object(xs: List<&2,String>) -> String:
  "{" ++ fields(List.sort(String,String.is_le,xs))
def point(name: String, frame: U32) -> String:
  object([field("name",quote(name)),field("frame",number(frame))])
def review(name: String, frame: U32, features: List<&2,String>) -> String:
  object([field("name",quote(name)),field("frame",number(frame)),field("features",array(features))])
