#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cmath>
#include <cstdint>
#include <stdexcept>

namespace material {

struct Rgb { float r, g, b; };
struct Oklch { float lightness, chroma, hue_degrees; };
struct Definition { uint32_t id; const char* name; Oklch base; };
inline constexpr uint32_t foundation_id=1;

// IDs are the stable voxel values declared in src/material.bend. Colors were
// authored from the original demo palette, then expressed as OKLCH values.
inline constexpr std::array<Definition,4> definitions{{
  {foundation_id,"foundation",{0.736340f,0.114340f,173.8965f}},
  {2,"concrete",  {0.733411f,0.093103f, 66.0436f}},
  {3,"frame",     {0.630974f,0.062930f,239.8232f}},
  {4,"machinery", {0.723628f,0.119039f, 64.7019f}},
}};

inline const Definition& find(uint32_t id) {
  if (id==0 || id>definitions.size() || definitions[id-1].id!=id)
    throw std::runtime_error("unknown voxel material");
  return definitions[id-1];
}

// Oklab -> linear sRGB, using Bjorn Ottosson's published D65 matrices:
// https://bottosson.github.io/posts/oklab/
inline Rgb raw_linear(Oklch color) {
  constexpr float radians=0.017453292519943295f;
  const float a=color.chroma*std::cos(color.hue_degrees*radians);
  const float b=color.chroma*std::sin(color.hue_degrees*radians);
  const auto cube=[](float value) { return value*value*value; };
  const float l=cube(color.lightness+0.3963377774f*a+0.2158037573f*b);
  const float m=cube(color.lightness-0.1055613458f*a-0.0638541728f*b);
  const float s=cube(color.lightness-0.0894841775f*a-1.2914855480f*b);
  return {+4.0767416621f*l-3.3077115913f*m+0.2309699292f*s,
          -1.2684380046f*l+2.6097574011f*m-0.3413193965f*s,
          -0.0041960863f*l-0.7034186147f*m+1.7076147010f*s};
}

inline bool in_gamut(Rgb c) {
  return std::isfinite(c.r)&&std::isfinite(c.g)&&std::isfinite(c.b)&&
    c.r>=0&&c.r<=1&&c.g>=0&&c.g<=1&&c.b>=0&&c.b<=1;
}

// Keep lightness and hue; reduce chroma only when the requested color lies
// outside sRGB. The search runs once for each palette swatch, not per face.
inline Rgb to_linear(Oklch color) {
  if (!std::isfinite(color.lightness)||!std::isfinite(color.chroma)||
      !std::isfinite(color.hue_degrees)||color.chroma<0)
    throw std::runtime_error("invalid OKLCH material color");
  color.lightness=std::clamp(color.lightness,0.0f,1.0f);
  Rgb rgb=raw_linear(color);
  if (in_gamut(rgb)) return rgb;
  float lo=0,hi=color.chroma;
  for (int i=0;i<24;i++) {
    color.chroma=(lo+hi)*0.5f;
    if (in_gamut(raw_linear(color))) lo=color.chroma;
    else hi=color.chroma;
  }
  color.chroma=lo;
  rgb=raw_linear(color);
  return {std::clamp(rgb.r,0.0f,1.0f),std::clamp(rgb.g,0.0f,1.0f),
    std::clamp(rgb.b,0.0f,1.0f)};
}

// IEC sRGB transfer functions, also specified in CSS Color 4.
inline float encode_channel(float value) {
  value=std::clamp(value,0.0f,1.0f);
  return value<=0.0031308f ? 12.92f*value : 1.055f*std::pow(value,1.0f/2.4f)-0.055f;
}
inline float decode_channel(float value) {
  return value<=0.04045f ? value/12.92f : std::pow((value+0.055f)/1.055f,2.4f);
}
inline Rgb encode(Rgb color) {
  return {encode_channel(color.r),encode_channel(color.g),encode_channel(color.b)};
}
inline Rgb decode(Rgb color) {
  return {decode_channel(color.r),decode_channel(color.g),decode_channel(color.b)};
}

inline float light(uint32_t side) {
  return side==3 ? 1.0f : side<2 ? 0.58f : 0.35f;
}

using Swatches=std::array<std::array<std::array<Rgb,6>,2>,definitions.size()>;
inline const Swatches& swatches() {
  static const Swatches values=[] {
    Swatches result{};
    for (size_t i=0;i<definitions.size();i++) for (size_t detached=0;detached<2;detached++) {
      Oklch color=definitions[i].base;
      if (detached) {
        // A body state treatment: retain material hue and identity.
        color.lightness=std::min(0.92f,color.lightness+0.07f);
        color.chroma*=0.72f;
      }
      Rgb base=to_linear(color);
      for (uint32_t side=0;side<6;side++) {
        float amount=light(side);
        result[i][detached][side]=encode({base.r*amount,base.g*amount,base.b*amount});
      }
    }
    return result;
  }();
  return values;
}

inline Rgb surface(uint32_t id,bool detached,uint32_t side) {
  if (side>=6) throw std::runtime_error("invalid voxel face side");
  return swatches()[find(id).id-1][detached?1:0][side];
}

} // namespace material
