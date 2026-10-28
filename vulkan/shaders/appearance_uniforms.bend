import Base

type FrameWords is Type:
  FrameWords{camera_clip: List<U32>, light_clip: List<U32>, eye_near: List<U32>, camera_right: List<U32>, camera_up: List<U32>, camera_forward_focal: List<U32>, viewport: List<U32>, brush_cm: List<U32>, flags: List<U32>, palette: List<U32>, shadow_params: List<U32>, selected: List<U32>}

type Field is Type:
  Field{offset_words: U32, size_words: U32, values: List<U32>}

def byte_size() -> U32:
  2336

def word_count() -> U32:
  584

def offset_camera_clip() -> U32:
  0

def offset_light_clip() -> U32:
  64

def offset_eye_near() -> U32:
  128

def offset_camera_right() -> U32:
  144

def offset_camera_up() -> U32:
  160

def offset_camera_forward_focal() -> U32:
  176

def offset_viewport() -> U32:
  192

def offset_brush_cm() -> U32:
  208

def offset_flags() -> U32:
  224

def offset_palette() -> U32:
  240

def offset_shadow_params() -> U32:
  320

def offset_selected() -> U32:
  336

def fields(values: FrameWords) -> List<Field>:
  FrameWords{camera_clip,light_clip,eye_near,camera_right,camera_up,camera_forward_focal,viewport,brush_cm,flags,palette,shadow_params,selected} = values
  [
    Field{0,16,camera_clip},
    Field{16,16,light_clip},
    Field{32,4,eye_near},
    Field{36,4,camera_right},
    Field{40,4,camera_up},
    Field{44,4,camera_forward_focal},
    Field{48,4,viewport},
    Field{52,4,brush_cm},
    Field{56,4,flags},
    Field{60,20,palette},
    Field{80,4,shadow_params},
    Field{84,500,selected}
  ]

def put(values: List<U32>, fuel: Nat, +offset: U32, words: Array<U32>) -> Maybe<Array<U32>>:
  match values fuel:
    case Nil{} 0n: Some{words}
    case Con{value,rest} 1n+tail:
      words[offset] <- value
      put(rest,tail,(offset + 1 : U32),words)
    case _ _: None{}

def pack_fields(fields: List<Field>, words: Array<U32>) -> Maybe<Array<U32>>:
  match fields:
    case Nil{}: Some{words}
    case Con{Field{offset,size,values},rest}:
      do Maybe<&1,Array<U32>>:
        next : Array<U32> <- put(values,U32.to_nat(size),offset,words)
        pack_fields(rest,next)

def pack(values: FrameWords) -> Maybe<Array<U32>>:
  pack_fields(fields(values),[0 : U32^10n])
