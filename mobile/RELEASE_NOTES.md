# ملاحظات الإصدار — ملك التوقعات

نصّ «ما الجديد» كما يُلصق في App Store Connect وGoogle Play Console،
ونسخة قصيرة للمساحات الضيّقة. يُحدَّث مع كل رقم إصدار في pubspec.yaml.

## 1.0.0 (5)

### ما الجديد — النص الكامل (App Store / Play)

توقّع بذكاء، واجمع التاج، واجلس على العرش.

• شاشة المباراة لحظةً بلحظة: النتيجة والدقيقة، الهدّافون، الخط الزمني للأحداث، الإحصاءات، التشكيلة على الملعب، والمواجهات السابقة.
• النتيجة على شاشة القفل: مباراتك التي توقّعتها تظهر في النشاط الحيّ والجزيرة الديناميكية مع توقّعك وحكمه — «مضبوط الآن» أو «خارج المسار».
• إشعارات تعرف اللعبة: تذكير قبل الإقفال، تنبيه قبل الانطلاق بتوقّعك، هدفٌ بهدف أثناء المباراة، ثم النتيجة ونقاطك فور الصافرة.
• المجالس: مجالس عامة وخاصة، أدوار مالك ومشرف، طلبات انضمام، رابط دعوة يفتح التطبيق، صورة للمجلس، ومنصّة تتويج بلقب «ملك المجلس».
• التاج الذهبي: عدّل توقّعك قبل الانطلاق، مضاعِف ×5، درع يحمي سلسلتك، وتصفّح بلا إعلانات.
• «ملفي» بتصميم جديد: أرقامك في شريط واحد، سجلّك بثلاثة تبويبات، ودورياتك جنباً إلى جنب.
• ملف عام لكل لاعب: مركزه ودقّته وحصيلته في كل دوري.

### النسخة القصيرة (≤ 500 حرف)

شاشة مباراة لحظةً بلحظة (أحداث، إحصاءات، تشكيلة)، والنتيجة وتوقّعك على شاشة القفل، وإشعارات قبل المباراة وأثناءها وبعدها، ومجالس عامة وخاصة برابط دعوة، والتاج الذهبي بمعزّزاته، و«ملفي» بتصميم جديد.

### للمراجِع في App Store (Review Notes)

- حساب المراجعة: `review@sahfootball.com` / `Review2026!Sah`. ويمكن إنشاء حساب من شاشة التسجيل بأي بريد؛ لا رمز تحقق.
- لا مشتريات داخل التطبيق في هذا الإصدار (التاج الذهبي مغلق من السيرفر ولا مدخل له في الواجهة).
- النشاط الحيّ يظهر عند فتح مباراة جارية من تبويب «مباشر».
- لا محتوى مراهنة: النقاط رمزية ولا تُستبدل بمال.

## 1.0.0 (8)

### ما الجديد — النص الكامل (App Store / Play)

تحديثٌ يجعل التطبيق يتبع دورياتك أنت.

• «مباشر» صار يعرض مباريات دورياتك وحدها، وبشريط الدوريات نفسه الذي في «المباريات» — تختار دورياً في تبويب فتجده مختاراً في البقية.
• «توقّع الجولة» لا يعرض إلا الدوريات التي تتابعها، ويفتح على الدوري الذي اخترته.
• التوقّع صار محصوراً بدورياتك: لوحة كل دوري ومضاعفاته وتذكيراته تتبع متابعتك، فلا تتبعثر نقاطك على لوحات لا تتابعها. وإن أردت دورياً جديداً فزرّ «تابع الدوري» في مكانه.
• إصلاح: كانت إشعارات حسابٍ سابق قد تصل لمن يدخل بعده على الهاتف نفسه. صار الجهاز ينتقل لصاحب الجلسة الحالية عند كل دخول.

### النسخة القصيرة (≤ 500 حرف)

شريط دوريات واحد في «المباريات» و«مباشر» و«توقّع الجولة» باختيار مشترك، ونتائج مباشرة مقصورة على دورياتك، وتوقّعٌ داخل ما تتابعه فقط، وإصلاح وصول إشعارات حساب سابق إلى من يدخل بعده على الهاتف نفسه.

### للمراجِع في App Store (Review Notes)

- حساب المراجعة: `review@sahfootball.com` / `Review2026!Sah`.
- التوقّع يتطلّب متابعة دوري: الحساب الجديد يمرّ برحلة التهيئة التي يختار فيها دورياته، ومن تخطّاها يجد زرّ «تابع دورياً» في «توقّع الجولة» وفي شيت التوقّع.
- لا محتوى مراهنة: النقاط رمزية ولا تُستبدل بمال.

## 1.0.0 (9)

نفس محتوى البناء ٨، ومعه إصلاح واحد يخصّ أندرويد:

• زرّ «اشترك» على أندرويد كان يفشل دائماً (لا Play Billing بعد، والخادم يردّ «الشراء عبر Google Play غير مفعّل بعد»). صار أندرويد يعرض بطاقة «قريباً» بالسعر بدل زرٍّ يعطي رسالة عطل. iOS بلا تغيير — الشراء فيه عبر StoreKit يعمل.

## 1.0.0 (10)

• شاشة «التاج الذهبي» بخلفية خاصة بها: وهجٌ ذهبي خافت خلف التاج على ليلٍ أدفأ، فتُقرأ عرضاً لا صفحة إعدادات.

## 1.1.0 (11) — أول تحديث بعد القبول

الإصدار كله عن لعبةٍ **ثانية** لا شاشةٍ ثالثة: «فريقي». التوقّعات لم
تتغيّر، ونقاطها وعرشها منفصلان تماماً عن الفانتازي (راجع FANTASY.md).

### Promotional Text — عربي (١٣١ حرفاً من ١٧٠)

لعبةٌ جديدة داخل التطبيق: ابنِ فريقك من لاعبي دوريك، ثلاثةٌ من ناديك دائماً، واجمع نقاطهم كل جولة. والتوقّعات كما هي، ولكلٍّ عرشُه.

### Promotional Text — English (167/170)

A second game inside: build your XV from your league, three from your club always, and score every round. Predictions stay as they were — each game has its own throne.

### What's New — عربي (النص الكامل)

«فريقي» — لعبةٌ ثانية كاملة في التبويب الثاني.

التوقّعات تسأل: كم ستنتهي المباراة؟ و«فريقي» تسأل: من سيلعب جيداً هذا الأسبوع؟ مهارتان مختلفتان، ولكلٍّ نقاطُها وعرشُها.

• ابنِ تشكيلتك: ١١ أساسياً و٤ بدلاء بميزانية ١٠٠، وسبع خطط تبدّلها بضغطة، واللاعب يُسحب إلى مكانه على الملعب.
• «فريقي» ناديك: تختاره مرة، وشعاره يصير شعار فريقك، وثلاثةٌ من لاعبيه في تشكيلتك دائماً — وهذا ما يجعلها فريقك لا قائمة أسماء.
• سوق لاعبين بأسعارٍ تتحرّك كل جولة بالطلب والأداء: من اكتشف لاعباً قبل الناس ربح، والبيع يستردّ سعر الشراء ونصف الربح.
• الكابتن ×٢ ونائبه يحلّ محلّه إن لم يلعب، وبدلاؤك يدخلون تلقائياً مكان من غاب.
• انتقالٌ مجاني كل جولة يتراكم حتى خمسة، ووايلد كارد مرتين في الموسم تعيد البناء بلا خصم.
• نقاط الجولة مفصّلةً لاعباً لاعباً: من أين جاءت كل نقطة، ومعها نقاط الإضافة — ٣ و٢ و١ لأفضل ثلاثة في كل مباراة، محسوبةً من أحداث المباراة لا من رأي أحد.
• عرشٌ مستقلّ لـ«فريقي»، وكل صفٍّ فيه بابٌ إلى تشكيلة صاحبه بعد إقفال الجولة — النقاط تقول من فاز، والتشكيلة تقول لماذا.
• شارك تشكيلتك صورةً ببطاقةٍ فيها شعار ناديك ونقاطك.

وفي التوقّعات: المباريات المباشرة انتقلت إلى شاشة «المباريات» في موضعها من الجولة الجارية، فصار التبويب الثاني لفريقك. وأيقونة التطبيق جديدة.

### What's New — English (full)

“فريقي” (My Team) — a complete second game in the second tab.

Predictions ask: how will the match end? My Team asks: who will play well this week? Two different skills, each with its own points and its own throne.

• Build your squad: 11 starters and 4 subs on a 100 budget, seven formations, and players you drag into place on the pitch.
• Your club is your identity: pick it once, its crest becomes your team's crest, and three of its players are always in your squad.
• A player market whose prices move every round with demand and form — spot a player before everyone else and you profit; selling returns your purchase price plus half the gain.
• Captain scores double, the vice-captain steps in if he doesn't play, and your bench subs in automatically for anyone who didn't.
• One free transfer per round, banking up to five, plus two season wildcards that rebuild your squad with no penalty.
• Round points broken down player by player — where every point came from — including bonus points: 3, 2 and 1 for the best three in each match, computed from match events, not anyone's opinion.
• A separate My Team throne, where every row opens that manager's squad once the round has locked: the points say who won, the squad says why.
• Share your squad as an image card with your club crest and your score.

Also: live matches now appear inside the Matches tab, in their place in the current round, freeing the second tab for your team. New app icon.

### النسخة القصيرة (≤ ٥٠٠ حرف)

«فريقي»: لعبة فانتازي كاملة — ١٥ لاعباً بميزانية ١٠٠، ثلاثةٌ من ناديك دائماً، سوقٌ تتحرّك أسعاره كل جولة، كابتن ×٢، انتقالات ووايلد كارد، نقاط الجولة مفصّلة مع نقاط الإضافة ٣/٢/١، وعرشٌ مستقلّ تفتح صفوفه تشكيلات الآخرين. والمباريات المباشرة انتقلت إلى شاشة «المباريات».

### App Review Information — English (paste into App Store Connect)

This is the first update after approval. The prediction game is unchanged; this
release adds a second game in the second tab. Points in both games are symbolic,
cannot be exchanged for money, and there is no betting or wagering of any kind.

Sign in with the provided account, or create a new one from the register screen
with any email (no verification code needed). Sign in with Apple and Google are
also available.

What's new to review — "فريقي" (My Team), the second tab: a fantasy game. A squad
is built from one league's players, so the tab first asks you to follow a league:
if prompted, tap "تابِع دورياً" and follow one of the six domestic leagues whose
squads are loaded — Saudi Pro League, Premier League, La Liga, Serie A,
Bundesliga or Ligue 1 — then save. (The Champions League is predictions-only and
is not offered here.)

Then the full loop: فريقي tab → "ابدأ" → pick the league → pick a club → "ابنِ
تشكيلتي" → on the squad screen tap the "⋯" button (top left of the crest bar) →
"تشكيلة تلقائية" to fill all 15 slots instantly → "احفظ التشكيلة" (save). You can
also fill slots one by one by tapping any "+" on the pitch, which opens the player
market. Round points and the My Team throne are the other two chips at the top.
Squad points are settled after a round's matches finish, so they read 0 for a
squad built today.

Unchanged since the approved version: Matches tab → tap a match card → set a score
→ "أكّد التوقّع" (confirm). Councils: Throne tab → "مجالسي" → create a council and
share its invite code. Account deletion: Settings → Account settings (also at
https://sahfootball.com/delete-account).

A Live Activity appears on the Lock Screen when you open a match that is currently
being played. The separate "مباشر" (Live) tab is gone in this version — live
matches now appear inside the Matches tab, marked in the current round.

In-app purchase: the auto-renewable subscription "التاج الذهبي" (Golden Crown,
com.sahfootball.app.crown.monthly) is the same product approved with the previous
version, unchanged here. It is purchased through StoreKit from Settings → التاج
الذهبي, or from the crown card in "ملفي"; "استعادة المشتريات" (Restore Purchases)
is at the bottom of that same screen. Nothing in the new tab is paid.

### ملاحظات المراجِع — عربي (لسجلّنا لا للصق)

- حساب المراجعة: `review@sahfootball.com` / `Review2026!Sah`.
- «فريقي» لعبة نقاط رمزية: لا شراء بمال، ولا رهان، ولا استبدال.
- نقاط التشكيلة تُحتسب بعد انتهاء مباريات الجولة، فتشكيلةٌ بُنيت اليوم تقرأ صفراً — وهذا صحيح لا عطل.
- تبويب «مباشر» لم يعد موجوداً: المباشر داخل «المباريات».
- الاشتراك هو نفسه المقبول في الإصدار السابق، بلا تغيير.
