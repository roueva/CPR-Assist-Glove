# Keep javax.annotation classes
-keep class javax.annotation.** { *; }
-dontwarn javax.annotation.**

# Keep Google error-prone annotations
-keep class com.google.errorprone.annotations.** { *; }
-dontwarn com.google.errorprone.annotations.**

# Keep concurrent annotations
-keep class javax.annotation.concurrent.** { *; }
-dontwarn javax.annotation.concurrent.**
