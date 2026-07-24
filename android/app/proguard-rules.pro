# Release build shrinking rules.
#
# R8 removes anything it cannot prove is reachable. Several things in this app
# are reached only reflectively or from native code, so they must be kept
# explicitly — without these rules the release build compiles cleanly and then
# fails at runtime, which is the worst kind of failure to discover after
# shipping.

# Flutter engine and embedding.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# The lock screen's Dart entrypoint is looked up by name from native code, so
# nothing in the bytecode references it and R8 would otherwise strip it. The
# symptom is a blank white lock screen in release builds only.
-keepclassmembers class * {
    @io.flutter.embedding.engine.dart.DartExecutor$DartEntrypoint *;
}

# Our blocking service and lock activity are instantiated by the Android
# framework from the manifest, not by our own code.
-keep class com.prayerlock.prayer_lock.blocking.AppBlockerService { *; }
-keep class com.prayerlock.prayer_lock.blocking.LockScreenActivity { *; }
-keep class com.prayerlock.prayer_lock.MainActivity { *; }

# flutter_local_notifications deserialises scheduled notifications from disk
# via Gson after a reboot; obfuscating these classes breaks rescheduling.
-keep class com.dexterous.** { *; }

# Gson, used by flutter_local_notifications to persist the pending-notification
# list.
#
# Gson resolves a generic type by reading the signature of an anonymous
# TypeToken subclass — `new TypeToken<ArrayList<Foo>>() {}` — through
# getGenericSuperclass(). R8 erases that information unless all three
# attributes below are preserved, and the failure is not at startup but at the
# moment a notification is *saved*:
#
#   IllegalStateException: TypeToken must be created with a type argument
#     at FlutterLocalNotificationsPlugin.saveScheduledNotification
#
# Every scheduled notification after the first then fails to persist, so the
# app reports "Only 1 of 200 prayer notifications could be scheduled" and the
# user gets no prayer reminders at all — while the app otherwise looks fine.
-keepattributes Signature,InnerClasses,EnclosingMethod
-keepattributes *Annotation*,RuntimeVisibleAnnotations,AnnotationDefault
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.gson.**

# WorkManager and Room.
#
# WorkManager initialises itself from a ContentProvider
# (androidx.startup.InitializationProvider) *before* any activity exists, and
# the first thing it does is open a Room database. Room locates the generated
# implementation of a database by name — Class.forName(canonicalName + "_Impl")
# — so obfuscating the database class makes that lookup fail, and the app dies
# during Application startup with:
#
#   Unable to get provider androidx.startup.InitializationProvider
#   Caused by: Failed to create an instance of class
#              androidx.work.impl.WorkDatabase
#
# There is no partial version of this failure: it happens on every launch of
# every release build, before Flutter starts.
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class androidx.startup.** { *; }
# Room resolves these by name, so the names themselves must survive.
-keepnames class * extends androidx.room.RoomDatabase
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class **_Impl { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# Our own background classes. The two receivers are declared in the manifest
# and kept automatically, but ScheduleMaintenanceWorker is not — WorkManager
# instantiates it reflectively from the class name it stored when the job was
# enqueued. If R8 renames it, the repair job that re-arms the prayer alarm
# chain silently stops running, which looks like blocking randomly dying days
# later.
-keep class com.prayerlock.prayer_lock.scheduling.** { *; }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }

# SQLCipher, behind sqflite_sqlcipher. The Java classes are bound to
# libsqlcipher.so through JNI, which R8 cannot see, and the encrypted prayer
# database is opened during startup before the first frame.
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }
-dontwarn net.sqlcipher.**
-dontwarn net.zetetic.**

# Third-party plugins whose entry points are resolved reflectively by the
# Flutter plugin registrant. The io.flutter.plugins rule above covers only
# first-party plugins, not these.
-keep class com.baseflow.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class xyz.luan.audioplayers.** { *; }
-keep class dev.fluttercommunity.** { *; }

# Desugared java.time, used for exact alarm scheduling.
-dontwarn java.time.**
-dontwarn sun.misc.**
