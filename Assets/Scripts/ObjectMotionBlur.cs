using UnityEngine.Rendering;

[System.Serializable, VolumeComponentMenu("Custom/Object Motion Blur")]
public class ObjectMotionBlur : VolumeComponent
{
    public ClampedFloatParameter shutterAngle = new ClampedFloatParameter(0, 0, 360);

    public ClampedIntParameter sampleCount = new ClampedIntParameter(8, 4, 32);

    public bool IsActive()
    {
        return  active && shutterAngle.overrideState && shutterAngle.value > 0 && sampleCount.value > 0;
    }
}
