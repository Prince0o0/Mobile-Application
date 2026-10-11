import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        const SizedBox(height: 16),
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
