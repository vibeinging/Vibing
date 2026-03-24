//
//  Shaders.metal
//  Vibing
//
//  Metal 着色器 - 用于终端字符渲染
//

#include <metal_stdlib>
using namespace metal;

// MARK: - 顶点着色器输入/输出结构

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct InstanceData {
    float2 position;     // 屏幕位置 (归一化坐标: 0-1)
    float2 size;         // 字符大小 (归一化坐标: 0-1)
    float4 uvRect;       // 纹理坐标 (x, y, w, h)
    float4 fgColor;      // 前景色 (RGBA)
    float4 bgColor;      // 背景色 (RGBA)
    uint attrs;          // 属性标志
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 fgColor;
    float4 bgColor;
    uint attrs;
};

struct CursorInstanceData {
    float2 position;
    float2 size;
    float4 color;
    uint style;
};

struct CursorVertexOut {
    float4 position [[position]];
    float4 color;
    uint style;
    float2 uv;
};

// MARK: - 字符顶点着色器

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant InstanceData &instance [[buffer(1)]],
                             uint instanceID [[instance_id]]) {
    VertexOut out;

    // 计算最终屏幕位置
    // 基础四边形位置 + 实例位置
    float2 pos = in.position * instance.size + instance.position;

    // 转换到 clip space (-1 到 1)
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    // 翻转 Y 轴 (Metal 使用左下角为原点)
    out.position.y = -out.position.y;

    // 计算纹理坐标
    out.uv = in.position;
    out.uv.x = instance.uvRect.x + in.uv.x * instance.uvRect.z;
    out.uv.y = instance.uvRect.y + (1.0 - in.uv.y) * instance.uvRect.w;

    // 传递颜色和属性
    out.fgColor = instance.fgColor;
    out.bgColor = instance.bgColor;
    out.attrs = instance.attrs;

    return out;
}

// MARK: - 字符片段着色器

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> glyphTexture [[texture(0)]],
                              sampler textureSampler [[sampler(0)]]) {
    // 采样字形纹理
    float4 glyph = glyphTexture.sample(textureSampler, in.uv);

    // 检查属性标志
    bool isBold = (in.attrs & 0x01) != 0;
    bool isDim = (in.attrs & 0x02) != 0;
    bool isItalic = (in.attrs & 0x04) != 0;
    bool isUnderline = (in.attrs & 0x08) != 0;
    bool isBlink = (in.attrs & 0x10) != 0;
    bool isReverse = (in.attrs & 0x20) != 0;
    bool isHidden = (in.attrs & 0x40) != 0;

    // 隐藏属性
    if (isHidden) {
        return in.bgColor;
    }

    // 反色属性
    float4 fg = isReverse ? in.bgColor : in.fgColor;
    float4 bg = isReverse ? in.fgColor : in.bgColor;

    // 应用亮度调整
    if (isDim) {
        fg.rgb *= 0.6;
    } else if (isBold) {
        fg.rgb = mix(fg.rgb, float3(1.0), 0.2);
    }

    // 组合最终颜色
    float4 finalColor = bg;
    finalColor.rgb = mix(bg.rgb, fg.rgb, glyph.a);

    // 处理下划线
    if (isUnderline && in.uv.y < 0.1) {
        finalColor.rgb = mix(finalColor.rgb, fg.rgb, 0.8);
    }

    return finalColor;
}

// MARK: - 光标顶点着色器

vertex CursorVertexOut vertex_cursor(VertexIn in [[stage_in]],
                                     constant CursorInstanceData &instance [[buffer(1)]]) {
    CursorVertexOut out;

    // 计算最终屏幕位置
    float2 pos = in.position * instance.size + instance.position;

    // 转换到 clip space
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.position.y = -out.position.y;

    out.color = instance.color;
    out.style = instance.style;
    out.uv = in.position;

    return out;
}

// MARK: - 光标片段着色器

fragment float4 fragment_cursor(CursorVertexOut in [[stage_in]]) {
    float4 color = in.color;

    // 根据样式调整光标
    switch (in.style) {
        case 0: // Block
            // 全填充
            break;

        case 1: // Underline
            if (in.uv.y > 0.15) {
                color.a = 0.0;
            }
            break;

        case 2: // Bar
            if (in.uv.x < 0.15) {
                // 显示竖条
            } else {
                color.a = 0.0;
            }
            break;

        default:
            break;
    }

    return color;
}
