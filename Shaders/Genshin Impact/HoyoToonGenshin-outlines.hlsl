// vertex
vsOut vert(vsIn v)
{
    vsOut o = (vsOut)0.0f; // cast to 0 to avoid intiailization warnings
    if(_OutlineType == 0)
    {
        return (vsOut)0.0f; // return every value as zero if outline type is set to none
    }
        
    float3 outline_normal;
    outline_normal = mul((float3x3)UNITY_MATRIX_IT_MV, v.tangent.xyz);
    outline_normal.z = -1;
    outline_normal.xy = normalize(outline_normal.xy);
    if(_FallbackOutlines)
    {
        float4 wv_pos = mul(UNITY_MATRIX_MV, v.vertex);
        float fov_width = 1.0f / (rsqrt(abs(wv_pos.z / unity_CameraProjection._m11)));
        // if(!_EnableFOVWidth)fov_width = 1;
        wv_pos.xyz = wv_pos + (outline_normal * fov_width * (v.vertexcol.w * _OutlineWidth * (_Scale * 10)));
        o.pos = mul(UNITY_MATRIX_P, wv_pos);
    }
    else
    {
        _OutlineWidthAdjustScales.w = 1.0f; // this is causing mad problems when you zoom out too far from the model
        float3 view = normalize(_WorldSpaceCameraPos.xyz - mul(unity_ObjectToWorld, v.vertex).xyz);
        float4 wv_pos = mul(UNITY_MATRIX_MV, v.vertex);
        o.pos = wv_pos;

        float fov = 1.0f;
       
            fov = 2.414f / unity_CameraProjection[1].y;
        

        float depth = -wv_pos.z * fov; // fov corrected depth
        
        float2 range;
        float2 scale;

        if(depth < _OutlineWidthAdjustZs.y)
        {
            range = _OutlineWidthAdjustZs.xy;
            scale = _OutlineWidthAdjustScales.xy;
        }
        else
        {
            range = _OutlineWidthAdjustZs.zw;
            scale = _OutlineWidthAdjustScales.zw;
        }

        float offset = lerpByZ(scale.x, scale.y, range.x, range.y, depth);
        float Z = saturate(v.vertexcol.z - 0.5f) * _MaxOutlineZOffset;
        offset = offset * 0.414f * v.vertexcol.w * (_OutlineWidth * _Scale * 100.0f);
        // normal.z = 0.1f;
        // outline_normal = normalize(normal);
        o.pos.xyz = o.pos.xyz + outline_normal * offset ;
        
        o.pos = mul(UNITY_MATRIX_P, o.pos);
    }


    o.uv = float4(v.uv0.xy, v.uv1.xy);
    o.vertexcol = v.vertexcol; 

    o.vertexWS = mul(UNITY_MATRIX_M, v.vertex); 
    o.vertexOS = v.vertex;
    
    return o;
}

// fragment
float4 frag(vsOut i, bool frontFacing : SV_IsFrontFace) : SV_Target
{
    // if frontFacing == 1, use uv.xy, else uv.zw
    float2 newUVs = (frontFacing) ? i.uv.xy : i.uv.zw;

    // sample textures to objects
    float4 mainTex = _MainTex.Sample(sampler_MainTex, vector<half, 2>(i.uv.xy));
    float4 lightmapTex = _LightMapTex.Sample(sampler_LightMapTex, vector<half, 2>(i.uv.xy));


    /* MATERIAL IDS */

    fixed idMasks = lightmapTex.w;

    half materialID = 1;
    if(idMasks >= 0.2 && idMasks <= 0.4 && _UseMaterial4 != 0){
        materialID = 4;
    } 
    else if(idMasks >= 0.4 && idMasks <= 0.6 && _UseMaterial3 != 0){
        materialID = 3;
    }
    else if(idMasks >= 0.6 && idMasks <= 0.8 && _UseMaterial5 != 0){
        materialID = 5;
    }
    else if(idMasks >= 0.8 && idMasks <= 1.0 && _UseMaterial2 != 0){
        materialID = 2;
    }

    float4 glow_colors[5] =
    {
        _OutlineGlowColor,
        _OutlineGlowColor2,
        _OutlineGlowColor3,
        _OutlineGlowColor4,
        _OutlineGlowColor5,
    };


    /* END OF MATERIAL IDS */


    /* ENVIRONMENT LIGHTING */

   float4 environmentLighting = calculateEnvLighting(i.vertexWS);
    
    // ensure environmentLighting does not make outlines greater than 1
    environmentLighting = min(1, environmentLighting);

    /* END OF ENVIRONMENT LIGHTING */


    /* COLOR CREATION */

    // form outline colors
    float4 globalOutlineColor = _OutlineColor;
    if(_UseFaceMapNew == 0){
        if(materialID == 2){
            globalOutlineColor = _OutlineColor2;
        }
        else if(materialID == 3){
            globalOutlineColor = _OutlineColor3;
        }
        else if(materialID == 4){
            globalOutlineColor = _OutlineColor4;
        }
        else if(materialID == 5){
            globalOutlineColor = _OutlineColor5;
        }
    }
    globalOutlineColor.w = 1.0;

    // apply environment lighting
    globalOutlineColor.xyz *= lerp(1, environmentLighting, _EnvironmentLightingStrength).xyz;

    /* END OF COLOR CREATION */

    if(_EnableOutlineGlow) globalOutlineColor.xyz = globalOutlineColor.xyz + (glow_colors[materialID - 1].xyz * _OutlineGlowInt);


    /* CUTOUT TRANSPARENCY */

    if(_MainTexAlphaUse == 1.0) clip(mainTex.w - 0.03 - _MainTexAlphaCutoff);

    /* END OF CUTOUT TRANSPARENCY */


    /* WEAPON */

    if(_UseWeapon != 0.0){
       half2 weaponUVs = (_ProceduralUVs != 0.0) ? (i.vertexOS.zx + 0.25) * 1.5 : i.uv.zw;

        float3 dissolve = 0.0;

        /* DISSOLVE */

        calculateDissolve(dissolve, weaponUVs.xy, 1.0);

        /*buf = dissolveTex < 0.99;

        dissolveTex.x -= 0.001;
        dissolveTex.x = dissolveTex.x < 0.0;
        dissolveTex.x = (buf) ? dissolveTex.x : 0.0;*/

        /* END OF DISSOLVE */

        // apply pattern
        globalOutlineColor.xyz += pow(dissolve.y, 2.0) * _WeaponPatternColor.xyz * 2;
    
        // apply dissolve
        clip(dissolve.x - _ClipAlphaThreshold);
    }
    clip(i.vertexcol.w - 0.1f);
    return globalOutlineColor;
}
