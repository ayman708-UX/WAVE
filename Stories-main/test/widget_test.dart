import 'package:flutter_test/flutter_test.dart';

import 'package:audiobook_app/main.dart';

void main() {
  testWidgets('Stories bootstrap builds', (WidgetTester tester) async {
    await tester.pumpWidget(const StoriesApp());
    expect(find.text('Stories'), findsOneWidget);
  });
}
