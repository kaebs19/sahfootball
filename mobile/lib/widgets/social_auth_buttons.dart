// أزرار الدخول الاجتماعي — كتلة واحدة تظهر في الدخول والتسجيل معاً.
//
// لماذا ودجت مشترك؟ لأن "الدخول" و"التسجيل" عبر مزوّد هوية نفس
// العملية حرفياً في السيرفر (الحساب يُنشأ إن لم يوجد)، فأي فرق
// بين الشاشتين هنا سيكون كذباً بصرياً. والودجت يملك رحلته كاملة:
// مزوّد ← Session ← نجاح/خطأ، والشاشة تتلقى الخطأ لتعرضه في
// موضعها المعتاد تحت النموذج.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/session.dart';
import '../state/social_auth.dart';

class SocialAuthButtons extends StatefulWidget {
  /// تعطيل من الشاشة الأم وقت انشغال نموذجها (دخول بكلمة مرور جارٍ).
  final bool enabled;

  /// خطأ صالح للعرض — الشاشة تضعه حيث تضع أخطاء نموذجها.
  final ValueChanged<String> onError;

  /// نجاح الدخول. الشاشة المدفوعة فوق الجذر (التسجيل) تحتاج
  /// popUntil، وشاشة الدخول (الجذر نفسه) لا تحتاج شيئاً.
  final VoidCallback? onSuccess;

  const SocialAuthButtons({
    super.key,
    required this.enabled,
    required this.onError,
    this.onSuccess,
  });

  @override
  State<SocialAuthButtons> createState() => _SocialAuthButtonsState();
}

class _SocialAuthButtonsState extends State<SocialAuthButtons> {
  // أي زر يعمل الآن؟ لتظهر دوّارة على الزر المضغوط وحده،
  // ويتعطل الآخر — رحلتا تفويض متوازيتان لا معنى لهما.
  _Provider? _busy;

  Future<void> _run(_Provider provider, Future<void> Function() flow) async {
    setState(() => _busy = provider);
    try {
      await flow();
      widget.onSuccess?.call();
    } on SocialAuthException catch (e) {
      widget.onError(e.message);
    } on ApiException catch (e) {
      widget.onError(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _apple() => _run(_Provider.apple, () async {
        final cred = await SocialAuth.apple();
        if (cred == null) return; // ألغى المستخدم — صمت
        if (!mounted) return;
        await context.read<Session>().loginWithApple(
              identityToken: cred.identityToken,
              displayName: cred.displayName,
            );
      });

  Future<void> _google() => _run(_Provider.google, () async {
        final idToken = await SocialAuth.googleIdToken();
        if (idToken == null) return;
        if (!mounted) return;
        await context.read<Session>().loginWithGoogle(idToken);
      });

  @override
  Widget build(BuildContext context) {
    final apple = SocialAuth.appleAvailable;
    final google = SocialAuth.googleAvailable;
    if (!apple && !google) return const SizedBox.shrink();

    final enabled = widget.enabled && _busy == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OrDivider(),
        const SizedBox(height: 18),
        // Apple أولاً على iOS — ترتيب تنص عليه إرشادات آبل حين
        // يجاور زرُها أزرار مزوّدين آخرين.
        if (apple) ...[
          _SocialButton(
            label: 'المتابعة بحساب Apple',
            icon: const Icon(Icons.apple, size: 24, color: Brand.text),
            busy: _busy == _Provider.apple,
            onPressed: enabled ? _apple : null,
          ),
          if (google) const SizedBox(height: 10),
        ],
        if (google)
          _SocialButton(
            label: 'المتابعة بحساب Google',
            icon: const CustomPaint(
              size: Size.square(20),
              painter: _GoogleLogoPainter(),
            ),
            busy: _busy == _Provider.google,
            onPressed: enabled ? _google : null,
          ),
      ],
    );
  }
}

enum _Provider { apple, google }

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool busy;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: Brand.surface,
        side: const BorderSide(color: Brand.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        foregroundColor: Brand.text,
        textStyle: const TextStyle(
          fontFamily: Brand.displayFont,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Brand.text),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 10),
                Text(label),
              ],
            ),
    );
  }
}

/// خط فاصل بكلمة «أو» — يفصل نموذج البريد عن أزرار المزوّدين.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Brand.border, height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('أو',
              style: TextStyle(color: Brand.textFaint, fontSize: 13)),
        ),
        Expanded(child: Divider(color: Brand.border, height: 1)),
      ],
    );
  }
}

/// شعار G الملوّن مرسوماً بالكود — لا أصل صورة ولا حزمة svg لأجل
/// أيقونة واحدة. أربعة أقواس بألوان جوجل الرسمية وشرطة أفقية،
/// والفجوة أعلى يمين الحلقة كما في الشعار الأصلي.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.20; // سماكة الحلقة
    final rect = Rect.fromLTWH(
        w / 2, w / 2, size.width - w, size.height - w);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;

    const deg = 3.1415926535 / 180.0;
    void arc(Color color, double startDeg, double sweepDeg) {
      paint.color = color;
      canvas.drawArc(rect, startDeg * deg, sweepDeg * deg, false, paint);
    }

    // الزوايا بعقارب الساعة من يمين الدائرة (اصطلاح Flutter).
    arc(_blue, -5, 50); // من الشرطة نزولاً لليمين السفلي
    arc(_green, 45, 75); // الأسفل
    arc(_yellow, 120, 85); // اليسار السفلي
    arc(_red, 205, 110); // الأعلى حتى فجوة اليمين العلوي

    // الشرطة: من مركز الدائرة إلى حافتها اليمنى، بسماكة الحلقة.
    // تُرسم LTR دائماً — الشعار علامة تجارية لا نص، لا ينقلب مع RTL
    // (وCustomPaint لا يتأثر بالاتجاه أصلاً).
    final barPaint = Paint()..color = _blue;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width / 2,
        size.height / 2 - w / 2,
        size.width / 2,
        w,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
