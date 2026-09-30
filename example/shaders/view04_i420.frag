#version 460 core

// VIEW-04 prototype: draws a tight I420 frame straight from its planes.
// The planes arrive as one RGBA8888 texture of width W/4 and height H*1.5,
// four plane bytes per texel: rows [0, H) hold Y, then H/4 rows of U, then
// H/4 rows of V, two chroma rows per texture row. Conversion is the same
// BT.601 limited-range integer formula as yuv_convert_v1.c.

#include <flutter/runtime_effect.glsl>

uniform vec2 uFrameSize; // source frame W, H
uniform vec4 uMap;       // source = (uMap.x*d.x + uMap.y*d.y, uMap.z*d.x + uMap.w*d.y) + uOffset
uniform vec2 uOffset;
uniform vec2 uTextureSize;
uniform sampler2D uPlanes;

out vec4 fragColor;

float planeByte(float column, float row) {
  float texel = floor(column / 4.0);
  float channel = column - texel * 4.0;
  vec4 value = texture(uPlanes, (vec2(texel, row) + 0.5) / uTextureSize);
  vec4 mask = vec4(1.0) - min(abs(vec4(channel) - vec4(0.0, 1.0, 2.0, 3.0)), vec4(1.0));
  return floor(dot(value, mask) * 255.0 + 0.5);
}

void main() {
  vec2 d = floor(FlutterFragCoord().xy);
  vec2 s = vec2(uMap.x * d.x + uMap.y * d.y, uMap.z * d.x + uMap.w * d.y) + uOffset;
  float width = uFrameSize.x;
  float height = uFrameSize.y;

  float y = planeByte(s.x, s.y);

  vec2 c = floor(s / 2.0);
  float chromaRow = floor(c.y / 2.0);
  float chromaColumn = (c.y - chromaRow * 2.0) * (width / 2.0) + c.x;
  float u = planeByte(chromaColumn, height + chromaRow);
  float v = planeByte(chromaColumn, height + height / 4.0 + chromaRow);

  float c298 = 298.0 * (y - 16.0);
  float dd = u - 128.0;
  float e = v - 128.0;
  float r = floor((c298 + 409.0 * e + 128.0) / 256.0);
  float g = floor((c298 - 100.0 * dd - 208.0 * e + 128.0) / 256.0);
  float b = floor((c298 + 516.0 * dd + 128.0) / 256.0);
  fragColor = vec4(clamp(vec3(r, g, b), 0.0, 255.0) / 255.0, 1.0);
}
