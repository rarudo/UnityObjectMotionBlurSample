using UnityEngine;
using UnityEngine.Rendering.Universal;

public class ObjectMotionBlurFeature : ScriptableRendererFeature
{
    public Shader shader;
    private ObjectMotionBlurPass _objectMotionBlurPass;

    public override void Create()
    {
        if (shader == null) return;

        _objectMotionBlurPass = new ObjectMotionBlurPass(shader)
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(_objectMotionBlurPass);
    }
}
