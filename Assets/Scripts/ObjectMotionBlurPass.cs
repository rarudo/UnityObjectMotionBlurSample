using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using GraphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat;

public class ObjectMotionBlurPass : ScriptableRenderPass
{
    private readonly ProfilingSampler _objectMotionBlurSampler = new("Object Motion Blur");
    private readonly PostProcessingMotionBlur _postProcessingMotionBlur;
    private static readonly int _tmpColorBufferID = Shader.PropertyToID("_TempColorBuffer");
    private Material _material;

    public ObjectMotionBlurPass(Shader shader)
    {
        // MotionVector要求する
        ConfigureInput(ScriptableRenderPassInput.Motion);

        _postProcessingMotionBlur = new PostProcessingMotionBlur();
        _material = CoreUtils.CreateEngineMaterial(shader);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;
        // SceneViewではブラーをかけない
        if (cameraData.cameraType == CameraType.SceneView) return;
        var component = VolumeManager.instance.stack.GetComponent<ObjectMotionBlur>();
        if (!component.IsActive())
        {
            return;
        }

        CommandBuffer cmd = CommandBufferPool.Get();

        using (new ProfilingScope(cmd, _objectMotionBlurSampler))
        {
            var descriptor = cameraData.cameraTargetDescriptor;
            descriptor.depthStencilFormat = GraphicsFormat.None;
            descriptor.depthBufferBits = 0;
            var colorTarget = cameraData.renderer.cameraColorTargetHandle;

            // カメラの画像を_TempColorBufferにコピーする
            cmd.GetTemporaryRT(_tmpColorBufferID, descriptor);
            cmd.Blit(colorTarget.nameID, _tmpColorBufferID);

            // オブジェクトモーションブラー
            _postProcessingMotionBlur.ObjectMotionBlur(cmd, _material, _tmpColorBufferID, colorTarget, descriptor);

            cmd.ReleaseTemporaryRT(_tmpColorBufferID);
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}
