import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'พอดี — งบประมาณนิสิต',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFAD4700),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F4F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF343434),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF58220),
            foregroundColor: const Color(0xFF343434),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
        ),
      ),
      home: const BudgetApp(),
    );
  }
}

class BudgetApp extends StatefulWidget {
  const BudgetApp({super.key});

  @override
  State<BudgetApp> createState() => _BudgetAppState();
}

class _BudgetAppState extends State<BudgetApp> {
  // ใช้ตัวเลขเลือกหน้าที่จะแสดง แล้วเรียก setState ให้หน้าจอวาดใหม่
  // 0 = เข้าสู่ระบบ, 1 = คำนวณ, 2 = ตั้งค่า ไม่มีแถบเมนูด้านล่าง
  int page = 0;
  final studentController = TextEditingController();
  final passwordController = TextEditingController();
  final incomeController = TextEditingController();
  final expenseController = TextEditingController();
  final savingController = TextEditingController();
  final daysController = TextEditingController();

  String loginError = '';
  String budgetError = '';
  String storageMessage = '';
  bool hasResult = false;
  bool busy = false;
  int remainingSatang = 0;
  int dailySatang = 0;

  // บัญชีนี้เป็นข้อมูลจำลองสำหรับส่งงาน ไม่ใช่บัญชีมหาวิทยาลัยจริง
  Future<void> login() async {
    final studentId = studentController.text.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(studentId)) {
      setState(() => loginError = 'กรอกรหัสนิสิตเป็นตัวเลข 8 หลัก');
      return;
    }
    if (studentId != '65000001' || passwordController.text != 'Demo@1234') {
      setState(() => loginError = 'รหัสนิสิตหรือรหัสผ่านไม่ถูกต้อง');
      return;
    }
    setState(() {
      page = 1;
      loginError = '';
      busy = true;
    });
    passwordController.clear();
    await loadPlan();
    if (mounted) setState(() => busy = false);
  }

  // รับจำนวนเงินไม่ติดลบ สูงสุด 1,000,000 บาท และทศนิยมไม่เกิน 2 ตำแหน่ง
  // เก็บเงินเป็นจำนวนเต็มหน่วยสตางค์ เพื่อไม่ให้ทศนิยมคลาดเคลื่อนตอนลบ
  int? readMoney(String text) {
    final input = text.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) return null;
    final value = double.tryParse(input);
    if (value == null || !value.isFinite || value > 1000000) return null;
    return (value * 100).round();
  }

  bool calculateBudget() {
    final income = readMoney(incomeController.text);
    final expense = readMoney(expenseController.text);
    final saving = readMoney(savingController.text);
    final days = int.tryParse(daysController.text.trim());

    if (income == null || expense == null || saving == null) {
      setState(() {
        hasResult = false;
        budgetError =
            'กรอกเงินทุกช่องเป็น 0–1,000,000 บาท ทศนิยมไม่เกิน 2 ตำแหน่ง';
      });
      return false;
    }
    if (days == null || days < 1 || days > 366) {
      setState(() {
        hasResult = false;
        budgetError = 'กรอกจำนวนวันเป็นจำนวนเต็ม 1–366 วัน';
      });
      return false;
    }

    setState(() {
      remainingSatang = income - expense - saving;
      // ~/ คือหารเอาจำนวนเต็ม ปัดงบลงให้ไม่ใช้เกินเงินที่เหลือ
      dailySatang = remainingSatang > 0 ? remainingSatang ~/ days : 0;
      hasResult = true;
      budgetError = '';
    });
    return true;
  }

  // ส่วนเสริม: บันทึกเฉพาะตัวเลข 4 ช่องไว้ในเครื่อง ไม่เก็บรหัสผ่าน
  // await หมายถึงรอให้การอ่าน/เขียนเสร็จก่อนทำบรรทัดถัดไป
  Future<void> loadPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList('beginner.demo.plan');
      if (!mounted) return;
      if (values != null && values.length == 4) {
        incomeController.text = values[0];
        expenseController.text = values[1];
        savingController.text = values[2];
        daysController.text = values[3];
        if (calculateBudget()) {
          setState(() => storageMessage = 'โหลดแผนล่าสุดจากเครื่องแล้ว');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => storageMessage = 'อ่านแผนเดิมไม่ได้ ยังสามารถคำนวณใหม่ได้');
      }
    }
  }

  Future<void> savePlan() async {
    setState(() => storageMessage = '');
    if (!calculateBudget()) return;
    setState(() => busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setStringList('beginner.demo.plan', [
        incomeController.text.trim(),
        expenseController.text.trim(),
        savingController.text.trim(),
        daysController.text.trim(),
      ]);
      if (!mounted) return;
      setState(() {
        storageMessage =
            saved ? 'บันทึกแผนในเครื่องแล้ว' : 'บันทึกไม่สำเร็จ ลองอีกครั้ง';
      });
    } catch (_) {
      if (mounted) {
        setState(() => storageMessage = 'บันทึกไม่สำเร็จ แต่ยังคำนวณได้');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void logout() {
    setState(() {
      page = 0;
      studentController.clear();
      passwordController.clear();
      incomeController.clear();
      expenseController.clear();
      savingController.clear();
      daysController.clear();
      loginError = '';
      budgetError = '';
      storageMessage = '';
      hasResult = false;
    });
  }

  // ทำช่องกรอกเป็นฟังก์ชันเดียว เพื่อลดการเขียนโค้ดซ้ำ 4 ครั้ง
  Widget budgetInput(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: !busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {
          hasResult = false;
          budgetError = '';
          storageMessage = '';
        }),
      ),
    );
  }

  Widget loginPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('พอดี',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const Text('วางแผนงบประมาณสำหรับนิสิต\nโครงงานสำหรับมหาวิทยาลัยนเรศวร'),
        const SizedBox(height: 24),
        TextField(
          controller: studentController,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'รหัสนิสิต 8 หลัก'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'รหัสผ่าน'),
        ),
        if (loginError.isNotEmpty)
          Text(loginError, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: login, child: const Text('เข้าสู่ระบบ')),
        const SizedBox(height: 20),
        const Text(
            'บัญชีทดลอง: 65000001\nรหัสผ่าน: Demo@1234\nใช้ข้อมูลสมมติเท่านั้น ไม่เชื่อมบัญชีมหาวิทยาลัย'),
      ],
    );
  }

  Widget budgetPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: busy ? null : () => setState(() => page = 2),
          child: const Text('ตั้งค่า / ข้อมูลผู้ใช้'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.notifications_active),
          label: const Text('ตั้งแจ้งเตือนค่าน้ำ ค่าไฟ ค่าหอพัก'),
          onPressed: busy
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BillReminderPage(),
                    ),
                  );
                },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.group_add),
          label: const Text('หารค่าใช้จ่ายกลุ่ม (PromptPay QR)'),
          onPressed: busy
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GroupSplitPage(),
                    ),
                  );
                },
        ),
        const SizedBox(height: 16),
        // เพิ่มปุ่มนี้ใน budgetPage() ต่อจากปุ่ม "หารค่าใช้จ่ายกลุ่ม (PromptPay QR)"
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.bar_chart),
          label: const Text('ดูสถิติ & ส่งออกรายงาน (PDF/Excel)'),
          onPressed: (!hasResult || busy)
              ? null
              : () {
                  final income =
                      (readMoney(incomeController.text) ?? 0) / 100.0;
                  final expense =
                      (readMoney(expenseController.text) ?? 0) / 100.0;
                  final saving =
                      (readMoney(savingController.text) ?? 0) / 100.0;
                  final days = int.tryParse(daysController.text.trim()) ?? 1;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExpenseStatisticsPage(
                        income: income,
                        expense: expense,
                        saving: saving,
                        remaining: remainingSatang / 100.0,
                        daily: dailySatang / 100.0,
                        days: days,
                      ),
                    ),
                  );
                },
        ),
        const Text('วางแผนเงินในรอบนี้',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text(
            'ใส่ยอดรวมของช่วงที่ต้องการวางแผน\nช่องที่ไม่มีค่าใช้จ่ายหรือเงินออม ให้กรอก 0'),
        const SizedBox(height: 20),
        budgetInput('รายรับทั้งหมด (บาท)', incomeController),
        budgetInput('รายจ่ายประจำรวม (บาท)', expenseController),
        budgetInput('เงินที่ต้องการออม (บาท)', savingController),
        budgetInput('จำนวนวันที่ต้องใช้เงิน', daysController),
        if (budgetError.isNotEmpty)
          Text(budgetError, style: const TextStyle(color: Colors.red)),
        ElevatedButton(
          onPressed: busy
              ? null
              : () {
                  setState(() => storageMessage = '');
                  calculateBudget();
                },
          child: const Text('คำนวณงบประมาณ'),
        ),
        const SizedBox(height: 12),
        if (hasResult)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF343434),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ใช้ได้วันละ',
                    style: TextStyle(color: Colors.white)),
                Text(
                  '${(dailySatang / 100).toStringAsFixed(2)} บาท',
                  style: const TextStyle(
                      color: Color(0xFFFF9B45),
                      fontSize: 30,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  remainingSatang < 0
                      ? 'เงินไม่พอ ขาดอีก ${(-remainingSatang / 100).toStringAsFixed(2)} บาท'
                      : 'เงินสำหรับใช้จ่าย ${(remainingSatang / 100).toStringAsFixed(2)} บาท',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : savePlan,
          child: Text(busy ? 'กำลังอ่านหรือบันทึก…' : 'บันทึกแผนในเครื่อง'),
        ),
        if (storageMessage.isNotEmpty) Text(storageMessage),
      ],
    );
  }

  Widget settingsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ข้อมูลผู้ใช้',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('รหัสนิสิต: 65000001\nประเภทบัญชี: บัญชีทดลอง'),
        const SizedBox(height: 24),
        const Text(
            'เกี่ยวกับแอป\nพอดี เวอร์ชันฝึกหัด 1.0\nคำนวณงบรายวันจากรายรับ หักรายจ่ายประจำและเงินออม'),
        const SizedBox(height: 12),
        const Text(
            'บันทึกเฉพาะแผนล่าสุดในเครื่องนี้\nก่อนออกจากระบบ ให้บันทึกแผนที่ต้องการเก็บไว้'),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => setState(() => page = 1),
          child: const Text('กลับหน้าคำนวณ'),
        ),
        OutlinedButton(onPressed: logout, child: const Text('ออกจากระบบ')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = loginPage();
    String title = 'เข้าสู่ระบบ';
    if (page == 1) {
      content = budgetPage();
      title = 'คำนวณงบประมาณ';
    } else if (page == 2) {
      content = settingsPage();
      title = 'ตั้งค่า';
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    studentController.dispose();
    passwordController.dispose();
    incomeController.dispose();
    expenseController.dispose();
    savingController.dispose();
    daysController.dispose();
    super.dispose();
  }
}

class BillReminderPage extends StatefulWidget {
  const BillReminderPage({super.key});

  @override
  State<BillReminderPage> createState() => _BillReminderPageState();
}

class _BillReminderPageState extends State<BillReminderPage> {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  final TextEditingController detailController = TextEditingController();

  String billType = 'ค่าน้ำประปา';
  DateTime? dueDate;
  int daysBefore = 1;
  bool ready = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    initializeNotifications();
  }

  Future<void> initializeNotifications() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

      const settings = InitializationSettings(
        android: AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        ),
        iOS: DarwinInitializationSettings(),
      );

      await notifications.initialize(settings);

      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await android?.requestNotificationsPermission();

      if (mounted) {
        setState(() {
          ready = true;
          message = 'พร้อมตั้งค่าการแจ้งเตือน';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = 'เริ่มระบบแจ้งเตือนไม่สำเร็จ: $e';
        });
      }
    }
  }

  Future<void> selectDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: dueDate ?? DateTime.now().add(const Duration(days: 2)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(
        const Duration(days: 366),
      ),
      helpText: 'เลือกวันครบกำหนดชำระ',
    );

    if (selected != null && mounted) {
      setState(() {
        dueDate = selected;
        message = '';
      });
    }
  }

  Future<void> scheduleReminder() async {
    if (!ready) {
      setState(() {
        message = 'ระบบแจ้งเตือนยังไม่พร้อม';
      });
      return;
    }

    if (dueDate == null) {
      setState(() {
        message = 'กรุณาเลือกวันครบกำหนดชำระ';
      });
      return;
    }

    final detail = detailController.text.trim();

    if (detail.isEmpty) {
      setState(() {
        message = 'กรุณากรอกรายละเอียดหรือจำนวนเงิน';
      });
      return;
    }

    final reminderDate = dueDate!.subtract(
      Duration(days: daysBefore),
    );

    // แจ้งเตือนเวลา 09:00 น. ตามเวลาไทย
    final reminderTime = tz.TZDateTime(
      tz.local,
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
      9,
    );

    if (!reminderTime.isAfter(tz.TZDateTime.now(tz.local))) {
      setState(() {
        message = 'วันแจ้งเตือนผ่านไปแล้ว กรุณาเลือกวันครบกำหนดใหม่ '
            'หรือปรับจำนวนวันแจ้งเตือนล่วงหน้า';
      });
      return;
    }

    try {
      final id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

      await notifications.zonedSchedule(
        id,
        'แจ้งเตือนการชำระเงิน: $billType',
        '$detail ถึงกำหนดชำระวันที่ '
            '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}',
        reminderTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'bill_reminder_channel',
            'แจ้งเตือนวันครบกำหนดชำระ',
            channelDescription: 'แจ้งเตือนค่าน้ำ ค่าไฟ ค่าหอพัก '
                'และค่าบริการรายเดือน',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

      if (mounted) {
        setState(() {
          message = 'ตั้งแจ้งเตือน $billType สำเร็จ '
              'วันที่ ${reminderTime.day}/'
              '${reminderTime.month}/'
              '${reminderTime.year} เวลา 09:00 น.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = 'ตั้งแจ้งเตือนไม่สำเร็จ: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('แจ้งเตือนค่าบริการ'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ตั้งค่าแจ้งเตือนล่วงหน้า',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'กำหนดวันชำระค่าน้ำ ค่าไฟ ค่าหอพัก '
                'หรือค่าบริการรายเดือน',
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: billType,
                decoration: const InputDecoration(
                  labelText: 'ประเภทค่าใช้จ่าย',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'ค่าน้ำประปา',
                    child: Text('ค่าน้ำประปา'),
                  ),
                  DropdownMenuItem(
                    value: 'ค่าไฟฟ้า',
                    child: Text('ค่าไฟฟ้า'),
                  ),
                  DropdownMenuItem(
                    value: 'ค่าหอพัก',
                    child: Text('ค่าหอพัก'),
                  ),
                  DropdownMenuItem(
                    value: 'ค่าบริการรายเดือน',
                    child: Text('ค่าบริการรายเดือน'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      billType = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: detailController,
                decoration: const InputDecoration(
                  labelText: 'รายละเอียด / จำนวนเงิน',
                  hintText: 'เช่น 650 บาท',
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: selectDueDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  dueDate == null
                      ? 'เลือกวันครบกำหนดชำระ'
                      : 'วันครบกำหนด '
                          '${dueDate!.day}/'
                          '${dueDate!.month}/'
                          '${dueDate!.year}',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: daysBefore,
                decoration: const InputDecoration(
                  labelText: 'แจ้งเตือนล่วงหน้า',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 0,
                    child: Text('วันครบกำหนด'),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text('1 วันก่อน'),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text('3 วันก่อน'),
                  ),
                  DropdownMenuItem(
                    value: 7,
                    child: Text('7 วันก่อน'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      daysBefore = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: ready ? scheduleReminder : null,
                icon: const Icon(Icons.notifications_active),
                label: const Text('บันทึกการแจ้งเตือน'),
              ),
              const SizedBox(height: 16),
              if (message.isNotEmpty)
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.deepOrange,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// 1. หน้าจอระบบหารค่าใช้จ่ายกลุ่ม
class GroupSplitPage extends StatefulWidget {
  const GroupSplitPage({super.key});

  @override
  State<GroupSplitPage> createState() => _GroupSplitPageState();
}

class _GroupSplitPageState extends State<GroupSplitPage> {
  final titleController = TextEditingController();
  final totalAmountController = TextEditingController();
  final peopleCountController = TextEditingController();
  final promptPayController = TextEditingController();

  double perPerson = 0.0;
  String qrData = '';
  String errorMessage = '';

  void calculateAndGenerateQR() {
    final title = titleController.text.trim();
    final total = double.tryParse(totalAmountController.text.trim());
    final count = int.tryParse(peopleCountController.text.trim());
    final promptPay = promptPayController.text.trim();

    if (title.isEmpty || total == null || count == null || promptPay.isEmpty) {
      setState(() {
        errorMessage = 'กรุณากรอกข้อมูลให้ครบถ้วน';
        qrData = '';
      });
      return;
    }

    if (total <= 0 || count <= 0) {
      setState(() {
        errorMessage = 'จำนวนเงินและจำนวนคนต้องมากกว่า 0';
        qrData = '';
      });
      return;
    }

    if (!RegExp(r'^\d{10}$').hasMatch(promptPay) &&
        !RegExp(r'^\d{13}$').hasMatch(promptPay)) {
      setState(() {
        errorMessage = 'กรอกเบอร์ PromptPay เป็นตัวเลข 10 หรือ 13 หลัก';
        qrData = '';
      });
      return;
    }

    final calculated = total / count;
    // เรียกใช้ Helper สร้าง EMVCo Payload
    final payload = PromptPayHelper.generatePayload(promptPay, calculated);

    setState(() {
      perPerson = calculated;
      qrData = payload;
      errorMessage = '';
    });
  }

  @override
  void dispose() {
    titleController.dispose();
    totalAmountController.dispose();
    peopleCountController.dispose();
    promptPayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('หารค่าใช้จ่ายกลุ่ม'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'หารค่าอาหาร / ค่าทริป',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อรายการ (เช่น ค่าชาบู, ค่าทริปบางแสน)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: totalAmountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'ยอดเงินรวมทั้งหมด (บาท)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: peopleCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'จำนวนคนหาร (รวมตัวคุณเอง)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptPayController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'เบอร์ PromptPay / เลขบัตรประชาชน ผู้รับเงิน',
                  hintText: 'เช่น 0812345678',
                ),
              ),
              const SizedBox(height: 16),
              if (errorMessage.isNotEmpty)
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_2),
                label: const Text('คำนวณและสร้าง QR Code'),
                onPressed: calculateAndGenerateQR,
              ),
              const SizedBox(height: 24),
              if (qrData.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'รายการ: ${titleController.text}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ต้องจ่ายคนละ ${perPerson.toStringAsFixed(2)} บาท',
                        style: const TextStyle(
                          fontSize: 22,
                          color: Color(0xFFAD4700),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 220.0,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ให้เพื่อนสแกน QR Code นี้เพื่อโอนเงินได้ทันที',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PromptPayHelper {
  static String generatePayload(String target, double amount) {
    String cleanTarget = target.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanTarget.length == 10 && cleanTarget.startsWith('0')) {
      cleanTarget = '0066${cleanTarget.substring(1)}';
    }

    String targetType =
        cleanTarget.length == 13 && cleanTarget.startsWith('0066')
            ? '01'
            : '02';
    String targetLength = cleanTarget.length.toString().padLeft(2, '0');

    String subTag00 = '0016A000000677010111';
    String subTagTarget = '$targetType$targetLength$cleanTarget';

    String merchantInfo = '$subTag00$subTagTarget';
    String tag29Length = merchantInfo.length.toString().padLeft(2, '0');
    String tag29 = '29$tag29Length$merchantInfo';

    String tag54 = '';
    if (amount > 0) {
      String amountStr = amount.toStringAsFixed(2);
      String amountLength = amountStr.length.toString().padLeft(2, '0');
      tag54 = '54$amountLength$amountStr';
    }

    String rawData =
        '000201010212' + tag29 + '5303764' + tag54 + '5802TH' + '6304';

    int crc = 0xFFFF;
    for (int i = 0; i < rawData.length; i++) {
      crc ^= rawData.codeUnitAt(i) << 8;
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }

    String crcHex = crc.toRadixString(16).toUpperCase().padLeft(4, '0');
    return rawData + crcHex;
  }
}
// part4

class ReportExportService {
  // ฟังก์ชันส่งออกเป็น PDF
  // ฟังก์ชันส่งออกเป็น PDF (ฉบับแก้ไขรองรับภาษาไทย)
  static Future<void> exportToPdf({
    required double income,
    required double expense,
    required double saving,
    required double remaining,
    required double daily,
    required int days,
  }) async {
    final pdf = pw.Document();

    //  โหลดฟอนต์ภาษาไทย (Sarabun) จาก Google Fonts
    final thaiFont = await PdfGoogleFonts.sarabunRegular();
    final thaiFontBold = await PdfGoogleFonts.sarabunBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        //  กำหนด Theme ของเอกสารให้ใช้ฟอนต์ภาษาไทย
        theme: pw.ThemeData.withFont(
          base: thaiFont,
          bold: thaiFontBold,
        ),
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'รายงานสรุปงบประมาณ - แอปพอดี',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                    'วันที่ออกรายงาน: ${DateTime.now().toString().split(' ')[0]}'),
                pw.Divider(),
                pw.SizedBox(height: 16),
                pw.TableHelper.fromTextArray(
                  headers: ['รายการ', 'จำนวนเงิน (บาท)'],
                  data: [
                    ['รายรับทั้งหมด', income.toStringAsFixed(2)],
                    ['รายจ่ายประจำรวม', expense.toStringAsFixed(2)],
                    ['เงินออม', saving.toStringAsFixed(2)],
                    ['เงินคงเหลือใช้จ่าย', remaining.toStringAsFixed(2)],
                    ['จำนวนวันที่ใช้เงิน', '$days วัน'],
                    ['งบเฉลี่ยต่อวัน', '${daily.toStringAsFixed(2)} บาท/วัน'],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    // เปิดหน้า Preview และสั่งพิมพ์/บันทึก PDF
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Budget_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  // ฟังก์ชันส่งออกเป็น Excel (.xlsx)
  static Future<void> exportToExcel({
    required double income,
    required double expense,
    required double saving,
    required double remaining,
    required double daily,
    required int days,
  }) async {
    var excel = xl.Excel.createExcel();
    xl.Sheet sheetObject = excel['สรุปงบประมาณ'];
    excel.setDefaultSheet('สรุปงบประมาณ');

    // เขียนข้อมูลลงเซลล์
    sheetObject.appendRow(
        [xl.TextCellValue('รายการ'), xl.TextCellValue('จำนวนเงิน (บาท)')]);
    sheetObject.appendRow(
        [xl.TextCellValue('รายรับทั้งหมด'), xl.DoubleCellValue(income)]);
    sheetObject.appendRow(
        [xl.TextCellValue('รายจ่ายประจำรวม'), xl.DoubleCellValue(expense)]);
    sheetObject
        .appendRow([xl.TextCellValue('เงินออม'), xl.DoubleCellValue(saving)]);
    sheetObject.appendRow([
      xl.TextCellValue('เงินคงเหลือใช้จ่าย'),
      xl.DoubleCellValue(remaining)
    ]);
    sheetObject
        .appendRow([xl.TextCellValue('จำนวนวัน'), xl.IntCellValue(days)]);
    sheetObject.appendRow(
        [xl.TextCellValue('งบเฉลี่ยต่อวัน'), xl.DoubleCellValue(daily)]);

    // บันทึกไฟล์ลงแคชของเครื่องแล้วแชร์ผ่าน share_plus
    final fileBytes = excel.save();
    if (fileBytes != null) {
      final directory = await getTemporaryDirectory();
      final filePath =
          '${directory.path}/Budget_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      await Share.shareXFiles([XFile(filePath)],
          text: 'รายงานสรุปงบประมาณ (Excel)');
    }
  }
}

// หน้าจอ Interactive Charts & Export Report

class ExpenseStatisticsPage extends StatefulWidget {
  final double income;
  final double expense;
  final double saving;
  final double remaining;
  final double daily;
  final int days;

  const ExpenseStatisticsPage({
    super.key,
    required this.income,
    required this.expense,
    required this.saving,
    required this.remaining,
    required this.daily,
    required this.days,
  });

  @override
  State<ExpenseStatisticsPage> createState() => _ExpenseStatisticsPageState();
}

class _ExpenseStatisticsPageState extends State<ExpenseStatisticsPage> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สรุปสถิติ & รายงาน'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'สัดส่วนงบประมาณ',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('แตะที่กราฟเพื่อดูสัดส่วนเปอร์เซ็นต์แบบ Interactive'),
              const SizedBox(height: 24),

              // --- Interactive Pie Chart ---
              SizedBox(
                height: 240,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            touchedIndex = -1;
                            return;
                          }
                          touchedIndex = pieTouchResponse
                              .touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    sectionsSpace: 4,
                    centerSpaceRadius: 40,
                    sections: _generateChartSections(),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // --- คำอธิบายสัญลักษณ์สี ---
              _buildLegend(Colors.blue, 'รายจ่ายประจำ', widget.expense),
              _buildLegend(Colors.green, 'เงินออม', widget.saving),
              _buildLegend(
                  Colors.orange, 'เงินคงเหลือใช้จ่าย', widget.remaining),
              const SizedBox(height: 32),

              const Text(
                'ส่งออกรายงาน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // --- ปุ่มส่งออก PDF ---
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAD4700)),
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                label: const Text('ส่งออกรายงานเป็น PDF',
                    style: TextStyle(color: Colors.white)),
                onPressed: () {
                  ReportExportService.exportToPdf(
                    income: widget.income,
                    expense: widget.expense,
                    saving: widget.saving,
                    remaining: widget.remaining,
                    daily: widget.daily,
                    days: widget.days,
                  );
                },
              ),
              const SizedBox(height: 12),

              // --- ปุ่มส่งออก Excel ---
              OutlinedButton.icon(
                icon: const Icon(Icons.table_chart, color: Colors.green),
                label: const Text('ส่งออกรายงานเป็น Excel (.xlsx)'),
                onPressed: () {
                  ReportExportService.exportToExcel(
                    income: widget.income,
                    expense: widget.expense,
                    saving: widget.saving,
                    remaining: widget.remaining,
                    daily: widget.daily,
                    days: widget.days,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ฟังก์ชันสร้างข้อมูลแต่ละ Section ของ PieChart
  List<PieChartSectionData> _generateChartSections() {
    final total = widget.income <= 0 ? 1.0 : widget.income;

    return List.generate(3, (i) {
      final isTouched = i == touchedIndex;
      final fontSize = isTouched ? 18.0 : 14.0;
      final radius = isTouched ? 65.0 : 55.0;

      switch (i) {
        case 0:
          final pct = (widget.expense / total) * 100;
          return PieChartSectionData(
            color: Colors.blue,
            value: widget.expense,
            title: '${pct.toStringAsFixed(1)}%',
            radius: radius,
            titleStyle: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          );
        case 1:
          final pct = (widget.saving / total) * 100;
          return PieChartSectionData(
            color: Colors.green,
            value: widget.saving,
            title: '${pct.toStringAsFixed(1)}%',
            radius: radius,
            titleStyle: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          );
        case 2:
          final rem = widget.remaining > 0 ? widget.remaining : 0.0;
          final pct = (rem / total) * 100;
          return PieChartSectionData(
            color: Colors.orange,
            value: rem,
            title: '${pct.toStringAsFixed(1)}%',
            radius: radius,
            titleStyle: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          );
        default:
          throw Error();
      }
    });
  }

  Widget _buildLegend(Color color, String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text('${amount.toStringAsFixed(2)} บาท'),
        ],
      ),
    );
  }
}
