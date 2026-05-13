import 'package:flutter/material.dart';

void main() {
  runApp(const ThesisGateApp());
}

class ThesisGateApp extends StatelessWidget {
  const ThesisGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ThesisGate',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFFF8F9FB),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF004AC6)),
      ),
      home: const ThesisGateDashboardPage(),
    );
  }
}

class ThesisGateDashboardPage extends StatelessWidget {
  const ThesisGateDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FB),
              boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('ThesisGate', style: TextStyle(color: cs.primary, fontSize: 24, fontWeight: FontWeight.w700)),
                ),
                Row(
                  children: [
                    _topNavItem('Dashboard', true, cs),
                    _topNavItem('History', false, cs),
                    _topNavItem('About', false, cs),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none, color: Color(0xFF434655)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFDBE1FF), borderRadius: BorderRadius.circular(999)),
                        child: const Text('ThesisGate v1.0.0', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(height: 16),
                      const Text('Tự động tạo file CMT từ Google Sheet', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      const Text(
                        'Nhập link Google Sheet để hệ thống xử lý và xuất file CMT hoàn toàn tự động.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Color(0xFF434655)),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFC3C6D7).withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Dán link Google Sheet tại đây...',
                                      filled: true,
                                      fillColor: Color(0xFFF3F4F6),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  height: 56,
                                  child: FilledButton.icon(
                                    onPressed: () {},
                                    icon: const Icon(Icons.bolt),
                                    label: const Text('Tải Dữ Liệu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            //const Text('Hơn 500 sinh viên đã sử dụng thành công', style: TextStyle(fontSize: 12, color: Color(0xFF434655))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text('Quy trình thực hiện', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Row(
                        children: const [
                          Expanded(child: _StepCard(icon: Icons.table_chart, title: '1. Chuẩn bị Google Sheet', desc: 'Hãy chắc rằng danh sách sinh viên đều được nhập đúng cột và đúng thông tin nhé.')),
                          SizedBox(width: 16),
                          Expanded(child: _StepCard(icon: Icons.link, title: '2. Dán link Google Sheet', desc: 'Copy đường dẫn Google Sheet của bạn rồi dán vào ô phía trên để hệ thống đọc dữ liệu.')),
                          SizedBox(width: 16),
                          Expanded(child: _StepCard(icon: Icons.folder_zip, title: '3. Tải file ZIP', desc: 'Hệ thống sẽ tự tạo các file CMT và nén lại cho bạn tải về chỉ trong một lần.')),
                        ],
                      ),
                      const SizedBox(height: 48),
                      const Divider(color: Color(0xFFEDEEF0)),
                      const SizedBox(height: 20),
                      const Text('© 2024 ThesisGate Automator. Designed for Academic Excellence.', style: TextStyle(color: Color(0xFF434655))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topNavItem(String label, bool active, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: TextStyle(
          color: active ? cs.primary : const Color(0xFF434655),
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _StepCard({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC3C6D7).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: const Color(0xFFDCE2F3), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: const Color(0xFF004AC6)),
          ),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF434655))),
        ],
      ),
    );
  }
}
