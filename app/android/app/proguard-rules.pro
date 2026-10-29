# flutter_local_notifications uses Gson reflection for scheduled notifications
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
# Play Billing
-keep class com.android.vending.billing.** { *; }
