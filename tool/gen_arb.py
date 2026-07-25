#!/usr/bin/env python3
"""Generate app_en.arb / app_ar.arb / app_ur.arb from one aligned table.

Three hand-maintained ARB files drift: a key added to English and forgotten in
Urdu shows an English string to an Urdu reader, and nothing fails. Generating
all three from one table makes a missing translation impossible to express.

Each entry is (key, en, ar, ur, placeholders). Placeholders are ICU names that
must appear in all three languages; the generator asserts that they do.
"""
import json
import pathlib
import re
import sys

L10N = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "lib/l10n")

# key: (en, ar, ur, {placeholder: type})
T: dict[str, tuple] = {}


def add(key, en, ar, ur, ph=None):
    assert key not in T, f"duplicate key {key}"
    T[key] = (en, ar, ur, ph or {})


# ---------------------------------------------------------------- common ----
add("appTitle", "Prayer Lock", "قفل الصلاة", "پریئر لاک")
add("actionRetry", "Try again", "أعد المحاولة", "دوبارہ کوشش کریں")
add("actionCancel", "Cancel", "إلغاء", "منسوخ کریں")
add("actionSave", "Save", "حفظ", "محفوظ کریں")
add("actionDelete", "Delete", "حذف", "حذف کریں")
add("actionClear", "Clear", "مسح", "صاف کریں")
add("actionDone", "Done", "تم", "مکمل")
add("actionContinue", "Continue", "متابعة", "جاری رکھیں")
add("actionSkip", "Skip", "تخطي", "چھوڑ دیں")
add("commonNotSet", "Not set", "غير محدد", "مقرر نہیں")
add("commonOff", "Off", "مغلق", "بند")
add("commonNoData", "No data", "لا توجد بيانات", "کوئی ڈیٹا نہیں")
add("commonNothingYet", "Nothing here yet.", "لا يوجد شيء بعد.",
    "ابھی یہاں کچھ نہیں ہے۔")
add("commonLoadFailed", "Could not load: {error}", "تعذر التحميل: {error}",
    "لوڈ نہیں ہو سکا: {error}", {"error": "String"})

# ------------------------------------------------------------- dashboard ----
add("dashboardTodaysPrayers", "TODAY'S PRAYERS", "صلوات اليوم",
    "آج کی نمازیں")
add("dashboardItIsTimeFor", "IT IS TIME FOR", "حان وقت", "وقت ہو گیا ہے")
add("dashboardNext", "NEXT: {prayer}", "التالية: {prayer}",
    "اگلی: {prayer}", {"prayer": "String"})
add("dashboardWhatIsNext", "what is next", "ما التالي", "آگے کیا ہے")
add("dashboardCompletedOfTotal", "{completed} of {total}",
    "{completed} من {total}", "{total} میں سے {completed}",
    {"completed": "int", "total": "int"})
add("dashboardCompleted", "Completed", "مكتملة", "مکمل")
add("dashboardRemaining", "Remaining", "متبقية", "باقی")
add("dashboardYourPrayers", "Your prayers", "صلواتك", "آپ کی نمازیں")
add("dashboardConfirmPrayer", "I completed this prayer", "أكملت هذه الصلاة",
    "میں نے یہ نماز پڑھ لی")
add("dashboardVerifyQaza", "Verify qaza prayer", "تأكيد صلاة القضاء",
    "قضا نماز کی تصدیق کریں")
add("dashboardMarkExcused", "Mark as excused", "تسجيل كعذر",
    "معذور کے طور پر نشان زد کریں")
add("dashboardBothRecorded", "Both prayers are recorded when you confirm.",
    "تُسجَّل الصلاتان عند التأكيد.",
    "تصدیق پر دونوں نمازیں درج ہو جائیں گی۔")
add("dashboardQazaExplain",
    "The on-time window has passed. Verifying now records this as a qaza "
    "(make-up) prayer.",
    "انتهى وقت الأداء. التأكيد الآن يسجلها صلاة قضاء.",
    "وقت گزر چکا ہے۔ اب تصدیق کرنے سے یہ قضا نماز کے طور پر درج ہوگی۔")
add("dashboardFajrBeforeSunrise",
    "Fajr must be prayed before sunrise. After sunrise it is recorded as late.",
    "يجب أداء الفجر قبل الشروق. بعد الشروق تُسجَّل متأخرة.",
    "فجر طلوعِ آفتاب سے پہلے پڑھنی ہے۔ اس کے بعد تاخیر شمار ہوگی۔")
add("dashboardSetLocation", "Set your location", "حدد موقعك",
    "اپنا مقام مقرر کریں")
add("dashboardSetLocationBody",
    "Prayer times depend on where you are. Choose a location to get started.",
    "تعتمد أوقات الصلاة على موقعك. اختر موقعًا للبدء.",
    "نماز کے اوقات آپ کے مقام پر منحصر ہیں۔ شروع کرنے کے لیے مقام منتخب کریں۔")
add("dashboardChooseLocation", "Choose location", "اختر الموقع",
    "مقام منتخب کریں")

# ------------------------------------------------------- prayer list tile ----
add("tileUntilBoundary", "Until {boundary}", "حتى {boundary}",
    "{boundary} تک", {"boundary": "String"})
add("tileVerifyNow", "Verify now", "أكّد الآن", "ابھی تصدیق کریں")
add("tileQazaAvailable", "Qaza available", "القضاء متاح", "قضا دستیاب")
add("tileVerifiedOnTime", "Verified on time", "أُكِّدت في وقتها",
    "وقت پر تصدیق شدہ")
add("tileQazaCompleted", "Qaza completed", "أُدِّي القضاء", "قضا مکمل")
add("tileLeft", "{duration} left", "بقي {duration}", "{duration} باقی",
    {"duration": "String"})
add("tileUpcoming", "Upcoming", "قادمة", "آنے والی")
add("tileMissed", "Missed", "فائتة", "رہ گئی")
add("tileExcused", "Excused", "معذور", "معذور")

# ------------------------------------------------------------ lock screen ----
add("lockGoodMorning", "Good morning", "صباح الخير", "صبح بخیر")
add("lockFajrFirst", "Please offer Fajr before starting your day.",
    "أدِّ صلاة الفجر قبل أن تبدأ يومك.",
    "دن شروع کرنے سے پہلے فجر ادا کریں۔")
add("lockItIsTimeFor", "It's time for {prayer}", "حان وقت {prayer}",
    "{prayer} کا وقت ہو گیا ہے", {"prayer": "String"})
add("lockPerformPrayer",
    "Please perform your prayer. Your apps will unlock once you confirm.",
    "أدِّ صلاتك. ستُفتح تطبيقاتك بمجرد التأكيد.",
    "اپنی نماز ادا کریں۔ تصدیق کرتے ہی آپ کی ایپس کھل جائیں گی۔")
add("lockCompletedPrayer", "I completed my prayer", "أكملت صلاتي",
    "میں نے نماز مکمل کر لی")
add("lockEmergencyUnlock", "Emergency unlock", "فتح للطوارئ",
    "ہنگامی انلاک")
add("lockAppPaused", "{app} is paused until you have prayed.",
    "{app} متوقف حتى تصلي.", "{app} نماز پڑھنے تک روکا گیا ہے۔",
    {"app": "String"})
add("lockThatApp", "That app", "ذلك التطبيق", "وہ ایپ")
add("lockEssentialsNeverBlocked",
    "Phone, messages and settings are never blocked.",
    "الهاتف والرسائل والإعدادات لا تُحجب أبدًا.",
    "فون، پیغامات اور ترتیبات کبھی بلاک نہیں ہوتے۔")
add("lockEmergencyTitle", "Emergency unlock?", "فتح للطوارئ؟",
    "ہنگامی انلاک؟")
add("lockEmergencyBody",
    "This unlocks your apps without verifying your prayer. If you need to call "
    "someone, the phone and messages apps are always available without using "
    "this.",
    "يفتح هذا تطبيقاتك دون تأكيد صلاتك. إن احتجت للاتصال بأحد، فالهاتف "
    "والرسائل متاحان دائمًا دون استخدام هذا.",
    "یہ آپ کی نماز کی تصدیق کے بغیر ایپس کھول دیتا ہے۔ اگر کسی کو کال کرنی ہو "
    "تو فون اور پیغامات ہمیشہ دستیاب ہیں۔")
add("lockEmergencyBodyCount",
    "This unlocks your apps without verifying your prayer. You have {count} "
    "per day.\n\nIf you need to call someone, the phone and messages apps are "
    "always available without using this.",
    "يفتح هذا تطبيقاتك دون تأكيد صلاتك. لديك {count} في اليوم.\n\nإن احتجت "
    "للاتصال بأحد، فالهاتف والرسائل متاحان دائمًا دون استخدام هذا.",
    "یہ آپ کی نماز کی تصدیق کے بغیر ایپس کھول دیتا ہے۔ آپ کے پاس روزانہ "
    "{count} ہیں۔\n\nاگر کسی کو کال کرنی ہو تو فون اور پیغامات ہمیشہ دستیاب "
    "ہیں۔", {"count": "int"})
add("lockUnlockedTitle", "Apps unlocked", "التطبيقات مفتوحة",
    "ایپس کھل گئیں")
add("lockUnlockedBody",
    "Your apps are available again. This has been recorded.",
    "تطبيقاتك متاحة مرة أخرى. تم تسجيل ذلك.",
    "آپ کی ایپس دوبارہ دستیاب ہیں۔ یہ درج کر لیا گیا ہے۔")
add("lockNoUnlocksLeft", "You've used all your emergency unlocks today",
    "استخدمت كل عمليات الفتح الطارئ لهذا اليوم",
    "آپ آج کے تمام ہنگامی انلاک استعمال کر چکے ہیں")
add("lockWillUnlockAfter",
    "Apps will unlock once you complete and verify your prayer.",
    "ستُفتح التطبيقات بعد أن تكمل صلاتك وتؤكدها.",
    "نماز مکمل اور تصدیق کرنے کے بعد ایپس کھل جائیں گی۔")

# ----------------------------------------------------------- verification ----
add("verifyTitle", "Verify {prayer}", "تأكيد {prayer}", "{prayer} کی تصدیق",
    {"prayer": "String"})
add("verifyRecordTitle", "Record {prayer}", "تسجيل {prayer}",
    "{prayer} درج کریں", {"prayer": "String"})
add("verifyDidYouComplete", "Did you complete {prayer}?", "هل أكملت {prayer}؟",
    "کیا آپ نے {prayer} مکمل کر لی؟", {"prayer": "String"})
add("verifyYesCompleted", "Yes, I completed it", "نعم، أكملتها",
    "جی ہاں، مکمل کر لی")
add("verifyNotYet", "Not yet", "ليس بعد", "ابھی نہیں")
add("verifyPhotoPrompt", "Point the camera at your prayer mat and take a photo.",
    "وجّه الكاميرا إلى سجادة الصلاة والتقط صورة.",
    "کیمرہ اپنی جائے نماز کی طرف کریں اور تصویر لیں۔")
add("verifyManualPrompt", "Confirm that you have prayed.", "أكّد أنك صليت.",
    "تصدیق کریں کہ آپ نے نماز پڑھ لی ہے۔")
add("verifyTakePhoto", "Take photo of prayer mat", "التقط صورة لسجادة الصلاة",
    "جائے نماز کی تصویر لیں")
add("verifyWithoutPhoto", "Record without a photo", "سجّل بدون صورة",
    "تصویر کے بغیر درج کریں")
add("verifyTrouble",
    "Having trouble? You can record this prayer without a photo.",
    "تواجه صعوبة؟ يمكنك تسجيل هذه الصلاة دون صورة.",
    "مشکل ہو رہی ہے؟ آپ یہ نماز تصویر کے بغیر درج کر سکتے ہیں۔")
add("verifyNoCamera",
    "No camera was found on this device. You can still record this prayer "
    "without a photo.",
    "لم يُعثر على كاميرا في هذا الجهاز. لا يزال بإمكانك تسجيل الصلاة دون صورة.",
    "اس ڈیوائس میں کیمرہ نہیں ملا۔ آپ پھر بھی یہ نماز تصویر کے بغیر درج کر "
    "سکتے ہیں۔")
add("verifyCameraDenied",
    "Camera permission was declined. Allow it in Settings, or record this "
    "prayer without a photo.",
    "رُفض إذن الكاميرا. اسمح به من الإعدادات، أو سجّل الصلاة دون صورة.",
    "کیمرے کی اجازت مسترد ہوئی۔ ترتیبات میں اجازت دیں، یا تصویر کے بغیر درج "
    "کریں۔")
add("verifyCameraFailed", "The camera could not be opened ({code}).",
    "تعذر فتح الكاميرا ({code}).", "کیمرہ نہیں کھل سکا ({code})۔",
    {"code": "String"})
add("verifyPhotoFailed", "The photo could not be taken ({code}).",
    "تعذر التقاط الصورة ({code}).", "تصویر نہیں لی جا سکی ({code})۔",
    {"code": "String"})
add("verifySaveFailed", "Could not save your prayer. Please try again.",
    "تعذر حفظ صلاتك. أعد المحاولة.",
    "آپ کی نماز محفوظ نہیں ہو سکی۔ دوبارہ کوشش کریں۔")
add("verifyWindowsPassed",
    "The prayer and qaza windows have both passed. This prayer is now recorded "
    "as missed.",
    "انتهى وقتا الأداء والقضاء. تُسجَّل هذه الصلاة الآن كفائتة.",
    "ادا اور قضا دونوں اوقات گزر چکے ہیں۔ یہ نماز اب فوت شدہ درج ہے۔")
add("verifyNoSchedule", "Cannot complete prayer: no schedule available",
    "تعذر إكمال الصلاة: لا يوجد جدول متاح",
    "نماز مکمل نہیں ہو سکتی: کوئی شیڈول دستیاب نہیں")

# ---------------------------------------------------------------- qaza ------
add("qazaTitle", "Make-up prayers", "صلوات القضاء", "قضا نمازیں")
add("qazaOne", "One prayer to make up", "صلاة واحدة للقضاء",
    "ایک نماز قضا کرنی ہے")
add("qazaMany", "{count} prayers to make up", "{count} صلوات للقضاء",
    "{count} نمازیں قضا کرنی ہیں", {"count": "int"})
add("qazaHint",
    "Pray them when you can, then mark them here. The oldest is first.",
    "صلِّها متى استطعت ثم سجّلها هنا. الأقدم أولًا.",
    "جب ممکن ہو ادا کریں، پھر یہاں نشان لگائیں۔ سب سے پرانی پہلے ہے۔")
add("qazaMarked", "{prayer} marked as made up.", "سُجِّلت {prayer} كقضاء.",
    "{prayer} قضا کے طور پر درج ہو گئی۔", {"prayer": "String"})
add("qazaAlreadyMarked", "That prayer was already marked as made up.",
    "سبق تسجيل تلك الصلاة كقضاء.",
    "وہ نماز پہلے ہی قضا کے طور پر درج تھی۔")
add("qazaNothing", "Nothing to make up", "لا شيء للقضاء", "کچھ قضا نہیں")
add("qazaNothingBody",
    "Every prayer whose window has closed was accounted for.",
    "كل صلاة انتهى وقتها تم حسابها.",
    "ہر وہ نماز جس کا وقت گزر چکا، شمار کر لی گئی ہے۔")
add("qazaLoadFailed", "Your make-up prayers could not be loaded.",
    "تعذر تحميل صلوات القضاء.", "آپ کی قضا نمازیں لوڈ نہیں ہو سکیں۔")

# ----------------------------------------------------------- analytics -----
add("analyticsTitle", "Your prayers", "صلواتك", "آپ کی نمازیں")
add("analyticsDayStreak", "day streak", "أيام متتالية", "دن کا تسلسل")
add("analyticsLongestStreak", "longest streak", "أطول تتابع",
    "طویل ترین تسلسل")
add("analyticsAllTimeCompletion", "all-time completion", "الإنجاز الكلي",
    "مجموعی تکمیل")
add("analyticsPrayersFulfilled", "prayers fulfilled", "صلوات مؤداة",
    "ادا شدہ نمازیں")
add("analyticsOnTime", "on time", "في وقتها", "وقت پر")
add("analyticsQazaMakeUp", "qaza (make-up)", "قضاء", "قضا")
add("analyticsQazaShort", "Qaza", "قضاء", "قضا")
add("analyticsVerified", "Verified", "مؤكدة", "تصدیق شدہ")
add("analyticsMissed", "missed", "فائتة", "فوت شدہ")
add("analyticsThisWeek", "THIS WEEK", "هذا الأسبوع", "اس ہفتے")
add("analyticsCompletionRate", "COMPLETION RATE", "معدل الإنجاز",
    "تکمیل کی شرح")
add("analyticsByPrayer", "BY PRAYER", "حسب الصلاة", "نماز کے لحاظ سے")
add("analyticsRangeWeek", "This week", "هذا الأسبوع", "اس ہفتے")
add("analyticsRangeMonth", "This month", "هذا الشهر", "اس ماہ")
add("analyticsRangeYear", "This year", "هذه السنة", "اس سال")
add("analyticsVerificationHistory", "Verification history", "سجل التأكيدات",
    "تصدیق کی تاریخ")
add("analyticsLockHistory", "Lock history", "سجل الأقفال", "قفل کی تاریخ")
add("analyticsEmergencyUnlocks", "Emergency unlocks", "عمليات الفتح الطارئ",
    "ہنگامی انلاک")
add("analyticsMostMissed",
    "{prayer} is the prayer you miss most. A little extra focus there will "
    "lift your whole week.",
    "{prayer} هي أكثر صلاة تفوتك. قليل من التركيز عليها يرفع أسبوعك كله.",
    "{prayer} وہ نماز ہے جو سب سے زیادہ رہ جاتی ہے۔ تھوڑی سی توجہ پورا ہفتہ "
    "بہتر کر دے گی۔", {"prayer": "String"})
add("analyticsParked", "{count} record(s) could not be uploaded.",
    "تعذر رفع {count} من السجلات.",
    "{count} ریکارڈ اپ لوڈ نہیں ہو سکے۔", {"count": "int"})
add("analyticsPending", "{count} record(s) waiting to sync.",
    "{count} من السجلات بانتظار المزامنة.",
    "{count} ریکارڈ ہم آہنگی کے منتظر ہیں۔", {"count": "int"})
add("analyticsReleasedWithoutDetection", "Released without detection",
    "أُفرِج دون كشف", "بغیر تصدیق کے جاری")
add("analyticsNotVerified", "Not verified", "غير مؤكدة", "غیر تصدیق شدہ")
add("analyticsNoPrayersYet", "No prayers recorded yet", "لم تُسجَّل صلوات بعد",
    "ابھی کوئی نماز درج نہیں")
add("analyticsChartSummary",
    "Prayer completion over {days} days: {fulfilled} of {assessed} prayers "
    "fulfilled",
    "إنجاز الصلاة خلال {days} يومًا: {fulfilled} من {assessed} صلوات مؤداة",
    "{days} دنوں میں نماز کی تکمیل: {assessed} میں سے {fulfilled} ادا",
    {"days": "int", "fulfilled": "int", "assessed": "int"})

# ------------------------------------------------------------- settings -----
add("settingsSectionPrayerTimes", "Prayer times", "أوقات الصلاة",
    "نماز کے اوقات")
add("settingsLocation", "Location", "الموقع", "مقام")
add("settingsCalculationMethod", "Calculation method", "طريقة الحساب",
    "حساب کا طریقہ")
add("settingsIslamicSection", "Islamic section", "المذهب الإسلامي",
    "اسلامی مسلک")
add("settingsPrayerMode", "Prayer mode", "نمط الصلاة", "نماز کا انداز")
add("settingsPrayerCards", "{mode} — {count} prayer cards",
    "{mode} — {count} بطاقات صلاة", "{mode} — {count} نماز کارڈ",
    {"mode": "String", "count": "int"})
add("settingsJumuah", "Jumu'ah", "الجمعة", "جمعہ")
add("settingsAsrTiming", "Asr timing", "توقيت العصر", "عصر کا وقت")
add("settingsResetSectionDefaults", "Reset to section defaults",
    "إعادة ضبط إلى إعدادات المذهب", "مسلک کی طے شدہ ترتیبات پر واپس")
add("settingsReturnToSuggested", "Return to what {section} suggests",
    "العودة إلى ما يقترحه {section}", "{section} کی تجویز پر واپس جائیں",
    {"section": "String"})
add("settingsHijriDate", "Hijri date", "التاريخ الهجري", "ہجری تاریخ")
add("settingsHijriCalculated",
    "Calculated — adjust if it differs from your local sighting",
    "محسوب — عدّله إن اختلف عن رؤيتك المحلية",
    "حساب شدہ — اگر مقامی رویت سے مختلف ہو تو ایڈجسٹ کریں")
add("settingsHijriAdjustment", "Hijri date adjustment", "تعديل التاريخ الهجري",
    "ہجری تاریخ کی ایڈجسٹمنٹ")
add("settingsHijriAsCalculated", "As calculated", "كما هو محسوب",
    "جیسا حساب کیا گیا")
add("settingsHijriDayLater", "1 day later", "يوم واحد لاحقًا", "1 دن بعد")
add("settingsHijriDayEarlier", "1 day earlier", "يوم واحد سابقًا",
    "1 دن پہلے")
add("settingsHijriDaysLater", "{days} days later", "{days} أيام لاحقًا",
    "{days} دن بعد", {"days": "int"})
add("settingsHijriDaysEarlier", "{days} days earlier", "{days} أيام سابقًا",
    "{days} دن پہلے", {"days": "int"})
add("settingsHighLatitude", "High latitude rule", "قاعدة خطوط العرض العالية",
    "بلند عرض البلد کا قاعدہ")
add("settingsSectionReminders", "Reminders", "التذكيرات", "یاد دہانیاں")
add("settingsRemindBefore", "Remind me before prayer", "ذكّرني قبل الصلاة",
    "نماز سے پہلے یاد دلائیں")
add("settingsMinutesBefore", "{minutes} minutes before", "{minutes} دقيقة قبل",
    "{minutes} منٹ پہلے", {"minutes": "int"})
add("settingsAtPrayerTime", "At prayer time", "عند وقت الصلاة",
    "نماز کے وقت")
add("settingsPlayAdhan", "Play adhan", "تشغيل الأذان", "اذان چلائیں")
add("settingsPlayAdhanBody", "Sound the call to prayer at prayer time",
    "أطلق الأذان عند وقت الصلاة", "نماز کے وقت اذان کی آواز")
add("settingsSectionBlocking", "App blocking", "حجب التطبيقات",
    "ایپ بلاکنگ")
add("settingsBlockingUnavailable",
    "Blocking other apps is not available on this platform. Prayer times, "
    "reminders, tracking and verification all work normally.",
    "حجب التطبيقات غير متاح على هذه المنصة. أوقات الصلاة والتذكيرات والتتبع "
    "والتأكيد تعمل كلها بشكل طبيعي.",
    "اس پلیٹ فارم پر ایپ بلاکنگ دستیاب نہیں۔ نماز کے اوقات، یاد دہانیاں، "
    "ٹریکنگ اور تصدیق سب معمول کے مطابق کام کرتے ہیں۔")
add("settingsBlockDuringPrayer", "Block apps during prayer",
    "احجب التطبيقات أثناء الصلاة", "نماز کے دوران ایپس بلاک کریں")
add("settingsBlockedApps", "Blocked apps", "التطبيقات المحجوبة",
    "بلاک شدہ ایپس")
add("settingsNoneSelected", "None selected", "لم يُحدَّد شيء",
    "کوئی منتخب نہیں")
add("settingsCountSelected", "{count} selected", "{count} محدد",
    "{count} منتخب", {"count": "int"})
add("settingsGracePeriod", "Grace period", "مهلة السماح", "مہلت")
add("settingsGraceBody", "{minutes} minutes after the adhan before apps lock",
    "{minutes} دقيقة بعد الأذان قبل قفل التطبيقات",
    "اذان کے {minutes} منٹ بعد ایپس بند ہوں گی", {"minutes": "int"})
add("settingsLockImmediately", "Lock immediately", "اقفل فورًا",
    "فوراً بند کریں")
add("settingsLockAfterMinutes", "Lock after {minutes} minutes",
    "اقفل بعد {minutes} دقيقة", "{minutes} منٹ بعد بند کریں",
    {"minutes": "int"})
add("settingsWhenAppsUnlock", "When apps unlock", "متى تُفتح التطبيقات",
    "ایپس کب کھلیں")
add("settingsPrayerDurations", "Prayer durations", "مدد الصلاة",
    "نماز کے دورانیے")
add("settingsPrayerDurationsBody", "See how long each prayer window lasts today",
    "اطّلع على مدة كل نافذة صلاة اليوم",
    "دیکھیں کہ آج ہر نماز کا وقت کتنا ہے")
add("settingsMorningProtection", "Morning protection", "حماية الصباح",
    "صبح کی حفاظت")
add("settingsMorningProtectionBody",
    "Keep apps locked after Fajr begins until you have prayed",
    "أبقِ التطبيقات مقفلة بعد دخول الفجر حتى تصلي",
    "فجر کے بعد نماز پڑھنے تک ایپس بند رکھیں")
add("settingsBlockUntilQaza", "Keep apps locked until qaza is made",
    "أبقِ التطبيقات مقفلة حتى يُقضى", "قضا ادا ہونے تک ایپس بند رکھیں")
add("settingsBlockUntilQazaBody",
    "A missed prayer keeps apps blocked for the rest of the day until you make "
    "it up",
    "الصلاة الفائتة تُبقي التطبيقات محجوبة بقية اليوم حتى تقضيها",
    "فوت شدہ نماز باقی دن ایپس بند رکھے گی جب تک آپ اسے ادا نہ کر لیں")
add("settingsMakeUpPrayers", "Make-up prayers", "صلوات القضاء", "قضا نمازیں")
add("settingsMakeUpPrayersBody", "Prayers you still owe",
    "الصلوات التي ما زالت عليك", "وہ نمازیں جو ابھی باقی ہیں")
add("settingsSectionSource", "Prayer time source", "مصدر أوقات الصلاة",
    "اوقات کا ماخذ")
add("settingsConfirmOnline", "Confirm times online",
    "أكّد الأوقات عبر الإنترنت", "اوقات آن لائن تصدیق کریں")
add("settingsConfirmOnlineBody",
    "Check prayer times against an online service when possible. Times are "
    "always calculated on this device as well, so the app works fully offline "
    "either way.",
    "تحقق من أوقات الصلاة عبر خدمة إنترنت متى أمكن. تُحسب الأوقات دائمًا على "
    "هذا الجهاز أيضًا، فيعمل التطبيق دون اتصال في الحالتين.",
    "جب ممکن ہو، اوقات آن لائن سروس سے ملائیں۔ اوقات ہمیشہ اس ڈیوائس پر بھی "
    "حساب ہوتے ہیں، اس لیے ایپ آف لائن بھی مکمل کام کرتی ہے۔")
add("settingsNotifyWindowEnd", "Notify when a window ends",
    "نبّهني عند انتهاء النافذة", "وقت ختم ہونے پر اطلاع دیں")
add("settingsNotifyWindowEndBody",
    "Warn before a prayer window closes, and confirm when apps unlock",
    "نبّه قبل انتهاء وقت الصلاة، وأكّد عند فتح التطبيقات",
    "نماز کا وقت ختم ہونے سے پہلے خبردار کریں، اور ایپس کھلنے پر تصدیق کریں")
add("settingsSectionAfterPrayer", "After prayer", "بعد الصلاة",
    "نماز کے بعد")
add("settingsTasbih", "Tasbih reminder", "تذكير التسبيح", "تسبیح کی یاد دہانی")
add("settingsTasbihBody",
    "Offer SubhanAllah, Alhamdulillah and Allahu Akbar after a recorded prayer",
    "اعرض سبحان الله والحمد لله والله أكبر بعد صلاة مسجلة",
    "درج شدہ نماز کے بعد سبحان اللہ، الحمد للہ اور اللہ اکبر پیش کریں")
add("settingsQuranReminder", "Quran reminder", "تذكير القرآن",
    "قرآن کی یاد دہانی")
add("settingsQuranReminderBody",
    "Suggest five minutes of reading while you are still sitting",
    "اقترح خمس دقائق من القراءة وأنت ما زلت جالسًا",
    "بیٹھے بیٹھے پانچ منٹ تلاوت کی تجویز دیں")
add("settingsSectionVerification", "Verification", "التأكيد", "تصدیق")
add("settingsPhotoVerification", "Photo verification", "التأكيد بالصورة",
    "تصویری تصدیق")
add("settingsPhotoVerificationBody",
    "Take a photo of your prayer mat to unlock apps",
    "التقط صورة لسجادة صلاتك لفتح التطبيقات",
    "ایپس کھولنے کے لیے جائے نماز کی تصویر لیں")
add("settingsPhotoPrivacy",
    "Photos are analysed and immediately discarded. They are never saved to "
    "your device, uploaded to storage, or shared.",
    "تُحلَّل الصور وتُحذف فورًا. لا تُحفظ على جهازك ولا تُرفع ولا تُشارك أبدًا.",
    "تصاویر کا تجزیہ کر کے فوراً حذف کر دی جاتی ہیں۔ نہ ڈیوائس پر محفوظ ہوتی "
    "ہیں، نہ اپ لوڈ، نہ شیئر۔")
add("settingsSectionGeneral", "General", "عام", "عمومی")

# ------------------------------------------------------- blocked apps -------
add("blockedAppsTitle", "Blocked apps", "التطبيقات المحجوبة",
    "بلاک شدہ ایپس")
add("blockedAppsIntro",
    "Selected apps will be unavailable from the start of each prayer until you "
    "confirm you have prayed.",
    "التطبيقات المحددة ستكون غير متاحة من بداية كل صلاة حتى تؤكد أنك صليت.",
    "منتخب ایپس ہر نماز کے آغاز سے اس وقت تک بند رہیں گی جب تک آپ تصدیق نہ "
    "کریں۔")
add("blockedAppsEssentials", "Phone, messages and settings can never be blocked.",
    "الهاتف والرسائل والإعدادات لا يمكن حجبها أبدًا.",
    "فون، پیغامات اور ترتیبات کبھی بلاک نہیں ہو سکتے۔")
add("blockedAppsNoneFound", "No apps found", "لم يُعثر على تطبيقات",
    "کوئی ایپ نہیں ملی")
add("blockedAppsAndroidOnly", "App blocking is only available on Android.",
    "حجب التطبيقات متاح على أندرويد فقط.",
    "ایپ بلاکنگ صرف اینڈرائیڈ پر دستیاب ہے۔")
add("blockedAppsListFailed", "Could not list your apps",
    "تعذر عرض تطبيقاتك", "آپ کی ایپس کی فہرست نہیں مل سکی")
add("blockedAppsSuggested", "Suggested", "مقترح", "تجویز کردہ")
add("blockedAppsChoose", "Choose apps", "اختر التطبيقات", "ایپس منتخب کریں")
add("blockedAppsSelectedCount", "{count} app(s) or categories selected",
    "{count} تطبيق أو فئة محددة", "{count} ایپس یا زمرے منتخب",
    {"count": "int"})
add("blockedAppsIosIntro",
    "Choose which apps to pause during prayer. On iPhone, apps are chosen in "
    "Apple's Screen Time picker — Prayer Lock never sees which apps you pick, "
    "only how many.",
    "اختر التطبيقات التي توقفها أثناء الصلاة. على آيفون تُختار من أداة وقت "
    "الشاشة من أبل — لا يرى قفل الصلاة أي تطبيقات اخترت، بل عددها فقط.",
    "منتخب کریں کہ نماز کے دوران کون سی ایپس روکی جائیں۔ آئی فون پر ایپل کے "
    "اسکرین ٹائم پکر سے منتخب ہوتی ہیں — پریئر لاک کو صرف تعداد معلوم ہوتی "
    "ہے، ایپس نہیں۔")

# ---------------------------------------------------------- durations -------
add("durationsTitle", "Prayer durations", "مدد الصلاة", "نماز کے دورانیے")
add("durationsTotalBlocking", "Today that is {duration} of blocking in total.",
    "اليوم هذا يعني {duration} من الحجب إجمالًا.",
    "آج یہ کل ملا کر {duration} کی بلاکنگ ہے۔", {"duration": "String"})
add("durationsSetLocation", "Set your location to see today's prayer windows.",
    "حدد موقعك لعرض نوافذ صلاة اليوم.",
    "آج کے نماز کے اوقات دیکھنے کے لیے اپنا مقام مقرر کریں۔")
add("durationsSourceConfirmed", "Times confirmed with the prayer time service.",
    "تم تأكيد الأوقات مع خدمة أوقات الصلاة.",
    "اوقات کی سروس سے تصدیق ہو گئی۔")
add("durationsSourceCachedOffline",
    "Showing saved times. They will be confirmed when you are online.",
    "تُعرض الأوقات المحفوظة. ستُؤكَّد عند الاتصال.",
    "محفوظ اوقات دکھائے جا رہے ہیں۔ آن لائن ہونے پر تصدیق ہو گی۔")
add("durationsSourceCached", "Showing saved times.", "تُعرض الأوقات المحفوظة.",
    "محفوظ اوقات دکھائے جا رہے ہیں۔")
add("durationsSourceDevice",
    "Times calculated on this device. They will be confirmed when you are "
    "online.",
    "حُسبت الأوقات على هذا الجهاز. ستُؤكَّد عند الاتصال.",
    "اوقات اس ڈیوائس پر حساب کیے گئے۔ آن لائن ہونے پر تصدیق ہو گی۔")

# ------------------------------------------------------------ jumu'ah -------
add("jumuahTitle", "Jumu'ah", "الجمعة", "جمعہ")
add("jumuahLabel", "JUMU'AH", "الجمعة", "جمعہ")
add("jumuahIntro",
    "On Fridays, Dhuhr is replaced by Jumu'ah at the time your mosque holds "
    "it. Every other day is unchanged.",
    "أيام الجمعة تُستبدل الظهر بالجمعة في الوقت الذي يقيمها فيه مسجدك. بقية "
    "الأيام دون تغيير.",
    "جمعہ کے دن ظہر کی جگہ آپ کی مسجد کے وقت پر جمعہ ہوتا ہے۔ باقی دن بغیر "
    "تبدیلی کے۔")
add("jumuahSmart", "Smart Jumu'ah", "الجمعة الذكية", "اسمارٹ جمعہ")
add("jumuahReplacesDhuhr", "Jumu'ah replaces Dhuhr on Fridays",
    "الجمعة تحل محل الظهر أيام الجمعة",
    "جمعہ کے دن جمعہ ظہر کی جگہ لیتا ہے")
add("jumuahDhuhrEveryDay", "Dhuhr is used every day",
    "تُستخدم الظهر كل يوم", "ہر دن ظہر ہی استعمال ہوتی ہے")
add("jumuahYourMosques", "Your mosques", "مساجدك", "آپ کی مساجد")
add("jumuahChooseMosque",
    "Choose a mosque so Jumu'ah can replace Dhuhr this Friday.",
    "اختر مسجدًا لتحل الجمعة محل الظهر هذه الجمعة.",
    "مسجد منتخب کریں تاکہ اس جمعہ کو جمعہ ظہر کی جگہ لے سکے۔")
add("jumuahChooseMosqueTitle", "Choose where you pray Jumu'ah",
    "اختر أين تصلي الجمعة", "منتخب کریں کہ آپ جمعہ کہاں پڑھتے ہیں")
add("jumuahFridayBehaviour", "Friday behaviour", "سلوك يوم الجمعة",
    "جمعہ کا رویہ")
add("jumuahAskWhenTravel", "Ask when I travel", "اسألني عند السفر",
    "سفر کے وقت پوچھیں")
add("jumuahAskWhenTravelBody",
    "Offer a different mosque if you seem to be somewhere else",
    "اعرض مسجدًا آخر إن بدا أنك في مكان مختلف",
    "اگر آپ کہیں اور معلوم ہوں تو دوسری مسجد تجویز کریں")
add("jumuahSilence", "Silence during Jumu'ah", "الإسكات أثناء الجمعة",
    "جمعہ کے دوران خاموشی")
add("jumuahSilenceBody",
    "Mute the phone for the congregation, and restore it after",
    "اكتم الهاتف أثناء الجماعة وأعده بعدها",
    "جماعت کے لیے فون خاموش کریں، بعد میں بحال کر دیں")
add("jumuahSilenceNeedsAccess",
    "Prayer Lock needs Do Not Disturb access before it can mute anything.",
    "يحتاج قفل الصلاة إذن عدم الإزعاج قبل أن يتمكن من الكتم.",
    "خاموش کرنے سے پہلے پریئر لاک کو ڈسٹرب نہ کریں کی اجازت درکار ہے۔")
add("jumuahGrantAccess", "Grant access", "امنح الإذن", "اجازت دیں")
add("jumuahReset", "Reset", "إعادة ضبط", "دوبارہ ترتیب")
add("jumuahResetTimes", "Reset the built-in mosque times",
    "أعد ضبط أوقات المساجد المدمجة", "بلٹ اِن مسجد اوقات دوبارہ ترتیب دیں")
add("jumuahResetTimesBody", "Mosques you added yourself are kept",
    "المساجد التي أضفتها تبقى", "آپ کی شامل کردہ مساجد باقی رہیں گی")
add("jumuahForget", "Forget where I pray", "انسَ أين أصلي",
    "بھول جائیں میں کہاں پڑھتا ہوں")
add("jumuahForgetBody", "You'll be asked again on the next Friday",
    "سيُسأل مجددًا يوم الجمعة القادم", "اگلے جمعہ دوبارہ پوچھا جائے گا")
add("jumuahAddMosque", "Add mosque", "أضف مسجدًا", "مسجد شامل کریں")
add("jumuahEditMosque", "Edit mosque", "تعديل المسجد", "مسجد میں ترمیم")
add("jumuahMosqueName", "Mosque name", "اسم المسجد", "مسجد کا نام")
add("jumuahMosqueNameHelp", "Shown on the Friday card and in notifications",
    "يظهر على بطاقة الجمعة وفي الإشعارات",
    "جمعہ کارڈ اور اطلاعات میں دکھایا جائے گا")
add("jumuahTime", "Jumu'ah time", "وقت الجمعة", "جمعہ کا وقت")
add("jumuahStartsAt", "Starts {time}", "يبدأ {time}", "{time} شروع",
    {"time": "String"})
add("jumuahEndsAt", "Ends {time}", "ينتهي {time}", "{time} ختم",
    {"time": "String"})
add("jumuahTimeHelp",
    "Apps stay blocked between these times, and this is the window in which "
    "you can confirm your prayer.",
    "تبقى التطبيقات محجوبة بين هذين الوقتين، وهذه هي النافذة التي تؤكد فيها "
    "صلاتك.",
    "ان اوقات کے درمیان ایپس بند رہیں گی، اور اسی دوران آپ نماز کی تصدیق کر "
    "سکتے ہیں۔")
add("jumuahNotesHint", "Parking, which entrance, anything useful",
    "المواقف، أي مدخل، أي شيء مفيد", "پارکنگ، کون سا دروازہ، کوئی بھی کارآمد بات")
add("jumuahNotes", "Notes", "ملاحظات", "نوٹس")
add("jumuahType", "Type", "النوع", "قسم")
add("jumuahOptional", "Optional", "اختياري", "اختیاری")
add("jumuahAddress", "Address", "العنوان", "پتہ")
add("jumuahNoPosition", "No position saved", "لم يُحفظ موقع",
    "کوئی مقام محفوظ نہیں")
add("jumuahPositionSaved", "Position saved", "حُفظ الموقع", "مقام محفوظ")
add("jumuahPositionHelp", "Used to offer this mosque when you are nearby",
    "يُستخدم لعرض هذا المسجد عندما تكون قريبًا",
    "قریب ہونے پر یہ مسجد تجویز کرنے کے لیے")
add("jumuahUseCurrent", "Use current", "استخدم الحالي", "موجودہ استعمال کریں")
add("jumuahIPrayed", "I prayed Jumu'ah", "صليت الجمعة",
    "میں نے جمعہ پڑھ لیا")
add("jumuahConfirmedLate", "Confirmed late", "أُكِّدت متأخرة",
    "تاخیر سے تصدیق")
add("jumuahMissed", "Missed — pray Dhuhr instead", "فائتة — صلِّ الظهر بدلًا",
    "رہ گئی — اس کے بجائے ظہر پڑھیں")
add("jumuahLeftToConfirm", "{duration} left to confirm",
    "بقي {duration} للتأكيد", "تصدیق کے لیے {duration} باقی",
    {"duration": "String"})
add("jumuahStartsIn", "Starts in {duration}", "يبدأ بعد {duration}",
    "{duration} میں شروع", {"duration": "String"})
add("jumuahWhereToday", "Where will you pray Jumu'ah today?",
    "أين ستصلي الجمعة اليوم؟", "آج آپ جمعہ کہاں پڑھیں گے؟")
add("jumuahWhereTodayBody",
    "We'll use this every Friday. You can change it in Settings.",
    "سنستخدم هذا كل جمعة. يمكنك تغييره من الإعدادات.",
    "ہم اسے ہر جمعہ استعمال کریں گے۔ ترتیبات میں تبدیل کر سکتے ہیں۔")
add("jumuahTravelTitle", "Praying somewhere else today?",
    "هل تصلي في مكان آخر اليوم؟", "آج کہیں اور نماز پڑھ رہے ہیں؟")
add("jumuahTravelBody",
    "You're about {near} from {mosque}, and {far} from your usual mosque.",
    "أنت على بعد {near} من {mosque}، و{far} من مسجدك المعتاد.",
    "آپ {mosque} سے تقریباً {near} پر ہیں، اور اپنی معمول کی مسجد سے {far} پر۔",
    {"near": "String", "mosque": "String", "far": "String"})
add("jumuahTravelStay", "No, stay as I am", "لا، أبقِ كما أنا",
    "نہیں، ویسے ہی رہنے دیں")
add("jumuahTravelUse", "Use it today", "استخدمه اليوم", "آج یہی استعمال کریں")
add("jumuahKilometres", "{value} km", "{value} كم", "{value} کلومیٹر",
    {"value": "String"})
add("jumuahNextFridayDays",
    "Today is not Friday. Jumu'ah next applies in {days} days.",
    "اليوم ليس الجمعة. تنطبق الجمعة بعد {days} أيام.",
    "آج جمعہ نہیں ہے۔ جمعہ {days} دن بعد لاگو ہوگا۔", {"days": "int"})
add("jumuahNextFridayTomorrow", "Today is not Friday. Jumu'ah applies tomorrow.",
    "اليوم ليس الجمعة. تنطبق الجمعة غدًا.",
    "آج جمعہ نہیں ہے۔ جمعہ کل لاگو ہوگا۔")
add("jumuahTodayIsFriday", "Today is Friday.", "اليوم هو الجمعة.",
    "آج جمعہ ہے۔")
add("jumuahAppliedToday", "Today Dhuhr is replaced by Jumu'ah.",
    "اليوم تحل الجمعة محل الظهر.", "آج ظہر کی جگہ جمعہ ہے۔")
add("jumuahAppliedClamped",
    "Today Dhuhr is replaced by Jumu'ah, adjusted to fit inside Dhuhr's window.",
    "اليوم تحل الجمعة محل الظهر، مع تعديلها لتقع داخل نافذة الظهر.",
    "آج ظہر کی جگہ جمعہ ہے، جسے ظہر کے وقت میں سمانے کے لیے ایڈجسٹ کیا گیا۔")
add("jumuahOutsideDhuhr",
    "Your Jumu'ah time falls outside Dhuhr today, so ordinary Dhuhr is being "
    "used.",
    "وقت جمعتك يقع خارج الظهر اليوم، لذا تُستخدم الظهر العادية.",
    "آج آپ کا جمعہ کا وقت ظہر سے باہر ہے، اس لیے عام ظہر استعمال ہو رہی ہے۔")
add("jumuahNotActive", "Jumu'ah is not active today.",
    "الجمعة غير مفعّلة اليوم.", "آج جمعہ فعال نہیں ہے۔")

# --------------------------------------------------------- onboarding -------
add("onboardingStepOf", "Step {index} of {count}", "الخطوة {index} من {count}",
    "{count} میں سے مرحلہ {index}", {"index": "int", "count": "int"})
add("onboardingStart", "Start praying on time", "ابدأ الصلاة في وقتها",
    "وقت پر نماز شروع کریں")
add("onboardingWhereAreYou", "Where are you?", "أين أنت؟", "آپ کہاں ہیں؟")
add("onboardingWhereBody",
    "Prayer times depend on your location. Detect it automatically, or choose "
    "the nearest city.",
    "تعتمد أوقات الصلاة على موقعك. اكتشفه تلقائيًا أو اختر أقرب مدينة.",
    "نماز کے اوقات آپ کے مقام پر منحصر ہیں۔ خودکار پتہ لگائیں یا قریب ترین "
    "شہر منتخب کریں۔")
add("onboardingUseLocation", "Use my location", "استخدم موقعي",
    "میرا مقام استعمال کریں")
add("onboardingDetecting", "Detecting…", "جارٍ التحديد…", "پتہ لگایا جا رہا ہے…")
add("onboardingSearchCity", "Search for a city", "ابحث عن مدينة",
    "شہر تلاش کریں")
add("onboardingLocationOff",
    "Location services are turned off. Turn them on, or pick a city below.",
    "خدمات الموقع مغلقة. شغّلها أو اختر مدينة أدناه.",
    "لوکیشن سروسز بند ہیں۔ انہیں آن کریں یا نیچے سے شہر منتخب کریں۔")
add("onboardingLocationDenied",
    "Location permission was declined. You can pick a city below instead.",
    "رُفض إذن الموقع. يمكنك اختيار مدينة أدناه بدلًا من ذلك.",
    "مقام کی اجازت مسترد ہوئی۔ آپ نیچے سے شہر منتخب کر سکتے ہیں۔")
add("onboardingLocationFailed",
    "Could not determine your location. Pick a city below instead.",
    "تعذر تحديد موقعك. اختر مدينة أدناه بدلًا من ذلك.",
    "آپ کا مقام معلوم نہیں ہو سکا۔ نیچے سے شہر منتخب کریں۔")
add("onboardingSectionQuestion", "Which Islamic section do you follow?",
    "أي مذهب إسلامي تتبع؟", "آپ کس اسلامی مسلک کی پیروی کرتے ہیں؟")
add("onboardingSectionBody",
    "This sets a starting point for prayer times and how prayers are grouped. "
    "You can change everything later.",
    "يحدد هذا نقطة انطلاق لأوقات الصلاة وكيفية تجميعها. يمكنك تغيير كل شيء "
    "لاحقًا.",
    "یہ نماز کے اوقات اور نمازوں کی ترتیب کا نقطۂ آغاز طے کرتا ہے۔ آپ بعد میں "
    "سب کچھ بدل سکتے ہیں۔")
add("onboardingMethodBody",
    "Different authorities use different sun angles for Fajr and Isha. Choose "
    "the one your local mosque follows.",
    "تستخدم الجهات المختلفة زوايا شمس مختلفة للفجر والعشاء. اختر ما يتبعه "
    "مسجدك المحلي.",
    "مختلف ادارے فجر اور عشاء کے لیے مختلف زاویے استعمال کرتے ہیں۔ وہ منتخب "
    "کریں جو آپ کی مقامی مسجد اپناتی ہے۔")
add("onboardingBlockingTitle", "Allow app blocking", "اسمح بحجب التطبيقات",
    "ایپ بلاکنگ کی اجازت دیں")
add("onboardingBlockingBody",
    "These permissions let Prayer Lock restrict distracting apps during "
    "prayer. Without them, blocking cannot work. You can skip this and enable "
    "it later.",
    "تتيح هذه الأذونات لقفل الصلاة تقييد التطبيقات المشتتة أثناء الصلاة. "
    "بدونها لا يعمل الحجب. يمكنك التخطي وتفعيلها لاحقًا.",
    "یہ اجازتیں پریئر لاک کو نماز کے دوران خلل ڈالنے والی ایپس روکنے دیتی "
    "ہیں۔ ان کے بغیر بلاکنگ کام نہیں کرتی۔ آپ چھوڑ کر بعد میں فعال کر سکتے "
    "ہیں۔")
add("onboardingUsageAccess", "Usage access", "الوصول إلى الاستخدام",
    "استعمال تک رسائی")
add("onboardingUsageAccessBody", "Lets the app see which app is currently open.",
    "يتيح للتطبيق معرفة أي تطبيق مفتوح حاليًا.",
    "ایپ کو معلوم ہوتا ہے کہ اس وقت کون سی ایپ کھلی ہے۔")
add("onboardingOverlay", "Display over other apps",
    "العرض فوق التطبيقات الأخرى", "دوسری ایپس کے اوپر دکھائیں")
add("onboardingOverlayBody",
    "Lets the prayer reminder appear over a blocked app.",
    "يتيح ظهور تذكير الصلاة فوق تطبيق محجوب.",
    "نماز کی یاد دہانی بلاک شدہ ایپ کے اوپر ظاہر ہو سکتی ہے۔")
add("onboardingBattery", "Ignore battery optimisation", "تجاهل تحسين البطارية",
    "بیٹری آپٹیمائزیشن نظرانداز کریں")
add("onboardingBatteryBody",
    "Stops the system pausing the reminder service in the background. Strongly "
    "recommended on Samsung and Xiaomi devices.",
    "يمنع النظام من إيقاف خدمة التذكير في الخلفية. يُنصح به بشدة على أجهزة "
    "سامسونج وشاومي.",
    "سسٹم کو پس منظر میں یاد دہانی سروس روکنے سے بچاتا ہے۔ سام سنگ اور شیاؤمی "
    "پر خاص طور پر تجویز کردہ۔")
add("onboardingAllow", "Allow", "اسمح", "اجازت دیں")
add("onboardingScreenTimeTitle", "Allow Screen Time access",
    "اسمح بالوصول إلى وقت الشاشة", "اسکرین ٹائم رسائی کی اجازت دیں")
add("onboardingScreenTimeBody",
    "Prayer Lock uses Screen Time to pause distracting apps during prayer. "
    "iPhone asks for this once. You can skip it and enable it later in "
    "Settings.",
    "يستخدم قفل الصلاة وقت الشاشة لإيقاف التطبيقات المشتتة أثناء الصلاة. يطلب "
    "آيفون هذا مرة واحدة. يمكنك التخطي وتفعيله لاحقًا من الإعدادات.",
    "پریئر لاک نماز کے دوران ایپس روکنے کے لیے اسکرین ٹائم استعمال کرتا ہے۔ "
    "آئی فون یہ ایک بار پوچھتا ہے۔ آپ چھوڑ کر بعد میں ترتیبات سے فعال کر سکتے "
    "ہیں۔")
add("onboardingScreenTime", "Screen Time", "وقت الشاشة", "اسکرین ٹائم")
add("onboardingScreenTimeDetail",
    "Lets Prayer Lock pause the apps you choose during prayer, and release them "
    "once you have prayed. Your app choices stay private — even Prayer Lock "
    "cannot see which apps you pick.",
    "يتيح لقفل الصلاة إيقاف التطبيقات التي تختارها أثناء الصلاة وتحريرها بعد "
    "أن تصلي. تبقى اختياراتك خاصة — حتى قفل الصلاة لا يرى ما تختاره.",
    "پریئر لاک کو نماز کے دوران آپ کی منتخب ایپس روکنے اور نماز کے بعد کھولنے "
    "دیتا ہے۔ آپ کے انتخاب نجی رہتے ہیں — پریئر لاک بھی نہیں دیکھ سکتا۔")
add("onboardingBlockingUnavailable",
    "Restricting other apps is not available on this platform. Prayer times, "
    "reminders, tracking and verification all work normally.",
    "تقييد التطبيقات الأخرى غير متاح على هذه المنصة. أوقات الصلاة والتذكيرات "
    "والتتبع والتأكيد تعمل كلها بشكل طبيعي.",
    "اس پلیٹ فارم پر دوسری ایپس روکنا دستیاب نہیں۔ نماز کے اوقات، یاد دہانیاں، "
    "ٹریکنگ اور تصدیق سب معمول کے مطابق کام کرتے ہیں۔")

# --------------------------------------------------------- post-prayer ------
add("dhikrPrayerRecorded", "Prayer recorded", "سُجِّلت الصلاة", "نماز درج ہو گئی")
add("dhikrSubhanAllahMeaning", "Glory be to Allah", "سبحان الله",
    "اللہ پاک ہے")
add("dhikrAlhamdulillahMeaning", "All praise is for Allah", "الحمد لله",
    "تمام تعریف اللہ کے لیے")
add("dhikrAllahuAkbarMeaning", "Allah is the greatest", "الله أكبر",
    "اللہ سب سے بڑا ہے")
add("dhikrOfCount", "of {count}", "من {count}", "{count} میں سے",
    {"count": "int"})
add("dhikrComplete", "Tasbih complete", "اكتمل التسبيح", "تسبیح مکمل")
add("dhikrTapToCount", "Tap to count", "اضغط للعد", "گننے کے لیے دبائیں")
add("dhikrQuranPrompt", "Read the Quran for five minutes?",
    "هل تقرأ القرآن خمس دقائق؟", "پانچ منٹ قرآن پڑھیں؟")
add("dhikrQuranBody",
    "Open your usual Quran app or copy — this is just a reminder while you are "
    "still sitting.",
    "افتح تطبيق أو نسخة القرآن المعتادة — هذا مجرد تذكير وأنت ما زلت جالسًا.",
    "اپنی معمول کی قرآن ایپ یا نسخہ کھولیں — یہ صرف ایک یاد دہانی ہے جب آپ "
    "ابھی بیٹھے ہیں۔")

# ------------------------------------------------------ islamic calendar ----
add("calendarSacredMonth", "sacred month", "شهر حرام", "حرمت والا مہینہ")
add("calendarSehriEndsIn", "Sehri ends in", "ينتهي السحور بعد",
    "سحری ختم ہونے میں")
add("calendarIftarIn", "Iftar in", "الإفطار بعد", "افطار میں")
add("calendarAfterIsha", "after Isha", "بعد العشاء", "عشاء کے بعد")
add("calendarRamadanDay", "Ramadan · Day {day}", "رمضان · اليوم {day}",
    "رمضان · دن {day}", {"day": "int"})
add("calendarOddNight", "One of the odd nights of the last ten",
    "إحدى الليالي الوترية من العشر الأواخر",
    "آخری عشرے کی طاق راتوں میں سے ایک")
add("calendarLastTen", "The last ten nights", "العشر الأواخر",
    "آخری دس راتیں")
add("calendarEidPrayer", "Eid prayer", "صلاة العيد", "عید کی نماز")
add("calendarAfterSunrise", "after sunrise", "بعد الشروق", "طلوعِ آفتاب کے بعد")

# ---------------------------------------------------------- countdown -------
add("statPercentDetail", "{label}: {percent} percent, {detail}",
    "{label}: {percent} بالمئة، {detail}", "{label}: {percent} فیصد، {detail}",
    {"label": "String", "percent": "int", "detail": "String"})
add("tileSemantics", "{prayer}, {time}, {phase}", "{prayer}، {time}، {phase}",
    "{prayer}، {time}، {phase}",
    {"prayer": "String", "time": "String", "phase": "String"})
add("analyticsStatsFailed", "Could not load your statistics.",
    "تعذر تحميل إحصاءاتك.", "آپ کے اعدادوشمار لوڈ نہیں ہو سکے۔")
add("analyticsLockActive", "{prayer} — active", "{prayer} — نشط",
    "{prayer} — فعال", {"prayer": "String"})
add("analyticsLockEnded", "{prayer} — {reason}", "{prayer} — {reason}",
    "{prayer} — {reason}", {"prayer": "String", "reason": "String"})
add("analyticsUnlockNumbered", "Unlock #{sequence} — {reason}",
    "فتح رقم {sequence} — {reason}", "انلاک #{sequence} — {reason}",
    {"sequence": "int", "reason": "String"})
add("analyticsUnlockPlain", "Emergency unlock #{sequence}",
    "فتح طارئ رقم {sequence}", "ہنگامی انلاک #{sequence}",
    {"sequence": "int"})
add("lockEndVerified", "unlocked after prayer", "فُتح بعد الصلاة",
    "نماز کے بعد کھلا")
add("lockEndEmergency", "emergency unlock", "فتح طارئ", "ہنگامی انلاک")
add("lockEndWindowExpired", "prayer window ended", "انتهى وقت الصلاة",
    "نماز کا وقت ختم")
add("lockEndDisabled", "blocking turned off", "أُوقف الحجب",
    "بلاکنگ بند کر دی گئی")
add("lockEndRestarted", "app restarted", "أُعيد تشغيل التطبيق",
    "ایپ دوبارہ شروع ہوئی")
add("dashboardNextUpper", "NEXT: {prayer}", "التالية: {prayer}",
    "اگلی: {prayer}", {"prayer": "String"})
add("dhikrSubhanAllah", "SubhanAllah", "سبحان الله", "سبحان اللہ")
add("dhikrAlhamdulillah", "Alhamdulillah", "الحمد لله", "الحمد للہ")
add("dhikrAllahuAkbar", "Allahu Akbar", "الله أكبر", "اللہ اکبر")
add("sectionSummaryPrayerTimes", "Prayer times", "أوقات الصلاة",
    "نماز کے اوقات")
add("sectionSummaryAsr", "Asr timing", "توقيت العصر", "عصر کا وقت")
add("sectionSummaryGrouping", "Prayer grouping", "تجميع الصلوات",
    "نمازوں کی ترتیب")
add("jumuahStartsLabel", "Jumu'ah starts", "تبدأ الجمعة", "جمعہ شروع")
add("jumuahClosesLabel", "Verification closes", "يغلق التأكيد",
    "تصدیق بند")
add("settingsHijriDayOffset", "{days} day", "{days} يوم", "{days} دن",
    {"days": "String"})
add("countdownJustNow", "just now", "الآن", "ابھی")
add("countdownMinutesAgo", "{minutes} min ago", "قبل {minutes} دقيقة",
    "{minutes} منٹ پہلے", {"minutes": "int"})
add("countdownHoursAgo", "{hours} h ago", "قبل {hours} ساعة",
    "{hours} گھنٹے پہلے", {"hours": "int"})
add("countdownDaysAgo", "{days} d ago", "قبل {days} يوم", "{days} دن پہلے",
    {"days": "int"})


def build(lang: str, index: int) -> dict:
    out: dict = {"@@locale": lang}
    for key, entry in T.items():
        en, ar, ur, ph = entry
        value = (en, ar, ur)[index]
        # A placeholder present in English but dropped in a translation would
        # render as literal text; catching it here is cheaper than in review.
        for name in ph:
            assert "{" + name + "}" in value, \
                f"{key} [{lang}] is missing placeholder {{{name}}}"
        out[key] = value
        meta: dict = {}
        if ph:
            meta["placeholders"] = {n: {"type": t} for n, t in ph.items()}
        if index == 0:
            meta.setdefault("description", key)
            out["@" + key] = meta
        elif ph:
            out["@" + key] = meta
    return out


def unused_placeholders(value: str) -> set:
    return set(re.findall(r"\{(\w+)\}", value))


for key, (en, ar, ur, ph) in T.items():
    for lang, value in (("en", en), ("ar", ar), ("ur", ur)):
        extra = unused_placeholders(value) - set(ph)
        assert not extra, f"{key} [{lang}] uses undeclared placeholder {extra}"

for lang, index in (("en", 0), ("ar", 1), ("ur", 2)):
    path = L10N / f"app_{lang}.arb"
    existing = json.loads(path.read_text()) if path.exists() else {}
    merged = {**existing, **build(lang, index)}
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n")
    print(f"{path}: {len([k for k in merged if not k.startswith('@')])} keys")
