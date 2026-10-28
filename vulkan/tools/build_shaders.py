#!/usr/bin/env python3
"""Compile Vulkan 1.0 example shaders and embed validated little-endian words."""
import argparse
import json
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


FIELDS = (
    ('camera_clip', 'mat4', 1),
    ('light_clip', 'mat4', 1),
    ('eye_near', 'vec4', 1),
    ('camera_right', 'vec4', 1),
    ('camera_up', 'vec4', 1),
    ('camera_forward_focal', 'vec4', 1),
    ('viewport', 'vec4', 1),
    ('brush_cm', 'vec4', 1),
    ('flags', 'uvec4', 1),
    ('palette', 'vec4', 5),
    ('shadow_params', 'vec4', 1),
    ('selected', 'uvec4', 125),
)
SHADERS = ('appearance_world.vert', 'appearance_world.frag', 'appearance_shadow.vert',
           'appearance_shadow.frag', 'appearance_backdrop.vert', 'appearance_backdrop.frag',
           'appearance_ring.vert', 'appearance_ring.frag', 'appearance_abi.frag')


def layout():
    offset = 0
    fields = []
    for name, kind, count in FIELDS:
        offset = (offset + 15) // 16 * 16
        size = (64 if kind == 'mat4' else 16) * count
        fields.append(dict(name=name, kind=kind, count=count, offset=offset, size=size))
        offset += size
    assert offset == 2336, f'ABI conflict: {offset} bytes instead of 2336'
    return fields


def generated():
    fields = layout()
    glsl = ['layout(std140, set=0, binding=0) uniform AppearanceFrame {']
    for f in fields:
        array = f'[{f["count"]}]' if f['count'] > 1 else ''
        glsl.append(f'  {f["kind"]} {f["name"]}{array};')
    glsl += ['} frame;', '']
    words = ['uint appearance_frame_word(uint i) {']
    for f in fields:
        first, end = f['offset'] // 4, (f['offset'] + f['size']) // 4
        words.append(f'  if (i >= {first}u && i < {end}u) {{')
        words.append(f'    uint j = i - {first}u;')
        access = f'frame.{f["name"]}'
        if f['kind'] == 'mat4':
            access += '[j / 4u][j % 4u]'
        elif f['count'] > 1:
            access += '[j / 4u][j % 4u]'
        else:
            access += '[j]'
        words.append('    return ' + (access if f['kind'] == 'uvec4' else f'floatBitsToUint({access})') + ';')
        words += ['  }']
    words += ['  return 0u;', '}', '']
    bend = ['import Base', '', 'type FrameWords is Type:', '  FrameWords{' + ', '.join(f'{f["name"]}: List<U32>' for f in fields) + '}', '',
            'type Field is Type:', '  Field{offset_words: U32, size_words: U32, values: List<U32>}', '',
            'def byte_size() -> U32:', '  2336', '', 'def word_count() -> U32:', '  584', '']
    for f in fields:
        bend += [f'def offset_{f["name"]}() -> U32:', f'  {f["offset"]}', '']
    names = ','.join(f['name'] for f in fields)
    bend += ['def fields(values: FrameWords) -> List<Field>:', f'  FrameWords{{{names}}} = values', '  [']
    for i,f in enumerate(fields):
        bend.append(f'    Field{{{f["offset"] // 4},{f["size"] // 4},{f["name"]}}}' + (',' if i+1<len(fields) else ''))
    bend += ['  ]', '',
             'def put(values: List<U32>, fuel: Nat, +offset: U32, words: Array<U32>) -> Maybe<Array<U32>>:',
             '  match values fuel:', '    case Nil{} 0n: Some{words}',
             '    case Con{value,rest} 1n+tail:', '      words[offset] <- value',
             '      put(rest,tail,(offset + 1 : U32),words)', '    case _ _: None{}', '',
             'def pack_fields(fields: List<Field>, words: Array<U32>) -> Maybe<Array<U32>>:',
             '  match fields:', '    case Nil{}: Some{words}',
             '    case Con{Field{offset,size,values},rest}:',
             '      do Maybe<&1,Array<U32>>:',
             '        next : Array<U32> <- put(values,U32.to_nat(size),offset,words)',
             '        pack_fields(rest,next)', '',
             'def pack(values: FrameWords) -> Maybe<Array<U32>>:',
             '  pack_fields(fields(values),[0 : U32^10n])', '']
    return {'shaders/appearance_frame.glsl': '\n'.join(glsl),
            'shaders/appearance_words.glsl': '\n'.join(words),
            'shaders/appearance_uniforms.bend': '\n'.join(bend),
            'shaders/appearance_layout.json': json.dumps(dict(bytes=2336, words=584, fields=fields), indent=2)+'\n'}



def generate():
    lines = ["import Base", ""]
    with tempfile.TemporaryDirectory() as temporary:
        for shader, stage, name in (
                                    ("voxel", "vert", "voxel_vertex_words"), ("voxel", "frag", "voxel_fragment_words"),
                                    ("voxel_material", "frag", "voxel_material_words"),
                                    ("voxel_direction", "frag", "voxel_direction_words"),
                                    *((name.split(".")[0],name.split(".")[1],name.replace(".","_")+"_words") for name in SHADERS),
                                    *((name,"vert" if name in ("metadata_adapter","depth_fixture") else "frag", "fixture_"+name+"_words") for name in ("metadata_adapter","depth_fixture","sample_fixture","world_metadata")),
                                    ("depth_fixture","frag","fixture_depth_fragment_words")):
            output = pathlib.Path(temporary) / f"{shader}.{stage}.spv"
            subprocess.run(["glslc", "--target-env=vulkan1.0", "-O", "-I", str(ROOT / "shaders"), "-o", str(output),
                            str(ROOT / f"shaders/{shader}.{stage}")], check=True)
            subprocess.run(["spirv-val", "--target-env", "vulkan1.0", str(output)], check=True)
            data = output.read_bytes()
            if len(data) % 4 or data[:4] != b"\x03\x02\x23\x07":
                raise ValueError("Expected little-endian SPIR-V")
            words = [str(word) for (word,) in struct.iter_unpack("<I", data)]
            chunks = [words[i:i+128] for i in range(0, len(words), 128)]
            for i, chunk in enumerate(chunks):
                lines.extend([f"def {name}_chunk_{i}() -> List<U32>:",
                              "  [" + ",".join(chunk) + "]", ""])
            lines.extend([f"def {name}() -> List<U32>:",
                          "  List.concat(&1,U32,[" + ",".join(f"{name}_chunk_{i}()" for i in range(len(chunks))) + "])", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = ROOT / "shaders/spirv.bend"
    for name, value in generated().items():
        path = ROOT / name
        if args.check:
            if not path.exists() or path.read_text() != value:
                raise SystemExit(f"{name} is stale; run tools/build_shaders.py")
        else:
            path.write_text(value)
    source = generate()
    if args.check:
        if output.read_text() != source:
            raise SystemExit("shaders/spirv.bend is stale; run tools/build_shaders.py")
    else:
        output.write_text(source)


if __name__ == "__main__":
    main()
