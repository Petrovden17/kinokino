import 'package:flutter_test/flutter_test.dart';
import 'package:kinokino/app.dart';

void main() {
  testWidgets('KinoKino app starts and shows its brand', (tester) async {
    await tester.pumpWidget(const KinoKinoApp());
    expect(find.text('KinoKino'), findsWidgets);
    expect(find.text('ТВОЙ ДОМАШНИЙ КИНОТЕАТР'), findsOneWidget);
  });
}
