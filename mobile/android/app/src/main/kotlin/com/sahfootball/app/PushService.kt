package com.sahfootball.app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * عرض الإشعار والتطبيق مفتوح.
 *
 * أندرويد يعرض حمولة notification تلقائياً **فقط** حين يكون
 * التطبيق في الخلفية. وهي في المقدمة تُسلَّم إلى onMessageReceived
 * هنا ولا يظهر منها شيء — وهذا الافتراضي خطأ في حالتنا تحديداً:
 * تذكير "مباراة تُقفل بعد قليل" يصل غالباً والمستخدم داخل التطبيق
 * في شاشة أخرى، فإخفاؤه يعني ألا يعرف حتى يخرج ويعود.
 *
 * وهو أيضاً ما يجعل المنصتين متطابقتين: عالجت نفس الحالة في iOS
 * بـ userNotificationCenter(willPresent:) في AppDelegate.swift.
 * بلا هذا الملف يصير سلوك التطبيق مختلفاً بين هاتفين، وهو فرق لا
 * يفسّره شيء للمستخدم.
 */
class PushService : FirebaseMessagingService() {

    /**
     * توكن جديد بينما التطبيق يعمل — يحدث عند استعادة نسخة
     * احتياطية أو مسح بيانات التطبيق.
     *
     * لا نرسله للسيرفر من هنا: الإرسال يحتاج توكن مصادقة المستخدم
     * وهو في طبقة Dart، وهذه الخدمة قد تعمل والتطبيق مغلق تماماً.
     * التسجيل يتم عند الإقلاع التالي — Push.enable() تُنادى في كل
     * مرة وتجلب التوكن الحالي أياً كان.
     */
    override fun onNewToken(token: String) {
        android.util.Log.i(TAG, "توكن FCM تغيّر — سيُسجَّل عند الإقلاع التالي")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val notification = message.notification ?: return

        // فتح التطبيق عند الضغط. singleTop في المانيفست يمنع فتح
        // نسخة ثانية فوق القائمة.
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val built = NotificationCompat.Builder(this, MainActivity.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(getColor(R.color.notification_accent))
            .setContentTitle(notification.title)
            .setContentText(notification.body)
            // النص طويل ويُقتطع في السطر الواحد: "ما توقّعت لـ3
            // مباريات تنطلق قريباً. ادخل قبل صافرة البداية" تفقد
            // نصفها الثاني بلا هذا.
            .setStyle(NotificationCompat.BigTextStyle().bigText(notification.body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        // معرّف ثابت: إشعارات التذكير المتتالية تستبدل بعضها بدل أن
        // تتكدّس. المستخدم يهمّه آخر حالة لا تاريخها.
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, built)
    }

    companion object {
        private const val TAG = "push"
        private const val NOTIFICATION_ID = 1
    }
}
