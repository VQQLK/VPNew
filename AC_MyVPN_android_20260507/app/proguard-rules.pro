# MyVPN Xray ProGuard rules

# AndroidLibXrayLite — JNI классы нельзя обфусцировать
-keep class libxray.** { *; }
-keep class com.xray.** { *; }

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# org.json — используется для парсинга конфига
-keep class org.json.** { *; }

# AndroidX
-keep class androidx.** { *; }
