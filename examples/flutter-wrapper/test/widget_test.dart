import 'package:bubbl_flutter_wrapper/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Bubbl SDK wrapper smoke app', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BubblWrapperApp());

    expect(find.text('Bubbl SDK Wrapper'), findsOneWidget);
    expect(find.text('Boot'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Notification'), findsOneWidget);
  });
}
