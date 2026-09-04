# قواعد التصغير لنسخة المتجر. Flutter وFirebase يضيفان قواعدهما
# تلقائياً؛ ما هنا هو ما يخصّنا فقط.
#
# حزمة إعلانات جوجل: صفوف تُنشأ بالانعكاس، وحذفها يُسقط الإعلان بصمت.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.gms.internal.ads.** { *; }
