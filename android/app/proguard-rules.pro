# Keep kotlinx.serialization-generated serializers for the content models.
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.sambulosendas1.biblecrossword.**$$serializer { *; }
-keepclassmembers class com.sambulosendas1.biblecrossword.** { *** Companion; }
-keepclasseswithmembers class com.sambulosendas1.biblecrossword.** { kotlinx.serialization.KSerializer serializer(...); }
