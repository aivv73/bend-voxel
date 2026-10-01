import Base
import ./LAWS.bend as Laws
import ./src/megascene_scale.bend as Scale

def Laws.stress_first_measured_edit(): {==}
def Laws.stress_warmup_has_no_edit(): {==}
def Laws.stress_six_edit_limit(): {==}
def Laws.stress_disabled_edits(frame,warmup): {==}
def Laws.stress_nearest_rank_p95(): {==}

def Laws.operational_u32_limit(): {==}
def Laws.operational_u32_overflow(): {==}
def Laws.operational_negative_rejected(): {==}
def Laws.configuration_wrapped_seed_rejected(): {==}
def Laws.operational_u64_limit(): {==}

def Laws.canonical_json_newline(): {==}
def Laws.canonical_json_non_bmp(): {==}
def Laws.canonical_schedule_field_order(): {==}

def Laws.checkpoint_coincident_order(a,b): {==}
def Laws.runtime_signed_zero_word(): {==}
def Laws.runtime_null_action_word(): {==}

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

def Laws.district_rejected(q,seed,control): {==}
def Laws.district_preserved(q,seed,control): {==}
def Laws.scale_half_double(a):
  match a:
    case Scale.ScaleZero{}: {==}
    case Scale.ScaleBit{b,t}: {==}
def Laws.scale_sqrt_fuel(target,lo,hi): {==}
def Laws.history_no_prior_visits(count,stride,offset,neighborhood,index): {==}
def Laws.admission_add_limit(): {==}
def Laws.admission_add_overflow(): {==}
def Laws.admission_mul_limit(): {==}
def Laws.admission_mul_overflow(): {==}
def Laws.admission_mul_zero(value): {==}
def Laws.scale_midpoint_lower_tie(): {==}
