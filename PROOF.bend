import Base
import ./LAWS.bend as Laws

def Laws.palette_length():
  {==}

# These are checked equalities, not IO tests. Runtime geometry checks remain
# in make test because their implementations currently rely on @unsafe.
def Laws.material_ids(): {==}
def Laws.foundation_anchor(): {==}
def Laws.editable_materials(): {==}

def Laws.append_empty(A,xs):
  match xs:
    case Nil{}: {==}
    case h <> t:
      %Laws.append_empty(A,t) : {h <> List.append(&2,A,t,Nil{}) == h <> _ : List<&2,A>}
      {==}
def Laws.append_associative(A,xs,ys,zs):
  match xs:
    case Nil{}: {==}
    case h <> t:
      %Laws.append_associative(A,t,ys,zs) :
        {h <> List.append(&2,A,List.append(&2,A,t,ys),zs) == h <> _ : List<&2,A>}
      {==}
def Laws.append_length(A,xs,ys):
  match xs:
    case Nil{}: {==}
    case h <> t:
      %Laws.append_length(A,t,ys) :
        {1n+List.length(&2,A,List.append(&2,A,t,ys)) == 1n+_ : Nat}
      {==}
def Laws.word_same(c,value):
  match c:
    case True{}: {==}
    case False{}: {==}
def Laws.pick_same(c,value):
  match c:
    case True{}: {==}
    case False{}: {==}
def Laws.gamut_fuel(lightness,hue,lo,hi): {==}
def Laws.resolution_rejected(width,height): {==}
def Laws.resolution_preserved(width,height): {==}
def Laws.resolution_default(): {==}
def Laws.resolution_pixel_limit(): {==}
def Laws.resolution_malformed(): {==}
def Laws.palette_material_order(): {==}
