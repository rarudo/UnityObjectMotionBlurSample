Shader "Hidden/PostEffect/ObjectMotionBlur"
{
    HLSLINCLUDE
        #pragma target 3.0

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"

        #if SHADER_API_GLES
        struct Attributes
        {
            float4 positionOS       : POSITION;
            float2 uv               : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };
        #else
        struct Attributes
        {
            uint vertexID : SV_VertexID;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };
        #endif

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 texcoord   : TEXCOORD0;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        Varyings Vert(Attributes input)
        {
            Varyings output;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

        #if SHADER_API_GLES
            float4 pos = input.positionOS;
            float2 uv  = input.uv;
        #else
            float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
            float2 uv  = GetFullScreenTriangleTexCoord(input.vertexID);
        #endif

            output.positionCS = pos;
            output.texcoord = uv;
            return output;
        }

        // SourceTexture
        TEXTURE2D(_SourceTex); float4 _SourceTex_TexelSize;

        // Camera depth texture
        TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

        // Camera motion vectors texture
        TEXTURE2D(_MotionVectorTexture); SAMPLER(sampler_MotionVectorTexture);
        float4 _MotionVectorTexture_TexelSize;

        // Packed velocity texture (2/10/10/10)
        TEXTURE2D(_VelocityTex); SAMPLER(sampler_VelocityTex);
        float2 _VelocityTex_TexelSize;

        // NeighborMax texture
        TEXTURE2D(_NeighborMaxTex); SAMPLER(sampler_NeighborMaxTex);
        float2 _NeighborMaxTex_TexelSize;

        // Velocity scale factor
        float _VelocityScale;

        // TileMax filter parameters
        int _TileMaxLoop;
        float2 _TileMaxOffs;

        // Maximum blur radius (in pixels)
        half _MaxBlurRadius;
        float _RcpMaxBlurRadius;

        // Filter parameters/coefficients
        half _LoopCount;


        // -----------------------------------------------------------------------------
        // Prefilter
        float Linear01DepthPPV2(float z)
        {
            float isOrtho = unity_OrthoParams.w;
            float isPers = 1.0 - unity_OrthoParams.w;
            z *= _ZBufferParams.x;
            return (1.0 - isOrtho * z) / (isPers * z + _ZBufferParams.y);
        }

        // Velocity texture setup
        half4 FragVelocitySetup(Varyings i) : SV_Target
        {
            float2 uv = i.texcoord;
            // Sample the motion vector.
            float2 v = SAMPLE_TEXTURE2D(_MotionVectorTexture, sampler_MotionVectorTexture, uv).rg;

            // // Apply the exposure time and convert to the pixel space.
            v *= (_VelocityScale * 0.5) * _MotionVectorTexture_TexelSize.zw;

            // // Clamp the vector with the maximum blur radius.
            v /= max(1.0, length(v) * _RcpMaxBlurRadius);

            // Sample the depth of the pixel.
            half d = Linear01Depth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv),_ZBufferParams);

            // Pack into 10/10/10/2 format.
            return half4((v * _RcpMaxBlurRadius + 1.0) * 0.5, d, 0.0);
        }

        half2 MaxV(half2 v1, half2 v2)
        {
            return dot(v1, v1) < dot(v2, v2) ? v2 : v1;
        }

        // TileMax filter (2 pixel width with normalization)
        half4 FragTileMax1(Varyings i) : SV_Target
        {
            float4 d = _SourceTex_TexelSize.xyxy * float4(-0.5, -0.5, 0.5, 0.5);

            half2 v1 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.xy).rg;
            half2 v2 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.zy).rg;
            half2 v3 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.xw).rg;
            half2 v4 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.zw).rg;

            v1 = (v1 * 2.0 - 1.0) * _MaxBlurRadius;
            v2 = (v2 * 2.0 - 1.0) * _MaxBlurRadius;
            v3 = (v3 * 2.0 - 1.0) * _MaxBlurRadius;
            v4 = (v4 * 2.0 - 1.0) * _MaxBlurRadius;

            return half4(MaxV(MaxV(MaxV(v1, v2), v3), v4), 0.0, 0.0);
        }

        // TileMax filter (2 pixel width)
        half4 FragTileMax2(Varyings i) : SV_Target
        {
            float4 d = _SourceTex_TexelSize.xyxy * float4(-0.5, -0.5, 0.5, 0.5);

            half2 v1 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.xy).rg;
            half2 v2 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.zy).rg;
            half2 v3 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.xw).rg;
            half2 v4 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.zw).rg;

            return half4(MaxV(MaxV(MaxV(v1, v2), v3), v4), 0.0, 0.0);
        }

        // TileMax filter (variable width)
        half4 FragTileMaxV(Varyings i) : SV_Target
        {
            float2 uv0 = i.texcoord + _SourceTex_TexelSize.xy * _TileMaxOffs.xy;

            float2 du = float2(_SourceTex_TexelSize.x, 0.0);
            float2 dv = float2(0.0, _SourceTex_TexelSize.y);

            half2 vo = 0.0;

            UNITY_LOOP
            for (int ix = 0; ix < _TileMaxLoop; ix++)
            {
                UNITY_LOOP
                for (int iy = 0; iy < _TileMaxLoop; iy++)
                {
                    float2 uv = uv0 + du * ix + dv * iy;
                    vo = MaxV(vo, SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, uv).rg);
                }
            }

            return half4(vo, 0.0, 0.0);
        }

        // NeighborMax filter
        half4 FragNeighborMax(Varyings i) : SV_Target
        {
            const half cw = 1.01; // Center weight tweak

            float4 d = _SourceTex_TexelSize.xyxy * float4(1.0, 1.0, -1.0, 0.0);

            half2 v1 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord - d.xy).rg;
            half2 v2 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord - d.wy).rg;
            half2 v3 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord - d.zy).rg;

            half2 v4 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord - d.xw).rg;
            half2 v5 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord).rg * cw;
            half2 v6 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.xw).rg;

            half2 v7 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.zy).rg;
            half2 v8 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.wy).rg;
            half2 v9 = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord + d.xy).rg;

            half2 va = MaxV(v1, MaxV(v2, v3));
            half2 vb = MaxV(v4, MaxV(v5, v6));
            half2 vc = MaxV(v7, MaxV(v8, v9));

            return half4(MaxV(va, MaxV(vb, vc)) * (1.0 / cw), 0.0, 0.0);
        }

        // -----------------------------------------------------------------------------
        // Reconstruction

        // Interleaved gradient function from Jimenez 2014
        // http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare
        float GradientNoise(float2 uv)
        {
            uv = floor(uv * _ScreenParams.xy);
            float f = dot(float2(0.06711056, 0.00583715), uv);
            return frac(52.9829189 * frac(f));
        }

        // Returns true or false with a given interval.
        bool Interval(half phase, half interval)
        {
            return frac(phase / interval) > 0.499;
        }

        // Jitter function for tile lookup
        float2 JitterTile(float2 uv)
        {
            float rx, ry;
            sincos(GradientNoise(uv + float2(2.0, 0.0)) * TWO_PI, ry, rx);
            return float2(rx, ry) * _NeighborMaxTex_TexelSize.xy * 0.25;
        }

        // Velocity sampling function
        half3 SampleVelocity(float2 uv)
        {
            half3 v = SAMPLE_TEXTURE2D_LOD(_VelocityTex, sampler_VelocityTex, uv, 0.0).xyz;
            return half3((v.xy * 2.0 - 1.0) * _MaxBlurRadius, v.z);
        }

        // Reconstruction filter
        half4 FragReconstruction(Varyings i) : SV_Target
        {
            // Color sample at the center point
            const float4 c_p = SAMPLE_TEXTURE2D(_SourceTex, sampler_LinearClamp, i.texcoord);

            // Velocity/Depth sample at the center point
            const float3 vd_p = SampleVelocity(i.texcoord);
            const float l_v_p = max(length(vd_p.xy), 0.5);
            const float rcp_d_p = 1.0 / vd_p.z;

            // NeighborMax vector sample at the center point
            const float2 v_max = SAMPLE_TEXTURE2D(_NeighborMaxTex, sampler_NeighborMaxTex, i.texcoord + JitterTile(i.texcoord)).xy;
            const float l_v_max = length(v_max);
            const float rcp_l_v_max = 1.0 / l_v_max;

            // Escape early if the NeighborMax vector is small enough.
            if (l_v_max < 2.0) return c_p;

            // Use V_p as a secondary sampling direction except when it's too small
            // compared to V_max. This vector is rescaled to be the length of V_max.
            const half2 v_alt = (l_v_p * 2.0 > l_v_max) ? vd_p.xy * (l_v_max / l_v_p) : v_max;

            // Determine the sample count.
            const half sc = floor(min(_LoopCount, l_v_max * 0.5));


            // Loop variables (starts from the outermost sample)
            const half dt = 1.0 / sc;
            const half t_offs = (GradientNoise(i.texcoord) - 0.5) * dt;
            float t = 1.0 - dt * 0.5;
            float count = 0.0;

            // Background velocity
            // This is used for tracking the maximum velocity in the background layer.
            float l_v_bg = max(l_v_p, 1.0);

            // Color accumlation
            float4 acc = 0.0;

            [loop]
            while (t > dt * 0.25)
            {
                // Sampling direction (switched per every two samples)
                const float2 v_s = Interval(count, 4.0) ? v_alt : v_max;

                // Sample position (inverted per every sample)
                const float t_s = (Interval(count, 2.0) ? -t : t) + t_offs;

                // Distance to the sample position
                const float l_t = l_v_max * abs(t_s);

                // UVs for the sample position
                const float2 uv0 = i.texcoord + v_s * t_s * _SourceTex_TexelSize.xy;
                const float2 uv1 = i.texcoord + v_s * t_s * _VelocityTex_TexelSize.xy;

                // Color sample
                const float3 c = SAMPLE_TEXTURE2D_LOD(_SourceTex, sampler_LinearClamp, uv0, 0.0).rgb;

                // Velocity/Depth sample
                const float3 vd = SampleVelocity(uv1);

                // Background/Foreground separation
                const float fg = saturate((vd_p.z - vd.z) * 20.0 * rcp_d_p);

                // Length of the velocity vector
                const float l_v = lerp(l_v_bg, length(vd.xy), fg);

                // Sample weight
                // (Distance test) * (Spreading out by motion) * (Triangular window)
                const float w = saturate(l_v - l_t) / l_v * (1.2 - t);

                // Color accumulation
                acc += half4(c, 1.0) * w;

                // Update the background velocity.
                l_v_bg = max(l_v_bg, l_v);

                // Advance to the next sample.
                t = Interval(count, 2.0) ? t - dt : t;
                count += 1.0;
            }

            // Add the center sample.
            acc += float4(c_p.rgb, 1.0) * (1.2 / (l_v_bg * sc * 2.0));

            //return half4(0,0,1,1);
            return half4(acc.rgb / acc.a, c_p.a);
        }

    ENDHLSL

    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        // (0) Velocity texture setup
        Pass
        {
            Name "Velocity Texture Setup"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragVelocitySetup

            ENDHLSL
        }

        // (1) TileMax filter (2 pixel width with normalization)
        Pass
        {
            Name "TileMax Filter (2px normalized)"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragTileMax1

            ENDHLSL
        }

        //  (2) TileMax filter (2 pixel width)
        Pass
        {
            Name "TileMax filter (2px)"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragTileMax2

            ENDHLSL
        }

        // (3) TileMax filter (variable width)
        Pass
        {
            Name "TileMax Filter (variable)"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragTileMaxV

            ENDHLSL
        }

        // (4) NeighborMax filter
        Pass
        {
            Name "NeighborMax Filter"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragNeighborMax

            ENDHLSL
        }

        // (5) Reconstruction filter
        Pass
        {
            Name "Reconstruction Filter"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragReconstruction

            ENDHLSL
        }
    }
}
