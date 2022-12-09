using UnityEngine;
using UnityEngine.Rendering;

public class PostProcessingMotionBlur
{
    enum Pass
    {
        VelocitySetup,
        TileMax1,
        TileMax2,
        TileMaxV,
        NeighborMax,
        Reconstruction
    }

    class ShaderIDs
    {
        internal static readonly int VelocityScale = Shader.PropertyToID("_VelocityScale");
        internal static readonly int MaxBlurRadius = Shader.PropertyToID("_MaxBlurRadius");
        internal static readonly int RcpMaxBlurRadius = Shader.PropertyToID("_RcpMaxBlurRadius");
        internal static readonly int VelocityTex = Shader.PropertyToID("_VelocityTex");
        internal static readonly int Tile2RT = Shader.PropertyToID("_Tile2RT");
        internal static readonly int Tile4RT = Shader.PropertyToID("_Tile4RT");
        internal static readonly int Tile8RT = Shader.PropertyToID("_Tile8RT");
        internal static readonly int TileMaxOffs = Shader.PropertyToID("_TileMaxOffs");
        internal static readonly int TileMaxLoop = Shader.PropertyToID("_TileMaxLoop");
        internal static readonly int TileVRT = Shader.PropertyToID("_TileVRT");
        internal static readonly int NeighborMaxTex = Shader.PropertyToID("_NeighborMaxTex");
        internal static readonly int LoopCount = Shader.PropertyToID("_LoopCount");
    }

    private void CreateTemporaryRT(CommandBuffer cmd, RenderTextureDescriptor rtDesc, int nameID, int width,
        int height,
        RenderTextureFormat rtFormat)
    {
        rtDesc.width = width;
        rtDesc.height = height;
        rtDesc.colorFormat = rtFormat;
        cmd.GetTemporaryRT(nameID, rtDesc, FilterMode.Point);
    }

    public void ObjectMotionBlur(
        CommandBuffer cmd,
        Material material,
        RenderTargetIdentifier source,
        RenderTargetIdentifier destination,
        RenderTextureDescriptor desc)
    {
        var objectMotionBlur = VolumeManager.instance.stack.GetComponent<ObjectMotionBlur>();

        const float kMaxBlurRadius = 5f;
        var vectorRTFormat = RenderTextureFormat.RGHalf;
        var packedRTFormat = SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.ARGB2101010)
            ? RenderTextureFormat.ARGB2101010
            : RenderTextureFormat.ARGB32;

        // var desc = GetCompatibleDescriptor();
        var width = desc.width;
        var height = desc.height;
        desc.colorFormat = packedRTFormat;

        // Calculate the maximum blur radius in pixels.
        // int maxBlurPixels = (int)(kMaxBlurRadius * context.height / 100);
        int maxBlurPixels = (int)(kMaxBlurRadius * height / 100);

        // Calculate the TileMax size.
        // It should be a multiple of 8 and larger than maxBlur.
        int tileSize = ((maxBlurPixels - 1) / 8 + 1) * 8;

        // Pass 1 - Velocity/depth packing
        var velocityScale = objectMotionBlur.shutterAngle.value / 360f;
        material.SetFloat(ShaderIDs.VelocityScale, velocityScale);
        material.SetFloat(ShaderIDs.MaxBlurRadius, maxBlurPixels);
        material.SetFloat(ShaderIDs.RcpMaxBlurRadius, 1f / maxBlurPixels);


        int vbuffer = ShaderIDs.VelocityTex;
        CreateTemporaryRT(cmd, desc, vbuffer, width, height, packedRTFormat);
        // cmd.Blit(BuiltinRenderTextureType.None, vbuffer, material, (int)Pass.VelocitySetup);
        Blit(cmd, BuiltinRenderTextureType.None, vbuffer, material, (int)Pass.VelocitySetup);

        // Pass 2 - First TileMax filter (1/2 downsize)
        int tile2 = ShaderIDs.Tile2RT;
        CreateTemporaryRT(cmd, desc, tile2, width / 2, height / 2, vectorRTFormat);
        Blit(cmd, vbuffer, tile2, material, (int)Pass.TileMax1);

        // Pass 3 - Second TileMax filter (1/2 downsize)
        int tile4 = ShaderIDs.Tile4RT;
        CreateTemporaryRT(cmd, desc, tile4, width / 4, height / 4, vectorRTFormat);
        Blit(cmd, tile2, tile4, material, (int)Pass.TileMax2);
        cmd.ReleaseTemporaryRT(tile2);

        // Pass 4 - Third TileMax filter (1/2 downsize)
        int tile8 = ShaderIDs.Tile8RT;
        CreateTemporaryRT(cmd, desc, tile8, width / 8, height / 8, vectorRTFormat);
        Blit(cmd, tile4, tile8, material, (int)Pass.TileMax2);
        cmd.ReleaseTemporaryRT(tile4);

        // Pass 5 - Fourth TileMax filter (reduce to tileSize)
        var tileMaxOffs = Vector2.one * (tileSize / 8f - 1f) * -0.5f;
        material.SetVector(ShaderIDs.TileMaxOffs, tileMaxOffs);
        material.SetFloat(ShaderIDs.TileMaxLoop, (int)(tileSize / 8f));
        int tile = ShaderIDs.TileVRT;
        CreateTemporaryRT(cmd, desc, tile, width / tileSize, height / tileSize, vectorRTFormat);
        Blit(cmd, tile8, tile, material, (int)Pass.TileMaxV);
        cmd.ReleaseTemporaryRT(tile8);

        // Pass 6 - NeighborMax filter
        int neighborMax = ShaderIDs.NeighborMaxTex;
        CreateTemporaryRT(cmd, desc, neighborMax, width / tileSize, height / tileSize, vectorRTFormat);
        Blit(cmd, tile, neighborMax, material, (int)Pass.NeighborMax);
        cmd.ReleaseTemporaryRT(tile);

        // Pass 7 - Reconstruction pass
        material.SetFloat(ShaderIDs.LoopCount, Mathf.Clamp(objectMotionBlur.sampleCount.value / 2, 1, 64));
        Blit(cmd, source, destination, material, (int)Pass.Reconstruction);

        cmd.ReleaseTemporaryRT(vbuffer);
        cmd.ReleaseTemporaryRT(neighborMax);
    }

    private void Blit(CommandBuffer cmd, RenderTargetIdentifier source, RenderTargetIdentifier destination,
        Material material, int passIndex = 0)
    {
        cmd.SetGlobalTexture(Shader.PropertyToID("_SourceTex"), source);
        cmd.Blit(source, destination, material, passIndex);
    }
}
