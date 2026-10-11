import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:student_budget_beginner/main.dart';

Future<void> openBudget(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MyApp());
  await tester.enterText(find.byType(TextField).at(0), '65000001');
  await tester.enterText(find.byType(TextField).at(1), 'Demo@1234');
  await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
  await tester.pumpAndSettle();
}

Future<void> fillPlan(WidgetTester tester, List<String> values) async {
  for (int i = 0; i < values.length; i++) {
    await tester.enterText(find.byType(TextField).at(i), values[i]);
  }
  await tester.tap(find.widgetWithText(ElevatedButton, 'คำนวณงบประมาณ'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rejects invalid student ID and wrong password', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField).at(0), '123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('กรอกรหัสนิสิตเป็นตัวเลข 8 หลัก'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '65000001');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('รหัสนิสิตหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
  });

  testWidgets('calculates budget and has no bottom navigation', (tester) async {
    await openBudget(tester);
    await fillPlan(tester, ['9000', '3000', '1500', '30']);
    expect(find.text('150.00 บาท'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('rounds down daily money and shows shortfall', (tester) async {
    await openBudget(tester);
    await fillPlan(tester, ['100', '0', '0', '3']);
    expect(find.text('33.33 บาท'), findsOneWidget);
    await fillPlan(tester, ['1000', '900', '200', '30']);
    expect(find.text('0.00 บาท'), findsOneWidget);
    expect(find.text('เงินไม่พอ ขาดอีก 100.00 บาท'), findsOneWidget);
  });

  testWidgets('rejects invalid amounts and days', (tester) async {
    await openBudget(tester);
    for (final amount in ['', '-1', 'NaN', 'Infinity', '1.234', '1000001']) {
      await fillPlan(tester, [amount, '0', '0', '30']);
      expect(find.textContaining('กรอกเงินทุกช่อง'), findsOneWidget);
      expect(find.text('ใช้ได้วันละ'), findsNothing);
    }
    for (final days in ['0', '-1', '1.5', '367']) {
      await fillPlan(tester, ['100', '0', '0', days]);
      expect(find.text('กรอกจำนวนวันเป็นจำนวนเต็ม 1–366 วัน'), findsOneWidget);
    }
  });

  testWidgets('hides stale result when editing', (tester) async {
    await openBudget(tester);
    await fillPlan(tester, ['100', '0', '0', '3']);
    await tester.enterText(find.byType(TextField).at(0), '200');
    await tester.pumpAndSettle();
    expect(find.text('33.33 บาท'), findsNothing);
  });

  testWidgets('saves plan and restores after logout', (tester) async {
    await openBudget(tester);
    await fillPlan(tester, ['9000', '3000', '1500', '30']);
    await tester.tap(find.widgetWithText(OutlinedButton, 'บันทึกแผนในเครื่อง'));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกแผนในเครื่องแล้ว'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('beginner.demo.plan'),
        ['9000', '3000', '1500', '30']);
    expect(prefs.getKeys(), {'beginner.demo.plan'});
    await tester.tap(find.text('ตั้งค่า / ข้อมูลผู้ใช้'));
    await tester.pumpAndSettle();
    expect(find.textContaining('รหัสนิสิต: 65000001'), findsOneWidget);
    await tester.tap(find.text('กลับหน้าคำนวณ'));
    await tester.pumpAndSettle();
    expect(find.text('150.00 บาท'), findsOneWidget);
    await tester.tap(find.text('ตั้งค่า / ข้อมูลผู้ใช้'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '65000001');
    await tester.enterText(find.byType(TextField).at(1), 'Demo@1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('150.00 บาท'), findsOneWidget);
    expect(find.text('โหลดแผนล่าสุดจากเครื่องแล้ว'), findsOneWidget);
  });

  testWidgets('fits small screen without layout exception', (tester) async {
    await openBudget(tester);
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
