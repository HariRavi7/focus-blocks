import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_blocks/app_state.dart';
import 'package:focus_blocks/main.dart';
import 'package:focus_blocks/models.dart';
import 'package:focus_blocks/storage.dart';
import 'package:focus_blocks/ui/pomodoro_view.dart';
import 'package:flutter/material.dart';

class _MemoryStore extends LocalStore {
  AppData data = const AppData();

  @override
  Future<AppData> load() async => data;

  @override
  Future<void> save(AppData next) async => data = next;
}

void main() {
  testWidgets('first run opens setup', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(_MemoryStore())],
        child: const FocusBlocksApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('Pomodoro starts, pauses and stops', (tester) async {
    final store = _MemoryStore()..data = const AppData(onboarded: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const MaterialApp(home: Scaffold(body: PomodoroScreen(embedded: true))),
      ),
    );
    await tester.pump();
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Subnetting');
    await tester.tap(find.text('Start 25 min focus'));
    await tester.pump();
    expect(store.data.pomodoro?.running, isTrue);
    expect(store.data.pomodoro?.label, 'Subnetting');
    expect(find.text('On: Subnetting'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(store.data.pomodoro?.running, isFalse);
    expect(find.text('PAUSED'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(store.data.pomodoro, isNull);
    await tester.pump(const Duration(seconds: 3));
  });
}
