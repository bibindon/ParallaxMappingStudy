// simple.fx — Parallax Offset Mapping (brighten knobs + green-flip)
// ps_3_0 / TBN from ddx/ddy

float4x4 g_matWorldViewProj;
float4x4 g_matWorld;

float4 g_eyePos; // world
float4 g_lightDirWorld; // world (directional, normalized)

// === Parallax params ===
float g_parallaxScale = 0.04f; // 0.02~0.06
float g_parallaxBias = -0.02f; // usually -0.5*scale

// === Lighting knobs (明るさ調整用) ===
float3 g_ambientColor = float3(0.25, 0.25, 0.25); // ベースの明るさ
float3 g_lightColor = float3(3.0, 3.0, 3.0); // 直射の色
float g_diffuseGain = 2.0; // 直射を増やす倍率（1.0~3.0）
float g_flipGreen = 0.0; // 1.0 にすると Normal.Y を反転（OpenGL系法線マップ対策）

// Textures
texture g_texColor;
texture g_texNormal; // tangent-space normal (RGB in [0,1])
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
    // 等方スケール前提（非等方なら逆転置行列に変更）
    o.worldNorm = normalize(mul(v.normal, (float3x3) g_matWorld));
    o.uv = v.uv;
    return o;
}

// TBN を PS で構築
void BuildTBN(float3 wp, float3 wn, float2 uv, out float3 T, out float3 B, out float3 N)
{
    float3 dp1 = ddx(wp), dp2 = ddy(wp);
    float2 du1 = ddx(uv), du2 = ddy(uv);
    float inv = 1.0 / (du1.x * du2.y - du1.y * du2.x);
    T = normalize((dp1 * du2.y - dp2 * du1.y) * inv);
    B = normalize((dp2 * du1.x - dp1 * du2.x) * inv);
    N = normalize(wn);
}

float4 PS(VSOut i) : COLOR
{
    // --- build TBN, view/light ---
    float3 T, B, Nw;
    BuildTBN(i.worldPos, i.worldNorm, i.uv, T, B, Nw);
    float3x3 TBN = float3x3(T, B, Nw);

    float3 Vw = (g_eyePos.xyz - i.worldPos);
    float3 Vts = normalize(mul(Vw, transpose(TBN)));
    float3 Lw = normalize(-g_lightDirWorld.xyz); // light travels along -dir
    float3 Lts = mul(Lw, transpose(TBN));

    // --- parallax offset ---
    float h = tex2D(sHeight, i.uv).r;
    float2 uvP = i.uv + (h * g_parallaxScale + g_parallaxBias) * (Vts.xy / max(Vts.z, 1e-3));

    // --- sample maps ---
    float3 albedo = tex2D(sColor, uvP).rgb;
    float3 nTS = tex2D(sNormal, uvP).rgb * 2.0 - 1.0;

    // Gチャンネル反転トグル（OpenGL法線→DirectX変換）
    nTS.y = lerp(nTS.y, -nTS.y, saturate(g_flipGreen));

    nTS = normalize(nTS);
    float3 nW = normalize(mul(nTS, TBN));

    // Lambert
    float NdotL = saturate(dot(nW, Lw));
    float3 diff = g_lightColor * (NdotL * g_diffuseGain);

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
