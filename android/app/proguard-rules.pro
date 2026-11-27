# tonEMU release-build rules (R8 is on by default for Flutter release builds).
#
# LibretroDroid is reached BY NAME in three ways, all of which R8 would otherwise break:
#   - VideoOptions:  Class.forName("...ShaderConfig$Default/Sharp/CRT/LCD") + INSTANCE field
#   - SaturnSupport: GLRetroViewData.setControllerConfigs, GLRetroView.setControllerType
#   - GameSession:   GLRetroView.getGLRetroEvents and the "FrameRendered" event class name
#                    (matched with getSimpleName(), so the class must not be renamed)
# Its native (JNI) code also calls back into its Kotlin classes by name.
# Without these rules the release app still builds and starts, but video filters, Saturn
# controls, save-readiness and the core itself can silently fail (release builds only).

-keep class com.swordfish.libretrodroid.** { *; }
-keepnames class com.swordfish.libretrodroid.**
-dontwarn com.swordfish.libretrodroid.**

# Keeps Kotlin object INSTANCE fields / sealed subclasses and enum names intact for reflection.
-keepattributes InnerClasses,EnclosingMethod,Signature,*Annotation*,Kotlin*

# Flutter references Play Core (deferred components) even when the app does not use it;
# without this R8 fails the release build with "Missing class com.google.android.play.core...".
-dontwarn com.google.android.play.core.**