import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('ThesisGate dashboard renders title', (WidgetTester tester) async {
    await tester.pumpWidget(const ThesisGateApp());

    expect(find.text('ThesisGate'), findsWidgets);
    expect(find.text('Bắt đầu sinh file CMT'), findsOneWidget);
  });
}
