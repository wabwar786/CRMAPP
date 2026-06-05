# --- Prevent R8 from removing needed Java Beans classes ---
-keep class java.beans.** { *; }
-dontwarn java.beans.**

# --- Keep javax.annotation (used by OkHttp3) ---
-keep class javax.annotation.** { *; }
-dontwarn javax.annotation.**

# --- Keep org.conscrypt (used by OkHttp3 Platform) ---
-keep class org.conscrypt.** { *; }
-dontwarn org.conscrypt.**

# --- Keep DOM classes used by Jackson XML serializer ---
-keep class org.w3c.dom.bootstrap.** { *; }
-dontwarn org.w3c.dom.bootstrap.**

# --- Jackson internal reflection support ---
-keep class com.fasterxml.jackson.databind.ext.** { *; }
-dontwarn com.fasterxml.jackson.databind.ext.**
-keepattributes *Annotation*

# (Optional) Keep annotation interfaces, if needed
# -keep @interface *
