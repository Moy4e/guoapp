// 液态玻璃透镜着色器。
//
// 视觉算法移植自 SukiSU-Ultra（https://github.com/ShirkNeko/SukiSU-Ultra ，
// GPL-3.0-or-later）的 manager/app/src/main/java/com/sukisu/ultra/ui/component/
// liquid/Lens.kt 与 Vibrancy.kt，其上游为 Kyant0/AndroidLiquidGlass
// （https://github.com/Kyant0/AndroidLiquidGlass ，Apache-2.0）。
//
// 在 Flutter 侧经 BackdropFilter + ImageFilter.shader 作用于玻璃区域背后的
// 内容：先做饱和度提升（vibrancy）与轻度高斯模糊，再按圆角矩形 SDF 对边缘
// 带做透镜折射（可选深度折射与色散）。玻璃区域向外扩张的部分由本着色器裁掉
// （形状外输出全透明），扩张区域只为给折射提供可采样的背景内容。
//
// 注意：ImageFilter.shader 要求第一个 uniform 为 vec2（引擎注入绑定纹理尺寸），
// 且至少一个 sampler2D（引擎注入滤镜输入）。GLES 后端纹理 y 轴朝向相反，
// 采样前需翻转。

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;                // 引擎注入：绑定纹理尺寸（玻璃区域，设备像素）
uniform vec2 u_shape_size;          // 玻璃形状（胶囊）的尺寸，设备像素
uniform vec4 u_corner_radii;        // 圆角半径：左上、右上、右下、左下，设备像素
uniform float u_refraction_height;  // 折射作用的边缘带宽度，设备像素
uniform float u_refraction_amount;  // 折射位移量，设备像素
uniform float u_depth_effect;       // 0/1：深度折射（向形状中心牵引）
uniform float u_chromatic_aberration; // 色散强度，0 为关闭
uniform float u_vibrancy;           // 0/1：饱和度提升至 1.5 倍
uniform float u_blur_radius;        // 背景模糊半径（3x3 高斯间距），设备像素

uniform sampler2D u_texture_input;

out vec4 frag_color;

float radiusAt(vec2 coord, vec4 radii) {
    if (coord.x >= 0.0) {
        if (coord.y <= 0.0) return radii.y;
        else return radii.z;
    } else {
        if (coord.y <= 0.0) return radii.x;
        else return radii.w;
    }
}

float sdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    float outside = length(max(cornerCoord, vec2(0.0))) - radius;
    float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
    return outside + inside;
}

vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        return sign(coord) * normalize(max(cornerCoord, vec2(0.0)));
    } else {
        float gradX = step(cornerCoord.y, cornerCoord.x);
        return sign(coord) * vec2(gradX, 1.0 - gradX);
    }
}

float circleMap(float x) {
    return 1.0 - sqrt(1.0 - x * x);
}

vec2 texCoordOf(vec2 coord) {
    vec2 uv = coord / u_size;
    #ifdef IMPELLER_TARGET_OPENGLES
        uv.y = 1.0 - uv.y;
    #endif
    return uv;
}

vec3 applyVibrancy(vec3 color) {
    if (u_vibrancy < 0.5) return color;
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(luma), color, 1.5);
}

// 采样背景内容；u_blur_radius > 0 时叠加 3x3 高斯（权重 1-2-1 / 16）。
vec4 sampleBackground(vec2 coord) {
    vec4 center = texture(u_texture_input, texCoordOf(coord));
    if (u_blur_radius < 0.75) {
        return vec4(applyVibrancy(center.rgb), center.a);
    }
    float r = u_blur_radius;
    vec3 sum = center.rgb * 4.0;
    float weight = 4.0;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(-r, -r))).rgb;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(0.0, -r))).rgb * 2.0;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(r, -r))).rgb;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(-r, 0.0))).rgb * 2.0;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(r, 0.0))).rgb * 2.0;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(-r, r))).rgb;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(0.0, r))).rgb * 2.0;
    sum += texture(u_texture_input, texCoordOf(coord + vec2(r, r))).rgb;
    weight += 12.0;
    return vec4(applyVibrancy(sum / weight), center.a);
}

void main() {
    vec2 coord = FlutterFragCoord().xy;
    vec2 regionCenter = u_size * 0.5;
    vec2 halfShape = u_shape_size * 0.5;
    vec2 centeredCoord = coord - regionCenter;

    float radius = radiusAt(centeredCoord, u_corner_radii);
    float sd = sdRoundedRect(centeredCoord, halfShape, radius);

    // 形状之外全透明：扩张区域只服务于折射采样。
    if (sd > 0.0) {
        frag_color = vec4(0.0);
        return;
    }

    if (u_refraction_height <= 0.0 || -sd >= u_refraction_height) {
        frag_color = sampleBackground(coord);
        return;
    }
    sd = min(sd, 0.0);

    float d = circleMap(1.0 - -sd / u_refraction_height) * u_refraction_amount;
    float gradRadius = min(radius * 1.5, min(halfShape.x, halfShape.y));
    vec2 grad = normalize(
        gradSdRoundedRect(centeredCoord, halfShape, gradRadius) +
        u_depth_effect * normalize(centeredCoord)
    );
    vec2 refractedCoord = coord + d * grad;

    if (u_chromatic_aberration > 0.0) {
        // 色散：按光谱权重分别采样（移植自 Lens.kt 的 dispersion 分支）。
        float dispersionIntensity = u_chromatic_aberration *
            ((centeredCoord.x * centeredCoord.y) / (halfShape.x * halfShape.y));
        vec2 dispersedCoord = d * grad * dispersionIntensity;
        vec4 color = vec4(0.0);

        vec4 red = sampleBackground(refractedCoord + dispersedCoord);
        color.r += red.r / 3.5;
        color.a += red.a / 7.0;

        vec4 orange = sampleBackground(refractedCoord + dispersedCoord * (2.0 / 3.0));
        color.r += orange.r / 3.5;
        color.g += orange.g / 7.0;
        color.a += orange.a / 7.0;

        vec4 yellow = sampleBackground(refractedCoord + dispersedCoord * (1.0 / 3.0));
        color.r += yellow.r / 3.5;
        color.g += yellow.g / 3.5;
        color.a += yellow.a / 7.0;

        vec4 green = sampleBackground(refractedCoord);
        color.g += green.g / 3.5;
        color.a += green.a / 7.0;

        vec4 cyan = sampleBackground(refractedCoord - dispersedCoord * (1.0 / 3.0));
        color.g += cyan.g / 3.5;
        color.b += cyan.b / 3.0;
        color.a += cyan.a / 7.0;

        vec4 blue = sampleBackground(refractedCoord - dispersedCoord * (2.0 / 3.0));
        color.b += blue.b / 3.0;
        color.a += blue.a / 7.0;

        vec4 purple = sampleBackground(refractedCoord - dispersedCoord);
        color.r += purple.r / 7.0;
        color.b += purple.b / 3.0;
        color.a += purple.a / 7.0;

        frag_color = color;
        return;
    }

    frag_color = sampleBackground(refractedCoord);
}
