import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_blocks/app_state.dart';
import 'package:focus_blocks/main.dart';
import 'package:focus_blocks/models.dart';
import 'package:focus_blocks/storage.dart';

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
}
