
float4x4 g_matWorld;
float4x4 g_matWorldViewProj;

float4 g_eyePos;
float4 g_lightDirWorld;

float g_parallaxScale = 0.04f;
float g_parallaxBias = -0.5f * 0.04f;

float3 g_ambientColor = float3(0.5, 0.5, 0.5);
float3 g_lightColor = float3(1.0, 1.0, 1.0);

// 法線テクスチャのエンコード方式（0=RGB、1=DXT5nm[A=nx,G=ny]）
float g_normalEncoding = 0.0;

//==============================
// テクスチャ
//==============================
texture g_texColor;
texture g_texHeight; // height (R)

sampler2D sColor = sampler_state
{
    Texture = <g_texColor>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D sHeight = sampler_state
{
    Texture = <g_texHeight>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

//==============================
// 頂点 I/O
//==============================
struct VSIn
{
    float4 pos : POSITION;
    float3 normal : NORMAL0;
    float2 uv : TEXCOORD0;
};

struct VSOut
{
    float4 pos : POSITION;
    float3 wp : TEXCOORD0; // world position
    float3 wn : TEXCOORD1; // world normal
    float2 uv : TEXCOORD2;
};

//==============================
// VS
//==============================
VSOut VS(VSIn v)
{
    VSOut o;
    o.pos = mul(v.pos, g_matWorldViewProj);
    o.wp = mul(v.pos, g_matWorld).xyz;
    // 等方スケール前提（非等方スケールなら逆転置行列を使用）
    o.wn = normalize(mul(v.normal, (float3x3) g_matWorld));
    o.uv = v.uv;
    return o;
}

//==============================
// TBN 構築（右手系を保証）
//==============================
void BuildTBN(float3 P, float3 N, float2 uv, out float3 T, out float3 B, out float3 Nn)
{
    float3 dp1 = ddx(P);
    float3 dp2 = ddy(P);
    float2 du1 = ddx(uv);
    float2 du2 = ddy(uv);

    float3 tRaw = dp1 * du2.y - dp2 * du1.y;
    float3 bRaw = dp2 * du1.x - dp1 * du2.x;

    Nn = normalize(N);
    T = normalize(tRaw - Nn * dot(Nn, tRaw)); // N に直交化
    float sign = (dot(cross(Nn, T), normalize(bRaw)) < 0.0) ? -1.0 : 1.0;
    B = normalize(cross(Nn, T)) * sign; // 右手系を維持
}

//==============================
// PS
//==============================
float4 PS(VSOut i) : COLOR
{
    // UV 反転
    float2 baseUV;
    baseUV.x = i.uv.x;
    baseUV.y = i.uv.y;

    // TBN と view（tangent space）
    float3 T, B, Nw;
    BuildTBN(i.wp, i.wn, baseUV, T, B, Nw);
    float3x3 TBN = float3x3(T, B, Nw);

    float3 Vw = g_eyePos.xyz - i.wp;
    float3 Vts = normalize(mul(Vw, transpose(TBN)));

    // Parallax UV オフセット
    float h = tex2D(sHeight, baseUV).r;
    float2 uvP = baseUV + (h * g_parallaxScale + g_parallaxBias) * (Vts.xy / max(abs(Vts.z), 1e-3));

    // サンプル
    float3 albedo = tex2D(sColor, uvP).rgb;

    // Lambert（光線の向き Lw に対して -Lw を使用）
    float3 Lw = normalize(g_lightDirWorld.xyz);
    float NdotL = saturate(dot(i.wn, -Lw));
    float3 diff = g_lightColor * NdotL;

    float3 color = albedo * (g_ambientColor + diff);
    return float4(saturate(color), 1.0);
}

//==============================
// Technique
//==============================
technique Technique_Parallax
{
    pass P0
    {
        VertexShader = compile vs_3_0 VS();
        PixelShader = compile ps_3_0 PS();
    }
}
