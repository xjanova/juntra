# Flutter Play Core stubs — required even when not using deferred components,
# otherwise R8 strips classes the Flutter engine references reflectively.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Keep all Kotlin coroutine internals (Dio's underlying http client).
-dontwarn kotlinx.**
-keep class kotlinx.** { *; }

# Keep enums (Riverpod uses reflection on a few sealed classes).
-keepclassmembers enum * { *; }
