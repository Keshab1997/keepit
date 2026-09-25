# flutter_local_notifications stores scheduled notifications with Gson.
# Without these rules R8 strips generic type info and scheduled reminders
# crash / disappear after a reboot in release builds.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.gson.**

# package:jni (pulled in by path_provider_android) registers JNI natives by
# exact class name. If R8 renames or strips these, dlopen/FindClass fails with
# an Error (not an Exception) and the process dies at the first path_provider
# call during startup. Keep them exactly as published.
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
