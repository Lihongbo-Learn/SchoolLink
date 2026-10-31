import 'package:flutter_test/flutter_test.dart';
import 'package:school_link/src/app.dart';
import 'package:school_link/src/state/app_controller.dart';

void main() {
  testWidgets('shows the loading brand', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(SchoolLinkApp(controller: controller));
    expect(find.text('校联 SchoolLink'), findsOneWidget);
  });
}
