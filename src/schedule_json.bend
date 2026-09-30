import Base

def quote(s: String) -> String: "\"" ++ s ++ "\""
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
def object(xs: List<&2,String>) -> String: "{" ++ fields(xs)
def point(name: String, frame: U32) -> String:
  object([field("name",quote(name)),field("frame",number(frame))])
def review(name: String, frame: U32, features: List<&2,String>) -> String:
  object([field("name",quote(name)),field("frame",number(frame)),field("features",array(features))])
