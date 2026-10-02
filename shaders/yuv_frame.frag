#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform highp vec2 uFrameSize;    // W, H
uniform highp vec2 uTextureSize;  // texture width, height
// view -> source: sx = x*m00 + y*m01 + t0, sy = x*m10 + y*m11 + t1
uniform highp vec4 uLinear;       // (m00, m10, m01, m11)
uniform highp vec2 uTranslate;    // (t0, t1)
uniform highp vec3 uU;            // row, offset, step
uniform highp vec3 uV;
uniform sampler2D uPlanes;

out vec4 fragColor;

float planeByte(highp float row, highp float byteIndex) {
  highp float texel = floor(byteIndex / 4.0);
  highp float channel = byteIndex - texel * 4.0;
  vec4 value = texture(uPlanes, (vec2(texel, row) + 0.5) / uTextureSize);
  vec4 mask = vec4(1.0) - min(abs(vec4(channel) - vec4(0.0, 1.0, 2.0, 3.0)), vec4(1.0));
  return floor(dot(value, mask) * 255.0 + 0.5);
}

void main() {
  highp vec2 p = FlutterFragCoord().xy;
  highp vec2 s = floor(vec2(p.x * uLinear.x + p.y * uLinear.z, p.x * uLinear.y + p.y * uLinear.w) + uTranslate);
  s = clamp(s, vec2(0.0), uFrameSize - 1.0);
  highp vec2 c = floor(s / 2.0);

  float y = planeByte(s.y, s.x);
  float u = planeByte(uU.x + c.y, uU.y + c.x * uU.z);
  float v = planeByte(uV.x + c.y, uV.y + c.x * uV.z);

  // BT.601 limited range as in src/yuv/abi/yuv_convert_v1.c: (k * value + 128) >> 8 == floor(k / 256 * value + 0.5).
  float yy = y - 16.0;
  float d = u - 128.0;
  float e = v - 128.0;
  float r = floor(1.1640625 * yy + 1.59765625 * e + 0.5);
  float g = floor(1.1640625 * yy - 0.390625 * d - 0.8125 * e + 0.5);
  float b = floor(1.1640625 * yy + 2.015625 * d + 0.5);
  fragColor = vec4(clamp(vec3(r, g, b), 0.0, 255.0) / 255.0, 1.0);
}
