// simple.fx — Parallax + robust TBN + UV flip toggles (ps_3_0)

float4x4 g_matWorldViewProj;
float4x4 g_matWorld;

float4 g_eyePos; // world
float4 g_lightDirWorld; // world, “光線の向き”（上→下なら (0,-1,0) 推奨）

// Parallax
float g_parallaxScale = 0.04f; // 0.02〜0.06
float g_parallaxBias = -0.5f * 0.04;

// Lighting (拡散のみ)
float3 g_ambientColor = float3(0.45, 0.45, 0.45);
float3 g_lightColor = float3(2.0, 2.0, 2.0);
float g_diffuseGain = 2.0;

// UV/Normal 調整トグル
float g_flipU = 0.0; // 1 で左右反転
float g_flipV = 0.0; // 1 で上下反転
float g_flipRed = 0.0; // ノーマルX 反転（必要時）
float g_flipGreen = 0.0; // ノーマルY 反転（必要時）

texture g_texColor;
texture g_texNormal; // tangent-space normal (RGB)
texture g_texHeight; // height in R

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
    float3 wp : TEXCOORD0;
    float3 wn : TEXCOORD1;
    float2 uv : TEXCOORD2;
};

VSOut VS(VSIn v)
{
    VSOut o;
    o.pos = mul(v.pos, g_matWorldViewProj);
    o.wp = mul(v.pos, g_matWorld).xyz;
    // 等方スケール前提（非等方なら逆転置行列へ）
    o.wn = normalize(mul(v.normal, (float3x3) g_matWorld));
    o.uv = v.uv;
    return o;
}

// --- TBN を右手系に補正して構築（面ごとの符号反転を吸収） ---
void BuildTBN(float3 P, float3 N, float2 uv, out float3 T, out float3 B, out float3 Nn)
{
    float3 dp1 = ddx(P), dp2 = ddy(P);
    float2 du1 = ddx(uv), du2 = ddy(uv);

    float3 tRaw = dp1 * du2.y - dp2 * du1.y;
    float3 bRaw = dp2 * du1.x - dp1 * du2.x;

    Nn = normalize(N);
    T = normalize(tRaw - Nn * dot(Nn, tRaw)); // N に直交化
    float sign = (dot(cross(Nn, T), normalize(bRaw)) < 0.0) ? -1.0 : 1.0;
    B = normalize(cross(Nn, T)) * sign; // 右手系を保証
}

float4 PS(VSOut i) : COLOR
{
    // UV 反転トグル
    float2 baseUV;
    baseUV.x = lerp(i.uv.x, 1.0 - i.uv.x, saturate(g_flipU));
    baseUV.y = lerp(i.uv.y, 1.0 - i.uv.y, saturate(g_flipV));

    // TBN と view/light
    float3 T, B, Nw;
    BuildTBN(i.wp, i.wn, baseUV, T, B, Nw);
    float3x3 TBN = float3x3(T, B, Nw);

    float3 Vw = g_eyePos.xyz - i.wp;
    float3 Vts = normalize(mul(Vw, transpose(TBN)));

    // g_lightDirWorld は“光線の向き”
    float3 Lw = normalize(g_lightDirWorld.xyz);
    float3 Lts = mul(Lw, transpose(TBN));

    // Parallax offset
    float h = tex2D(sHeight, baseUV).r;
    float2 uvP = baseUV + (h * g_parallaxScale + g_parallaxBias) * (Vts.xy / max(Vts.z, 1e-3));

    // テクスチャと法線
    float3 albedo = tex2D(sColor, uvP).rgb;
    float3 nTS = tex2D(sNormal, uvP).rgb * 2.0 - 1.0;
    nTS.x = lerp(nTS.x, -nTS.x, saturate(g_flipRed));
    nTS.y = lerp(nTS.y, -nTS.y, saturate(g_flipGreen));
    nTS = normalize(nTS);
    float3 nW = normalize(mul(nTS, TBN));

    // Lambert（光線の向き Lw に対しては -Lw を使う）
    float NdotL = saturate(dot(nW, -Lw));
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
