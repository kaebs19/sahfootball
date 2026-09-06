// StoreBridge — الجسر بين متجر الجهاز (StoreKit اليوم، Play لاحقاً)
// وسيرفرنا.
//
// لمن يعرف StoreKit: هذا مكان `Transaction.updates` في التطبيق كله.
// المستمع يُنشأ مرة واحدة عند الإقلاع لا داخل شاشة الشراء، لسببين:
//   • معاملة تكتمل والشاشة مغلقة (موافقة وليّ الأمر، انقطاع، تجديد
//     شهري) تصل إلى هنا وتُصرَف إلى السيرفر ولا تضيع.
//   • StoreKit يعيد تسليم كل معاملة لم تُنهَ (finish) عند الإقلاع
//     التالي، فمستمعٌ دائم يعني أن فشل الشبكة مرة ليس فقدان شراء.
//
// قاعدة الأمان: لا نمنح شيئاً هنا. المعاملة تُرسل إلى السيرفر، هو
// يتحقّق من توقيع آبل ويمنح، ونحن نعتمد ما يردّ به (Premium.adopt).
// ولا نُنهي المعاملة (completePurchase) إلا بعد أن يقبلها السيرفر —
// فإن تعذّر الوصول إليه بقيت معلّقة وأعادها StoreKit لاحقاً.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../api/api_client.dart';
import '../state/premium.dart';

/// نتيجة محاولة شراء أو استعادة كما تراها الشاشة.
enum StoreOutcome { granted, restoredNothing, cancelled, pending, failed }

class StoreBridge extends ChangeNotifier {
  final ApiClient api;
  final Premium premium;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// هل متجر الجهاز متاح لهذه المنصّة؟ اليوم iOS فقط: أندرويد يأتي
  /// مع ربط Play Billing، وحتى ذلك الحين يسلك مساره القديم.
  bool get supported => Platform.isIOS;

  bool _available = false;
  bool get available => supported && _available;

  /// منتجات المتجر بأسعارها المحلية — آبل تشترط عرض سعرها هي.
  final Map<String, ProductDetails> products = {};

  /// المعرّفات التي طلبناها ولم يجدها المتجر — لإخفاء بطاقاتها.
  final Set<String> missing = {};

  /// المنتج الجاري شراؤه، لتعطيل زرّه وحده.
  String? busyProductId;

  /// آخر خطأ يستحق العرض، تقرؤه الشاشة ثم تمسحه.
  String? lastError;

  /// مكتمل بعد كل معاملة تُعالَج — الشاشة تنتظره لتعرض النتيجة.
  final _outcomes = StreamController<StoreOutcome>.broadcast();
  Stream<StoreOutcome> get outcomes => _outcomes.stream;

  StoreBridge(this.api, this.premium) {
    if (!supported) return;
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      lastError = 'تعذّر الاتصال بالمتجر';
      notifyListeners();
    });
  }

  /// يسأل المتجر عن المنتجات. يُنادى حين تُفتح شاشة الشراء.
  Future<void> loadProducts(Set<String> ids) async {
    if (!supported || ids.isEmpty) return;
    _available = await _iap.isAvailable();
    if (!_available) {
      notifyListeners();
      return;
    }
    final res = await _iap.queryProductDetails(ids);
    products
      ..clear()
      ..addEntries(res.productDetails.map((p) => MapEntry(p.id, p)));
    missing
      ..clear()
      ..addAll(res.notFoundIDs);
    if (res.notFoundIDs.isNotEmpty) {
      debugPrint('[store] منتجات غير موجودة في المتجر: ${res.notFoundIDs}');
    }
    notifyListeners();
  }

  /// يبدأ الشراء. الاشتراك «غير استهلاكي» في اصطلاح المكوّن الإضافي،
  /// والحزم استهلاكية. النتيجة تصل عبر [outcomes] لا كقيمة راجعة،
  /// لأن ورقة الدفع نافذة نظام لا نتحكّم بزمنها.
  Future<void> buy(String productId, {required bool consumable}) async {
    final product = products[productId];
    if (product == null) {
      lastError = 'المنتج غير متاح في المتجر الآن';
      notifyListeners();
      _outcomes.add(StoreOutcome.failed);
      return;
    }
    busyProductId = productId;
    lastError = null;
    notifyListeners();
    final param = PurchaseParam(productDetails: product);
    try {
      final started = consumable
          ? await _iap.buyConsumable(purchaseParam: param)
          : await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        busyProductId = null;
        notifyListeners();
        _outcomes.add(StoreOutcome.failed);
      }
    } catch (e) {
      busyProductId = null;
      lastError = 'تعذّر بدء الشراء';
      notifyListeners();
      _outcomes.add(StoreOutcome.failed);
    }
  }

  /// الاستعادة — شرط آبل. المتجر يعيد إرسال المعاملات السارية عبر
  /// نفس المجرى بحالة restored، فتُصرَف كما يُصرَف الشراء.
  Future<void> restore() async {
    if (!available) {
      // لا متجر: نسأل سيرفرنا عمّا يعرفه عن هذا الحساب.
      final ent = await api.restorePurchases(platform: 'apple');
      premium.adopt(ent);
      _outcomes.add(ent.premium ? StoreOutcome.granted : StoreOutcome.restoredNothing);
      return;
    }
    _restoreSawAny = false;
    await _iap.restorePurchases();
    // StoreKit لا يقول «انتهيت»: نمهله لحظة، فإن لم تصل معاملة
    // نبلّغ أن لا شيء يُستعاد. مهلة قصيرة لأن التسليم محلي وفوري.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!_restoreSawAny) {
      final ent = await api.restorePurchases(platform: 'apple');
      premium.adopt(ent);
      _outcomes.add(ent.premium ? StoreOutcome.granted : StoreOutcome.restoredNothing);
    }
  }

  bool _restoreSawAny = false;

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _outcomes.add(StoreOutcome.pending);
          break;
        case PurchaseStatus.canceled:
          busyProductId = null;
          notifyListeners();
          _outcomes.add(StoreOutcome.cancelled);
          break;
        case PurchaseStatus.error:
          busyProductId = null;
          lastError = p.error?.message ?? 'فشل الشراء';
          notifyListeners();
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          _outcomes.add(StoreOutcome.failed);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.status == PurchaseStatus.restored) _restoreSawAny = true;
          await _deliver(p);
          break;
      }
    }
  }

  /// يسلّم المعاملة الموقّعة إلى السيرفر ويعتمد ردّه.
  Future<void> _deliver(PurchaseDetails p) async {
    try {
      final ent = await api.verifyPurchase(
        platform: 'apple',
        productId: p.productID,
        receipt: p.verificationData.serverVerificationData,
      );
      premium.adopt(ent);
      // الآن فقط نُنهي المعاملة: السيرفر سجّلها ومنح ما يترتّب عليها.
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      busyProductId = null;
      lastError = null;
      notifyListeners();
      _outcomes.add(StoreOutcome.granted);
    } on ApiException catch (e) {
      // لا نُنهي المعاملة: تبقى معلّقة ويعيدها StoreKit عند الإقلاع
      // التالي، فيُعاد الإرسال بلا تدخّل من المستخدم.
      busyProductId = null;
      lastError = e.message;
      notifyListeners();
      _outcomes.add(StoreOutcome.failed);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _outcomes.close();
    super.dispose();
  }
}
