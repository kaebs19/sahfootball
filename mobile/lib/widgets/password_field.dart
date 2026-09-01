// حقل كلمة مرور بعين إظهار/إخفاء — موحّد في الدخول والتسجيل
// والاستعادة وكل موضع يُكتب فيه سر.
//
// لماذا ودجت لا سطر obscureText في كل شاشة؟ لأن الإظهار حالة،
// والحالة تحتاج StatefulWidget، وتكرار ذلك في خمسة مواضع يعني
// خمس نسخ ستتباعد (عين هنا بلا عين هناك). النسخة الواحدة تُبقي
// السلوك واحداً: العين رمادية خافتة، والضغط يبدّلها، والنص يبقى
// LTR لأن كلمات المرور لاتينية الطابع كالبريد.
import 'package:flutter/material.dart';

import '../brand.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;

  /// AutofillHints.password للدخول وAutofillHints.newPassword
  /// للتسجيل والاستعادة — التمييز هو ما يجعل iOS يعرض الكلمة
  /// المحفوظة في الأولى ويقترح كلمة قوية في الثانية.
  final List<String>? autofillHints;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.validator,
    this.onFieldSubmitted,
    this.textInputAction,
    this.autofillHints,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      style: const TextStyle(color: Brand.text),
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        helperStyle: const TextStyle(color: Brand.textFaint),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscured = !_obscured),
          icon: Icon(
            _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 21,
            color: Brand.textFaint,
          ),
          // قارئ الشاشة يسمع فعل الزر لا شكله.
          tooltip: _obscured ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
        ),
      ),
    );
  }
}
