// Adds the native pieces Focus Blocks needs to the platform folders that
// `flutter create` generates. Safe to run more than once.
//
//   flutter create . --platforms=ios,android,macos --org com.cisroute --project-name focus_blocks
//   dart run tool/setup_platforms.dart
//
// Android: notification permissions and receivers, core library desugaring,
//          a recent Android Gradle Plugin, and the home screen widget.
// macOS:   the menu bar item, and keeping the app alive when the window closes.
// iOS:     shows reminders while the app is open.
import 'dart:io';

void main() {
  if (!File('pubspec.yaml').existsSync() || !Directory('platform').existsSync()) {
    stderr.writeln('Run this from the focus_blocks project folder.');
    exit(1);
  }
  var ok = true;
  ok = _android() && ok;
  ok = _macos() && ok;
  ok = _ios() && ok;
  stdout.writeln(ok ? '\nAll set. Now run: flutter pub get' : '\nFinished with warnings (see above).');
}

void _say(String s) => stdout.writeln('  $s');
void _warn(String s) => stdout.writeln('  ! $s');

// ---------------------------------------------------------------- Android

bool _android() {
  stdout.writeln('Android');
  if (!Directory('android').existsSync()) {
    _say('no android folder, skipped');
    return true;
  }
  var ok = true;
  ok = _gradle() && ok;
  ok = _gradleVersions() && ok;
  ok = _manifest() && ok;
  ok = _widget() && ok;
  return ok;
}

bool _gradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final file = kts.existsSync() ? kts : (groovy.existsSync() ? groovy : null);
  if (file == null) {
    _warn('android/app/build.gradle(.kts) not found');
    return false;
  }
  final isKts = file == kts;
  var s = file.readAsStringSync();
  final flag = isKts ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
  if (!s.contains('oreLibraryDesugaringEnabled')) {
    final compileOptions = RegExp(r'compileOptions\s*\{');
    if (compileOptions.hasMatch(s)) {
      s = s.replaceFirst(compileOptions, 'compileOptions {\n        $flag');
    } else {
      s = s.replaceFirst(RegExp(r'android\s*\{'), 'android {\n    compileOptions {\n        $flag\n    }');
    }
  }
  if (!s.contains('desugar_jdk_libs')) {
    s += isKts
        ? '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        : "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n";
  }
  file.writeAsStringSync(s);
  if (!s.contains('oreLibraryDesugaringEnabled')) {
    _warn('could not turn on core library desugaring in ${file.path}; add "$flag" to compileOptions');
    return false;
  }
  _say('desugaring on in ${file.path}');
  return true;
}

/// flutter_local_notifications needs Android Gradle Plugin 8.11.1+ (and so Gradle 8.13+).
bool _gradleVersions() {
  for (final path in ['android/settings.gradle.kts', 'android/settings.gradle']) {
    final f = File(path);
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    final re = RegExp(r'''(id\s*\(?\s*["']com\.android\.application["']\s*\)?\s*version\s*["'])([\d.]+)(["'])''');
    final m = re.firstMatch(s);
    if (m == null) {
      _warn('Android Gradle Plugin version not found in $path; make sure it is 8.11.1 or newer');
      return false;
    }
    if (_older(m.group(2)!, '8.11.1')) {
      s = s.replaceFirst(re, '${m.group(1)}8.11.1${m.group(3)}');
      f.writeAsStringSync(s);
      _say('Android Gradle Plugin ${m.group(2)} -> 8.11.1');
    } else {
      _say('Android Gradle Plugin ${m.group(2)} is fine');
    }
    break;
  }
  final wrapper = File('android/gradle/wrapper/gradle-wrapper.properties');
  if (wrapper.existsSync()) {
    var s = wrapper.readAsStringSync();
    final re = RegExp(r'gradle-([\d.]+)-(all|bin)\.zip');
    final m = re.firstMatch(s);
    if (m != null && _older(m.group(1)!, '8.13')) {
      s = s.replaceFirst(re, 'gradle-8.14.3-${m.group(2)}.zip');
      wrapper.writeAsStringSync(s);
      _say('Gradle ${m.group(1)} -> 8.14.3');
    }
  }
  return true;
}

bool _older(String a, String b) {
  final x = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final y = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? x[i] : 0;
    final q = i < y.length ? y[i] : 0;
    if (p != q) return p < q;
  }
  return false;
}

const _permissions = '''
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
''';

const _receivers = '''
        <!-- Focus Blocks: scheduled reminders and notification buttons -->
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
''';

const _widgetReceiver = '''
        <!-- Focus Blocks: home screen widget -->
        <receiver android:name=".FocusWidgetProvider" android:exported="true" android:label="Focus Blocks">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/focus_widget_info" />
        </receiver>
''';

bool _manifest() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    _warn('AndroidManifest.xml not found');
    return false;
  }
  var s = f.readAsStringSync();
  if (!s.contains('USE_EXACT_ALARM')) {
    final i = s.indexOf('<application');
    if (i < 0) {
      _warn('no <application> in AndroidManifest.xml');
      return false;
    }
    s = s.substring(0, i) + _permissions.trimLeft() + '\n    ' + s.substring(i);
  }
  if (!s.contains('ScheduledNotificationReceiver')) {
    final i = s.lastIndexOf('</application>');
    s = s.substring(0, i) + _receivers.trimLeft() + '    ' + s.substring(i);
  }
  if (!s.contains('FocusWidgetProvider')) {
    final i = s.lastIndexOf('</application>');
    s = s.substring(0, i) + _widgetReceiver.trimLeft() + '    ' + s.substring(i);
  }
  f.writeAsStringSync(s);
  _say('permissions and receivers added to AndroidManifest.xml');
  return true;
}

bool _widget() {
  File? activity;
  for (final base in ['android/app/src/main/kotlin', 'android/app/src/main/java']) {
    final d = Directory(base);
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true)) {
      if (e is File && (e.path.endsWith('MainActivity.kt') || e.path.endsWith('MainActivity.java'))) {
        activity = e;
        break;
      }
    }
    if (activity != null) break;
  }
  if (activity == null) {
    _warn('MainActivity not found, so the home screen widget was not added');
    return false;
  }
  final pkg = RegExp(r'^\s*package\s+([\w.]+)', multiLine: true).firstMatch(activity.readAsStringSync())?.group(1);
  if (pkg == null) {
    _warn('could not read the package name from ${activity.path}');
    return false;
  }
  final source = File('platform/android/FocusWidgetProvider.kt').readAsStringSync().replaceAll('__PACKAGE__', pkg);
  File("${activity.parent.path}/FocusWidgetProvider.kt").writeAsStringSync(source);
  _copyTree('platform/android/res', 'android/app/src/main/res');
  _say('home screen widget added (package $pkg)');
  return true;
}

void _copyTree(String from, String to) {
  for (final e in Directory(from).listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = e.path.substring(from.length + 1);
    final target = File('$to/$rel');
    target.parent.createSync(recursive: true);
    e.copySync(target.path);
  }
}

// ---------------------------------------------------------------- macOS

bool _macos() {
  stdout.writeln('macOS');
  if (!Directory('macos/Runner').existsSync()) {
    _say('no macos folder, skipped');
    return true;
  }
  File('platform/macos/AppDelegate.swift').copySync('macos/Runner/AppDelegate.swift');
  File('platform/macos/MainFlutterWindow.swift').copySync('macos/Runner/MainFlutterWindow.swift');
  _say('menu bar item and keep-running-on-close installed');
  return true;
}

// ---------------------------------------------------------------- iOS

bool _ios() {
  stdout.writeln('iOS');
  final f = File('ios/Runner/AppDelegate.swift');
  if (!f.existsSync()) {
    _say('no ios/Runner/AppDelegate.swift, skipped');
    return true;
  }
  var s = f.readAsStringSync();
  if (s.contains('UNUserNotificationCenter')) {
    _say('already set up');
    return true;
  }
  final launch = RegExp(r'didFinishLaunchingWithOptions[^{]*\{');
  final m = launch.firstMatch(s);
  if (m == null) {
    _warn('could not find didFinishLaunchingWithOptions in AppDelegate.swift; reminders will still work '
        'but will not show while the app is open');
    return false;
  }
  s = s.replaceRange(m.end, m.end,
      '\n    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate');
  if (!s.contains('import UserNotifications')) {
    s = s.replaceFirst('import UIKit', 'import UIKit\nimport UserNotifications');
  }
  f.writeAsStringSync(s);
  _say('notifications show while the app is open');
  return true;
}
