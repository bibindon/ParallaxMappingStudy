// simple.fx — Parallax Offset Mapping (color + normal + height)
// Tangent basis is built per-pixel from ddx/ddy (ps_3_0 required).

float4x4 g_matWorldViewProj;
float4x4 g_matWorld;

float4 g_eyePos; // world
float4 g_lightDirWorld; // world (directional, normalized)

// Parallax parameters
float g_parallaxScale = 0.04f; // 0.02~0.06
float g_parallaxBias = -0.02f; // typically -0.5 * scale

// Ambient / light color (お好みで)
float3 g_ambientColor = float3(0.38, 0.38, 0.38);
float3 g_lightColor = float3(1.0, 1.0, 1.0);

// Textures
texture g_texColor;
texture g_texNormal; // tangent-space normal (RGB)
texture g_texHeight; // height (use .r)

sampler2D sColor = sampler_state
{
    Texture = <g_texColor>;
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};
sampler2D sNormal = sampler_state
{
    Texture = <g_texNormal>;
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};
sampler2D sHeight = sampler_state
{
    Texture = <g_texHeight>;
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

struct VSIn
{
    float4 pos : POSITION;
    float3 normal : NORMAL0;
    float2 uv : TEXCOORD0;
};

struct VSOut
{
    float4 pos : POSITION;
    float3 worldPos : TEXCOORD0;
    float3 worldNorm : TEXCOORD1;
    float2 uv : TEXCOORD2;
};

VSOut VS(VSIn v)
{
    VSOut o;
    o.pos = mul(v.pos, g_matWorldViewProj);
    o.worldPos = mul(v.pos, g_matWorld).xyz;
    // 等方スケール前提。非等方スケールなら逆転置行列に差し替え。
    o.worldNorm = normalize(mul(v.normal, (float3x3) g_matWorld));
    o.uv = v.uv;
    return o;
}

// TBN を PS で構築
void BuildTBN(float3 wp, float3 wn, float2 uv, out float3 T, out float3 B, out float3 N)
{
    float3 dp1 = ddx(wp);
    float3 dp2 = ddy(wp);
    float2 duv1 = ddx(uv);
    float2 duv2 = ddy(uv);

    float inv = 1.0 / (duv1.x * duv2.y - duv1.y * duv2.x);

    T = normalize((dp1 * duv2.y - dp2 * duv1.y) * inv);
    B = normalize((dp2 * duv1.x - dp1 * duv2.x) * inv);
    N = normalize(wn); // 幾何ノーマル
}

float4 PS(VSOut i) : COLOR
{
    // --- TBN / view & light ---
    float3 T, B, Nw;
    BuildTBN(i.worldPos, i.worldNorm, i.uv, T, B, Nw);

    float3x3 TBN = float3x3(T, B, Nw);

    float3 Vw = (g_eyePos.xyz - i.worldPos);
    float3 Vts = mul(Vw, transpose(TBN)); // to tangent space
    Vts = normalize(Vts);

    float3 Lw = normalize(-g_lightDirWorld.xyz); // directional light
    float3 Lts = mul(Lw, transpose(TBN));

    // --- Parallax offset ---
    float h = tex2D(sHeight, i.uv).r; // use R as height
    float2 parallax = (h * g_parallaxScale + g_parallaxBias) * (Vts.xy / max(Vts.z, 1e-3));
    float2 uvP = i.uv + parallax;

    // --- Sample maps ---
    float3 albedo = tex2D(sColor, uvP).rgb;
    float3 nTS = tex2D(sNormal, uvP).rgb * 2.0 - 1.0;
    nTS = normalize(nTS);

    // 法線をワールドへ戻してからライティング（Lambert）
    float3 nW = normalize(mul(nTS, TBN));

    float NdotL = saturate(dot(nW, Lw));
    float3 diff = g_lightColor * NdotL;

    float3 color = albedo * (g_ambientColor + diff);
    return float4(saturate(color), 1.0);
}

technique Technique_Parallax
{
    pass P0
    {
        VertexShader = compile vs_3_0 VS();
        PixelShader = compile ps_3_0 PS();
    }
}
