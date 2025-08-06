# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }

# AndroidX and standard libraries
-keep class androidx.** { *; }
-keep class com.google.** { *; }

# Needed if you use reflection, ads, file pickers, etc.
-keepclassmembers class * {
    public <init>(android.content.Context);
    *** *(...);
}
