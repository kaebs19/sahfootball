// أصوات «فريقي» — أربعة أصوات تصاحب الفعل، لا موسيقى ولا زينة.
//
// كل صوت يجيب سؤالاً واحداً بلا أن تقرأ العين شيئاً:
//
//   pop      وقع اللاعب في مكانه
//   swoosh   بدأ السحب
//   save     حُفظت
//   error    القاعدة رفضت
//
// والصمت هو الأصل: لا صوت لفتح شاشة ولا لتمرير قائمة. الصوت
// الذي يُسمع في كل لمسة يصير ضجيجاً يُطفأ من إعدادات الهاتف،
// فيضيع معه الصوت الذي كان يعني شيئاً.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum Sfx { pop, swoosh, save, error }

class FantasySounds {
  FantasySounds._();

  static const _files = {
    Sfx.pop: 'sounds/pop_drop.mp3',
    Sfx.swoosh: 'sounds/swoosh_drag.mp3',
    Sfx.save: 'sounds/chime_save.mp3',
    Sfx.error: 'sounds/error_buzz.mp3',
  };

  /// مشغّلٌ لكل صوت لا مشغّلٌ واحد: صوتان متتاليان (سحبٌ ثم وقوع)
  /// يقطع أحدهما الآخر لو تشاركا مشغّلاً، فيُسمع نصف نقرة.
  static final _players = <Sfx, AudioPlayer>{};

  /// يُطفأ كلّه بسطر واحد — لإعدادٍ قادم أو لاختبارٍ صامت.
  static bool enabled = true;

  static Future<void> play(Sfx sound) async {
    if (!enabled) return;
    try {
      final player = _players.putIfAbsent(sound, () {
        final p = AudioPlayer();
        // لا يوقف موسيقى المستخدم ولا يستولي على جلسة الصوت:
        // نقرةٌ في لعبة لا تستحقّ إسكات ما يسمعه.
        p.setReleaseMode(ReleaseMode.stop);
        p.setPlayerMode(PlayerMode.lowLatency);
        return p;
      });
      await player.stop();
      await player.play(AssetSource(_files[sound]!), volume: 0.55);
    } catch (err) {
      // فشل الصوت لا يُسقط فعلاً: من رفضت قاعدةٌ تشكيلته يجب أن
      // يرى الرسالة حتى لو صمت الجهاز (مكتومٌ، أو جلسة صوت
      // مشغولة، أو محاكٍ بلا مخرج).
      debugPrint('[sfx] $sound failed: $err');
    }
  }

  static Future<void> dispose() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
  }
}
