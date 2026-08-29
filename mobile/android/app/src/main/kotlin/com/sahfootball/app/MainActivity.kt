package com.sahfootball.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * جسر الإشعارات إلى FCM.
 *
 * اسم القناة وأسماء الدوال مطابقة حرفياً لنسخة iOS في
 * ios/Runner/AppDelegate.swift، ولهذا تبقى lib/state/push.dart
 * ملفاً واحداً بلا أي تفرّع على المنصة. أي اختلاف في التسمية هنا
 * كان سيفرض شرطاً في Dart لكل نداء.
 *
 * ولماذا FCM هنا بينما iOS يكلّم APNs مباشرة؟ لأنه لا سبيل آخر
 * للوصول لجهاز أندرويد إطلاقاً — جوجل تحتكر التسليم. في iOS كان
 * الوسيط اختيارياً فتجنّبناه، وهنا ليس كذلك.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /**
     * حمولة إشعار ضُغط عليه قبل أن يجهز Dart.
     *
     * الضغط على إشعار والتطبيق مغلق يشغّله من الصفر، فتصل النية
     * (Intent) قبل أن تُبنى شجرة Flutter بوقت طويل.
     */
    private var pendingOpen: Map<String, Any?>? = null

    /** ينتظر نتيجة نافذة الصلاحية (أندرويد 13+) ليرد على Dart. */
    private var pendingResult: MethodChannel.Result? = null

    /** التوكن إن وصل قبل أن يطلبه Dart — نفس منطق iOS. */
    private var pendingToken: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        readOpenIntent(intent)
    }

    /**
     * التطبيق كان يعمل وضُغط إشعار: أندرويد لا ينشئ نشاطاً جديداً
     * (launchMode=singleTop) بل يسلّم النية هنا. بلا هذه الدالة
     * يعمل الانتقال حين يكون التطبيق مغلقاً ولا يعمل حين يكون
     * مفتوحاً — وهو أسوأ من ألا يعمل أبداً لأنه يبدو عشوائياً.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readOpenIntent(intent)
    }

    /**
     * حقول السيرفر (type وfixtureId) تصل كإضافات على النية:
     * FCM يضعها هناك سواء عرض الإشعار بنفسه أو عرضته PushService.
     */
    private fun readOpenIntent(intent: Intent?) {
        val extras = intent?.extras ?: return
        val type = extras.getString("type") ?: return

        val payload = mapOf(
            "type" to type,
            "fixtureId" to extras.getString("fixtureId")
        )
        pendingOpen = payload
        channel?.invokeMethod("onOpen", payload)
    }

    /**
     * قناة الإشعارات. أندرويد 8+ يرفض عرض أي إشعار لا قناة له،
     * ولو تركنا الأمر لـ FCM لأنشأ قناة احتياطية اسمها
     * "Miscellaneous" — وهذا اسم يراه المستخدم في إعدادات هاتفه
     * ولا يدل على شيء، ولا يستطيع تمييزه ليوقفه أو يبقيه.
     *
     * قناة واحدة لا قناتان (تذكير ونتيجة) عمداً: التحكم التفصيلي
     * موجود أصلاً داخل التطبيق في شاشة الإشعارات، وقناتان تعنيان
     * مكانين متضاربين لنفس الإعداد — يوقف المستخدم التذكير من
     * إعدادات الهاتف ويبقى مفتوحاً في التطبيق، فلا يفهم أيهما يحكم.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "تنبيهات المباريات",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "تذكير قبل إقفال التوقع، ونتيجة توقعاتك بعد المباراة."
        }

        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        this.channel = channel
        // مرجع ثابت تستعمله PushService حين يتغيّر التوكن والتطبيق
        // يعمل. الخدمة تعمل في سياق منفصل ولا وصول لها إلى النشاط.
        liveChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestPermission(result)
                "pendingToken" -> {
                    result.success(pendingToken)
                    pendingToken = null
                }
                "pendingOpen" -> {
                    result.success(pendingOpen)
                    pendingOpen = null
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * قبل أندرويد 13 لا صلاحية تُطلب: الإشعارات مسموحة ما لم
     * يوقفها المستخدم من الإعدادات، فنمضي مباشرة لجلب التوكن.
     */
    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            fetchToken()
            result.success(true)
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            fetchToken()
            result.success(true)
            return
        }

        pendingResult = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST
        )
    }

    override fun onDestroy() {
        if (liveChannel === channel) liveChannel = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) fetchToken()

        // الرد مرة واحدة فقط: نداء result مرتين يرمي في Flutter.
        pendingResult?.success(granted)
        pendingResult = null
    }

    /**
     * FCM يعطي التوكن غير متزامن، وقد يفشل (لا خدمات جوجل على
     * الجهاز، أو google-services.json مفقود). الفشل يُسجّل ولا
     * يُسقط شيئاً — التطبيق يعمل كاملاً بلا إشعارات.
     */
    private fun fetchToken() {
        FirebaseMessaging.getInstance().token
            .addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    android.util.Log.w(TAG, "تعذّر جلب توكن FCM", task.exception)
                    return@addOnCompleteListener
                }
                val token = task.result ?: return@addOnCompleteListener
                // نحتفظ بنسخة دائماً: لو لم يكن Dart جاهزاً بعد،
                // يذهب invokeMethod بلا مستمع ويضيع التوكن بصمت.
                pendingToken = token
                channel?.invokeMethod("onToken", token)
            }
    }

    companion object {
        private const val CHANNEL = "sahfootball/push"
        private const val TAG = "push"
        private const val PERMISSION_REQUEST = 4001

        /** يطابق default_notification_channel_id في AndroidManifest. */
        const val CHANNEL_ID = "malik_default"

        /**
         * القناة الحية إن كان التطبيق يعمل، وإلا null.
         *
         * تُمسح في onDestroy لأن الاحتفاظ بها بعد موت النشاط يسرّب
         * المحرّك كاملاً، والنداء عليها حينها يذهب إلى العدم.
         */
        var liveChannel: MethodChannel? = null
            private set
    }
}
