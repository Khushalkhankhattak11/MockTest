import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_test/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('remembered admin session opens dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({
      'is_admin_logged_in': true,
      'admin_id': 'FfSqqZULtNTfNbV3o30u0gBFZ3e2',
      'admin_email': 'admin@example.com',
      'admin_name': 'Admin User',
      'admin_role': 'superAdmin',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AdminApp(firebaseReady: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Platform Performance Analytics'), findsOneWidget);
  });
}
