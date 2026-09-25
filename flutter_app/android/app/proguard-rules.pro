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

# WorkManager arrives transitively (Firebase/AdMob stack) and creates its Room
# database reflectively: Class.forName("androidx.work.impl.WorkDatabase_Impl")
# + getDeclaredConstructor().newInstance(). Room 2.x's bundled rule keeps the
# class NAME but not its members, so R8 full mode strips the no-arg constructor
# and every release build dies at process start with:
#   RuntimeException: Failed to create an instance of androidx.work.impl.WorkDatabase
# thrown from androidx.startup.InitializationProvider before Flutter loads.
# Keep the reflective targets constructible (class * extends matches both
# WorkDatabase_Impl and any future generated Room database).
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.room3.RoomDatabase { <init>(); }
# WorkManager instantiates InputMerger implementations reflectively too.
-keep class * extends androidx.work.InputMerger { <init>(); }
