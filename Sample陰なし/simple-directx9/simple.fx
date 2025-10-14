float4x4 g_matWorld;
float4x4 g_matWorldViewProj;

float4 g_eyePos;
float4 g_lightDirWorld;

float g_parallaxScale = 0.08f;
float g_parallaxBias = -1.0f * 0.04f;

float3 g_ambientColor = float3(0.5, 0.5, 0.5);
float3 g_lightColor = float3(1.0, 1.0, 1.0);

texture g_texColor;
texture g_texHeight;

sampler2D sColor
{
    Texture = <g_texColor>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D sHeight
{
    Texture = <g_texHeight>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

void VS(float4 inPos            : POSITION0,
        float3 inNormal         : NORMAL0,
        float2 inUV             : TEXCOORD0,

        out float4 outPos       : POSITION0,
        out float3 outWorldPos  : TEXCOORD0,
        out float3 outWorldNorm : TEXCOORD1,
        out float2 outUV        : TEXCOORD2)
{
    outPos = mul(inPos, g_matWorldViewProj);
    outWorldPos = mul(inPos, g_matWorld).xyz;

    float3x3 world3x3 = (float3x3) g_matWorld;
    outWorldNorm = normalize(mul(inNormal, world3x3));

    outUV = inUV;
}

//-------------------------------------------------------------
// TBN 構築
//-------------------------------------------------------------
void BuildTBN(float3 worldPos,
              float3 worldNorm,
              float2 uv,

              out float3 tangentVec,
              out float3 binormalVec,
              out float3 normWorld);

void PS(float3 inWorldPos  : TEXCOORD0,
        float3 inWorldNorm : TEXCOORD1,
        float2 inUV        : TEXCOORD2,

        out float4 outColor: COLOR0)
{
    float3 tangentVec, binormalVec, normWorld;

    BuildTBN(inWorldPos, inWorldNorm, inUV,
             tangentVec, binormalVec, normWorld);

    float3x3 TBNMatrix = float3x3(tangentVec, binormalVec, normWorld);

    float3 viewDirWorld = g_eyePos.xyz - inWorldPos;
    float3 viewDirTangentSpace = normalize(mul(viewDirWorld, transpose(TBNMatrix)));

    // Parallax UV オフセット
    float height = tex2D(sHeight, inUV).r;
    float parallaxAmt = height * g_parallaxScale + g_parallaxBias;
    float2 uvParallax = inUV + parallaxAmt * (viewDirTangentSpace.xy / max(abs(viewDirTangentSpace.z), 0.001f));

    // Lambert Lighting
    float3 albedo = tex2D(sColor, uvParallax).rgb;

    float3 lightDirWorld = normalize(g_lightDirWorld.xyz);
    float nDotL = saturate(dot(normWorld, -lightDirWorld));
    float3 diffuse = g_lightColor * nDotL;

    float3 color = albedo * (g_ambientColor + diffuse);
    outColor = float4(saturate(color), 1.0);
}

void BuildTBN(float3 worldPos,
              float3 worldNorm,
              float2 uv,

              out float3 tangentVec,
              out float3 binormalVec,
              out float3 normWorld)
{
    float3 ddxPos = ddx(worldPos);
    float3 ddyPos = ddy(worldPos);
    float2 ddxUV = ddx(uv);
    float2 ddyUV = ddy(uv);

    float3 rawTan = ddxPos * ddyUV.y - ddyPos * ddxUV.y;
    float3 rawBin = ddyPos * ddxUV.x - ddxPos * ddyUV.x;

    normWorld = normalize(worldNorm);
    tangentVec = normalize(rawTan - normWorld * dot(normWorld, rawTan));

    float signFlag = dot(cross(normWorld, tangentVec), normalize(rawBin));

    float handedness = 0.f;
    if (signFlag < 0.0)
    {
        handedness = -1.0;
    }
    else
    {
        handedness = 1.0;
    }

    binormalVec = normalize(cross(normWorld, tangentVec)) * handedness;
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
