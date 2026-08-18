import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fork/main.dart';

void main() {
  testWidgets('shows the settings prompt when unconfigured', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ForkApp()));
    await tester.pumpAndSettle();

    expect(find.text('Point Fork at your fork-backend to get started.'), findsOneWidget);
  });
}
