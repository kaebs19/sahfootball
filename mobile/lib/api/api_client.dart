// api_client — كل حديث التطبيق مع السيرفر يمر من هنا.
//
// البنية من ثلاث قطع، لكل منها سبب وجود:
//
// 1. TokenStore: يحفظ التوكنات في التخزين الآمن للنظام (Keychain في
//    iOS) — التوكن مفتاح حساب المستخدم، ولا يوضع في ملف عادي أبداً.
//
// 2. Interceptor: يحقن Authorization في كل طلب، وعند 401 يجدد التوكن
//    ويعيد الطلب بشفافية. لماذا هنا وليس في كل شاشة؟ لأن انتهاء
//    التوكن (كل 15 دقيقة) حدث بنية تحتية لا يخص واجهة المستخدم —
//    الشاشة تطلب "المباريات القادمة" ولا يعنيها كيف بقيت الجلسة حية.
//    نفس فلسفة RequestInterceptor في Alamofire.
//
// 3. دوال API مسماة: الشاشات تستدعي client.upcomingFixtures() ولا
//    تعرف المسارات ولا شكل الـ JSON — لو تغير السيرفر نعدل هنا فقط.
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models/fixture.dart';
import '../models/leaderboard_entry.dart';
import '../models/live_fixture.dart';
import '../models/prediction.dart';
import '../models/profile_stats.dart';
import '../models/user.dart';

/// خطأ موجه للعرض: message جاهزة بالعربية (السيرفر يرسل أخطاءه
/// بالعربية أصلاً في حقل error، ونلتقطها كما هي).
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class TokenStore {
  static const _kAccess = 'sah_access_token';
  static const _kRefresh = 'sah_refresh_token';
  final _storage = const FlutterSecureStorage();

  // كاش بالذاكرة: قراءة Keychain عملية IPC بطيئة نسبياً، ولا نريدها
  // في مسار كل طلب شبكة. القرص للبقاء بين التشغيلات، والذاكرة للسرعة.
  String? accessToken;
  String? refreshToken;

  Future<void> load() async {
    accessToken = await _storage.read(key: _kAccess);
    refreshToken = await _storage.read(key: _kRefresh);
  }

  Future<void> save({required String access, required String refresh}) async {
    accessToken = access;
    refreshToken = refresh;
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  bool get hasSession => refreshToken != null;
}

class ApiClient {
  final TokenStore tokens = TokenStore();
  late final Dio _dio;

  /// تستدعيها Session عند موت الجلسة نهائياً — فشل التجديد، أو
  /// إيقاف الحساب، أو حذفه. تعيد المستخدم لشاشة الدخول من أي
  /// مكان كان، ومعها سبب صالح للعرض حين يكون هناك سبب: "انتهت
  /// جلستك" و"أوقفت الإدارة حسابك" حدثان مختلفان تماماً عند
  /// المستخدم، وإخفاء الفرق يجعله يعيد المحاولة بلا فائدة.
  void Function([String? reason])? onSessionExpired;

  // تجديد "برحلة واحدة": لو انطلقت 3 طلبات معاً وكلها رجعت 401،
  // نجدد مرة واحدة وينتظر الجميع نفس النتيجة. بدون هذا القفل سترسل
  // 3 طلبات تجديد متسابقة، وبما أن refresh token يُستبدل عند كل
  // استخدام (rotation)، الطلب الثاني سيفشل ويُسقط الجلسة خطأً.
  Future<bool>? _refreshInFlight;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokens.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final response = error.response;
        final alreadyRetried = error.requestOptions.extra['retried'] == true;

        // حساب أوقفته الإدارة.
        //
        // السيرفر يرد 403 لا 401 عمداً، والفرق جوهري هنا: التوكن
        // سليم تماماً ولا فائدة من تجديده، فلو عاملناه كـ 401
        // لدخلنا في حلقة /refresh لا تنتهي. نخرج المستخدم فوراً
        // ونمرر له سبب الإيقاف كما كتبه الأدمن.
        final data = response?.data;
        if (response?.statusCode == 403 &&
            data is Map &&
            data['code'] == 'ACCOUNT_SUSPENDED') {
          await tokens.clear();
          onSessionExpired?.call(
              data['error'] as String? ?? 'تم إيقاف حسابك، تواصل مع الإدارة');
          return handler.next(error);
        }

        // الحساب حُذف بينما توكنه ما زال حياً.
        if (response?.statusCode == 401 &&
            data is Map &&
            data['code'] == 'ACCOUNT_NOT_FOUND') {
          await tokens.clear();
          onSessionExpired?.call('لم يعد هذا الحساب موجوداً');
          return handler.next(error);
        }

        // نحاول التجديد فقط لو: الرد 401، وعندنا refresh token،
        // ولم نجرب مع هذا الطلب من قبل (منعاً لحلقة لا نهائية)،
        // وليس الطلب نفسه طلب مصادقة (فشل الدخول 401 طبيعي وليس
        // انتهاء جلسة).
        final isAuthPath = error.requestOptions.path.startsWith('/api/auth/');
        if (response?.statusCode == 401 &&
            tokens.refreshToken != null &&
            !alreadyRetried &&
            !isAuthPath) {
          final refreshed = await _refreshTokens();
          if (refreshed) {
            // نعيد الطلب الأصلي نفسه بالتوكن الجديد.
            final opts = error.requestOptions;
            opts.extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
            try {
              final retryResponse = await _dio.fetch(opts);
              return handler.resolve(retryResponse);
            } on DioException catch (e) {
              return handler.next(e);
            }
          } else {
            await tokens.clear();
            onSessionExpired?.call();
          }
        }
        handler.next(error);
      },
    ));
  }

  Future<bool> _refreshTokens() {
    // القفل: أول من يصل ينشئ عملية التجديد، والبقية ينتظرونها.
    _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  Future<bool> _doRefresh() async {
    try {
      // Dio جديد بلا interceptors: لو استعملنا _dio نفسه ورجع
      // التجديد 401 لدخلنا في تجديد داخل تجديد.
      final bare = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final res = await bare.post('/api/auth/refresh',
          data: {'refreshToken': tokens.refreshToken});
      await tokens.save(
        access: res.data['accessToken'] as String,
        refresh: res.data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// تحويل أخطاء dio لـ ApiException برسالة صالحة للعرض مباشرة.
  Never _throwReadable(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) {
      throw ApiException(data['error'] as String,
          statusCode: e.response?.statusCode);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      throw const ApiException('تعذر الاتصال بالخادم — تحقق من الشبكة');
    }
    throw ApiException('حدث خطأ غير متوقع (${e.response?.statusCode ?? ''})',
        statusCode: e.response?.statusCode);
  }

  // ---------------------------- المصادقة ----------------------------

  Future<User> login({required String email, required String password}) async {
    try {
      final res = await _dio.post('/api/auth/login',
          data: {'email': email, 'password': password});
      await tokens.save(
        access: res.data['accessToken'] as String,
        refresh: res.data['refreshToken'] as String,
      );
      return User.fromJson(res.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  Future<User> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final res = await _dio.post('/api/auth/register', data: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.isNotEmpty)
          'displayName': displayName,
      });
      await tokens.save(
        access: res.data['accessToken'] as String,
        refresh: res.data['refreshToken'] as String,
      );
      return User.fromJson(res.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  Future<User> me() async {
    try {
      final res = await _dio.get('/api/auth/me');
      return User.fromJson(res.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  Future<void> logout() async {
    // نبطل التوكن في السيرفر، لكن فشل الشبكة لا يمنع الخروج محلياً —
    // المستخدم طلب الخروج وسيخرج، والتوكن اليتيم سينتهي وحده بعد 30 يوماً.
    try {
      await _dio.post('/api/auth/logout',
          data: {'refreshToken': tokens.refreshToken});
    } catch (_) {}
    await tokens.clear();
  }

  // ---------------------------- البيانات ----------------------------

  Future<List<Fixture>> upcomingFixtures() async {
    try {
      final res = await _dio.get('/api/fixtures/upcoming');
      return (res.data['fixtures'] as List)
          .map((j) => Fixture.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  /// مباريات يوم محدد. الصيغة YYYY-MM-DD واليوم محسوب بتوقيت الرياض
  /// في السيرفر — مباراة 12:30 فجراً تُنسب ليومها المحلي لا لـ UTC.
  Future<List<Fixture>> fixturesByDate(DateTime day) async {
    final d = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    try {
      final res = await _dio.get('/api/fixtures', queryParameters: {'date': d});
      return (res.data['fixtures'] as List)
          .map((j) => Fixture.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  /// حالة تبويب "مباشر": الجاري الآن، والمباراة القادمة، ونتائج اليوم.
  ///
  /// طلب واحد لا ثلاثة: الشاشة تُحدَّث كل عشرين ثانية، وثلاثة طلبات
  /// في كل دورة تضاعف الحمل بلا سبب — الأجزاء الثلاثة تُقرأ معاً
  /// دائماً ولا معنى لتحديث أحدها دون الآخر.
  Future<LiveState> liveState() async {
    try {
      final res = await _dio.get('/api/fixtures/live');
      return LiveState.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  Future<List<Prediction>> myPredictions() async {
    try {
      final res = await _dio.get('/api/predictions/mine');
      return (res.data['predictions'] as List)
          .map((j) => Prediction.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  Future<void> submitPrediction({
    required int fixtureId,
    required int home,
    required int away,
  }) async {
    try {
      await _dio.post('/api/predictions', data: {
        'fixtureId': fixtureId,
        'home': home,
        'away': away,
      });
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  /// إحصاءات ملفي: الرتبة والدقة والسلسلة وشكل الأداء الأخير.
  Future<ProfileStats> profileStats() async {
    try {
      final res = await _dio.get('/api/profile/stats');
      return ProfileStats.fromJson(res.data['stats'] as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }

  Future<List<LeaderboardEntry>> leaderboard() async {
    try {
      final res = await _dio.get('/api/leaderboard');
      return (res.data['leaderboard'] as List)
          .map((j) => LeaderboardEntry.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _throwReadable(e);
    }
  }
}
