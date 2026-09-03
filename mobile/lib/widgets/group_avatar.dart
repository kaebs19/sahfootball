// صورة المجلس — دائرة واحدة في كل مكان يُعرض فيه مجلس.
//
// التدهور بالترتيب: صورة المجلس إن رُفعت، وإلا شعار دوريه إن كان
// مقيّداً بدوري، وإلا أيقونة تقول نوعه (عام أو خاص). ثلاث شاشات
// كانت ترسم هذا بثلاث طرق؛ الآن واحدة، فلا يبدو المجلس نفسه مختلفاً
// بين القائمة والترويسة والدعوة.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../config.dart';
import '../models/group.dart';

class GroupAvatar extends StatelessWidget {
  final Group group;
  final double size;

  /// حدّ ذهبي خفيف — للترويسة والدعوة حيث الصورة هي البطل.
  final bool ringed;

  const GroupAvatar({
    super.key,
    required this.group,
    this.size = 38,
    this.ringed = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = group;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.fill,
        border: ringed ? Border.all(color: Brand.crownWash(0.4), width: 2) : null,
        image: g.imageUrl != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(
                    AppConfig.absoluteUrl(g.imageUrl!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: g.imageUrl != null
          ? null
          : g.leagueLogo != null
              ? CachedNetworkImage(
                  imageUrl: AppConfig.absoluteUrl(g.leagueLogo!),
                  width: size * 0.58,
                  height: size * 0.58,
                  errorWidget: (_, _, _) => Icon(Icons.groups_outlined,
                      size: size * 0.48, color: Brand.textMuted),
                )
              : Icon(
                  g.isPublic ? Icons.public : Icons.groups_outlined,
                  size: size * 0.48,
                  color: Brand.textMuted,
                ),
    );
  }
}
