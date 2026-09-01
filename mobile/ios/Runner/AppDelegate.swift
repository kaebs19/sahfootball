import AuthenticationServices
import Flutter
import UIKit
import UserNotifications

/// جسر الإشعارات إلى APNs.
///
/// لماذا كود أصلي بدل حزمة firebase_messaging؟ لأن السيرفر يكلّم
/// APNs مباشرة (راجع server/src/services/pushProvider.js)، وFCM في
/// حالة iOS ليس إلا وسيطاً يسلّم لـ APNs بنفس مفتاح p8 الذي نرفعه
/// إليه — فالحزمة تضيف مشروع Firebase وملف إعدادات وSDK كاملاً
/// مقابل صفر قدرة إضافية. ما نحتاجه فعلاً ثلاثة أشياء يوفرها
/// النظام: اطلب الإذن، سجّل، سلّم التوكن — وهي الدوال أدناه.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channel: FlutterMethodChannel?

  /// التوكن حين يصل قبل أن يطلبه Dart.
  ///
  /// السباق حقيقي ويقع فعلاً: didRegister قد يعود خلال أجزاء من
  /// الثانية، بينما شجرة Flutter ما زالت تُبنى ولم يسجّل أحد
  /// مستمعاً بعد. بلا تخزين هنا يضيع التوكن بصمت ولا يُعاد إصداره
  /// إلا في الإقلاع التالي — أي مستخدم بلا إشعارات ليوم كامل بلا
  /// أي خطأ ظاهر.
  private var pendingToken: String?

  /// منسّق تفويض Apple الجاري — يُحتفظ به لأن ASAuthorizationController
  /// لا يمسك مندوبه إلا بمرجع ضعيف: بلا هذا المتغير يتحرر المنسّق
  /// فور خروج الدالة وتُغلق النافذة بلا رد، ويعلق Future في Dart
  /// إلى الأبد.
  private var appleSignIn: AppleSignInCoordinator?

  /// ضغطة على إشعار وصلت قبل أن يصبح Dart جاهزاً.
  ///
  /// هذه ليست الحالة النادرة بل الشائعة: الضغط على إشعار والتطبيق
  /// مغلق يشغّله من الصفر، فيصل didReceive قبل أن تُبنى شجرة
  /// Flutter بوقت طويل. بلا تخزين هنا يفتح التطبيق على شاشته
  /// الافتراضية وكأن المستخدم لم يضغط شيئاً.
  private var pendingOpen: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // نستلم إشعارات المقدمة كي تظهر البانر والتطبيق مفتوح.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // المرسل يأتي من applicationRegistrar لا من الجسر مباشرة:
    // FlutterImplicitEngineBridge يكشف pluginRegistry (للإضافات)
    // و applicationRegistrar (لقنوات التطبيق نفسه)، وهذه الثانية.
    let channel = FlutterMethodChannel(
      name: "sahfootball/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    self.channel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "requestPermission":
        self?.requestPermission(result: result)
      case "pendingToken":
        // Dart يسأل عند الجاهزية عمّا فات قبل أن يستمع.
        result(self?.takePendingToken())
      case "pendingOpen":
        result(self?.takePendingOpen())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // قناة الدخول بحساب Apple. كود أصلي بلا حزمة لنفس منطق قناة
    // الإشعارات أعلاه: ما نحتاجه من AuthenticationServices طلبٌ
    // واحد وتسليم توكن — حزمة كاملة مقابل هذا ثمن بلا مقابل.
    let appleChannel = FlutterMethodChannel(
      name: "sahfootball/apple_signin",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appleChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "signIn":
        self?.startAppleSignIn(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startAppleSignIn(result: @escaping FlutterResult) {
    let coordinator = AppleSignInCoordinator { [weak self] payload, error in
      // تحرير المنسّق قبل الرد: الرد قد يفتح رحلة جديدة فوراً.
      self?.appleSignIn = nil
      if let error = error {
        result(error)
      } else {
        // payload قد يكون nil = إلغاء من المستخدم، وDart يفهم null
        // على أنه إلغاء صامت لا خطأ.
        result(payload)
      }
    }
    appleSignIn = coordinator
    coordinator.start()
  }

  /// يطلب الإذن ثم يسجّل عند القبول. يرجع لـ Dart هل مُنح الإذن.
  ///
  /// الطلب لا يُنادى عند الإقلاع بل من داخل التطبيق بعد أن يفهم
  /// المستخدم لماذا: نافذة iOS تُعرض مرة واحدة في عمر التثبيت،
  /// ورفضها لا يُسترد إلا برحلة يدوية لإعدادات الهاتف لا يقوم بها
  /// أحد عملياً.
  private func requestPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      if let error = error {
        NSLog("[push] فشل طلب الإذن: \(error.localizedDescription)")
      }
      // التسجيل على الخيط الرئيسي شرط من UIKit لا تفصيل أسلوبي.
      DispatchQueue.main.async {
        if granted {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(granted)
      }
    }
  }

  private func takePendingToken() -> String? {
    let token = pendingToken
    pendingToken = nil
    return token
  }

  private func takePendingOpen() -> [String: Any]? {
    let open = pendingOpen
    pendingOpen = nil
    return open
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // APNs يعطي Data خاماً، والسيرفر ينتظر hex — وهذا هو التحويل
    // كاملاً. (سلسلة description للـ Data تعطي "<a1b2 c3d4>"
    // بأقواس ومسافات، وهي فخ قديم يمرّ ويفشل عند آبل لاحقاً.)
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()

    if let channel = channel {
      channel.invokeMethod("onToken", arguments: hex)
    }
    // نحتفظ بنسخة دائماً: invokeMethod أعلاه لا يفشل ظاهرياً لو لم
    // يكن Dart جاهزاً بعد، بل يذهب بلا مستمع.
    pendingToken = hex

    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // الفشل الشائع في التطوير: تشغيل على محاكي بلا حساب مطوّر، أو
    // ملف الاستحقاقات (entitlements) بلا aps-environment.
    NSLog("[push] تعذّر التسجيل في APNs: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// عرض الإشعار والتطبيق مفتوح.
  ///
  /// الافتراضي في iOS هو الإخفاء التام. وهذا خطأ هنا تحديداً:
  /// تذكير "مباراة تُقفل بعد قليل" يصل غالباً والمستخدم داخل
  /// التطبيق في شاشة أخرى، وإخفاؤه يعني ألا يعرف حتى يخرج ويعود.
  /// المستخدم ضغط الإشعار.
  ///
  /// نمرر الحمولة كما هي إلى Dart وهو يقرر الوجهة: القرار "التذكير
  /// يفتح المباريات" منطق منتج لا منطق منصة، ووضعه هنا يعني كتابته
  /// مرتين — مرة بـ Swift ومرة بـ Kotlin — فينحرفان عند أول تعديل.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    // aps حمولة النظام نفسها ولا تعني Dart شيئاً؛ ما يهمنا الحقول
    // التي أضافها السيرفر (type وfixtureId).
    let payload = info
      .filter { $0.key as? String != "aps" }
      .reduce(into: [String: Any]()) { dict, pair in
        if let key = pair.key as? String { dict[key] = pair.value }
      }

    if let channel = channel {
      channel.invokeMethod("onOpen", arguments: payload)
    }
    pendingOpen = payload

    completionHandler()
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }
}

/// رحلة تفويض Apple واحدة من البداية للنهاية.
///
/// صنف مستقل لا امتداد على AppDelegate: المندوب يعيش بعمر الرحلة
/// لا بعمر التطبيق، وحصر الحالة كلها في كائن يُنشأ ويُرمى يمنع
/// تسرب رد قديم إلى رحلة جديدة.
private class AppleSignInCoordinator: NSObject,
  ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

  /// (الحمولة، الخطأ): حمولة بلا خطأ = نجاح، لا حمولة ولا خطأ =
  /// إلغاء من المستخدم، خطأ = فشل حقيقي يستحق رسالة.
  private let completion: ([String: Any]?, FlutterError?) -> Void

  init(completion: @escaping ([String: Any]?, FlutterError?) -> Void) {
    self.completion = completion
  }

  func start() {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    // fullName يصل في أول تفويض فقط في عمر الحساب عند Apple —
    // بعدها تعيد التوكن بلا اسم أبداً، والسيرفر يعرف ذلك ويخزنه
    // من الطلب الأول.
    request.requestedScopes = [.fullName, .email]

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.presentationContextProvider = self
    controller.performRequests()
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    // النافذة المفتاحية عبر المشاهد — التطبيق يستخدم SceneDelegate
    // فلا توجد UIApplication.keyWindow مباشرة.
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene,
         let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
        return window
      }
    }
    return ASPresentationAnchor()
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
          let tokenData = credential.identityToken,
          let token = String(data: tokenData, encoding: .utf8) else {
      completion(nil, FlutterError(
        code: "apple_signin",
        message: "رد Apple بلا identityToken",
        details: nil))
      return
    }

    var payload: [String: Any] = ["identityToken": token]
    if let components = credential.fullName {
      let name = PersonNameComponentsFormatter().string(from: components)
        .trimmingCharacters(in: .whitespaces)
      if !name.isEmpty { payload["displayName"] = name }
    }
    completion(payload, nil)
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    // الإلغاء فعل مقصود لا عطل — يُرد بـ nil فيصمت Dart. غيره
    // (لا شبكة، جهاز بلا Apple ID) خطأ يستحق رسالة.
    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
      completion(nil, nil)
      return
    }
    NSLog("[apple-signin] فشل التفويض: \(error.localizedDescription)")
    completion(nil, FlutterError(
      code: "apple_signin",
      message: error.localizedDescription,
      details: nil))
  }
}
