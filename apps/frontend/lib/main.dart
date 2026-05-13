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
    return Scaffold(
      body: Column(
        children: [
          _TopBar(
            active: 'dashboard',
            onDashboard: () {},
            onAbout: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutPage()),
              );
            },
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
                        child: const Text('v1.0.0', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(height: 16),
                      const Text('Tạo file CMT nhanh chóng và chính xác', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      const Text(
                        'Nhập link Google Sheet — hệ thống lo phần còn lại.',
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
                        child: Row(
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
                                label: const Text('Tạo CMT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text('Quy trình thực hiện', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Row(
                        children: const [
                          Expanded(child: _StepCard(icon: Icons.table_chart, title: '1. Chuẩn bị Sheet', desc: 'Đảm bảo danh sách sinh viên đúng định dạng cột quy định.')),
                          SizedBox(width: 16),
                          Expanded(child: _StepCard(icon: Icons.link, title: '2. Nhập Link', desc: 'Copy và dán URL Google Sheet vào thanh công cụ phía trên.')),
                          SizedBox(width: 16),
                          Expanded(child: _StepCard(icon: Icons.folder_zip, title: '3. Tải ZIP', desc: 'Hệ thống nén tất cả file CMT thành một file ZIP duy nhất.')),
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
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _TopBar(
            active: 'about',
            onDashboard: () => Navigator.of(context).pop(),
            onAbout: () {},
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            flex: 7,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                //Text('Introduction', style: TextStyle(fontSize: 12, color: Color(0xFF004AC6), fontWeight: FontWeight.w600)),
                                SizedBox(height: 12),
                                Text('⭐ ThesisGate', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
                                SizedBox(height: 12),
                                Text(
                                  'ThesisGate được phát triển với mục tiêu đơn giản hóa và tự động hóa toàn bộ quá trình tạo file CMT (Comment đánh giá đồ án tốt nghiệp) vốn tốn nhiều thời gian và dễ xảy ra sai sót khi thực hiện thủ công. \nDành riêng cho giảng viên, hội đồng chấm đồ án và các khoa đào tạo, hệ thống giúp xử lý dữ liệu một cách nhanh chóng, chính xác và nhất quán.',
                                  style: TextStyle(fontSize: 16, color: Color(0xFF434655), height: 1.6),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 5,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                'https://lh3.googleusercontent.com/aida-public/AB6AXuC14vgWYIdNIB9P2PuRoaHiQuJ86DawXSkSfwisqmvwhG9-q_EgaUqzpvcoMtrcNzx8gw1yfji-JbhVTs1dyaU2DYy16oMSoEHC5zdZUz_Z7B2Hy4RAh25qQJAJSPldxnlk6D2RpSkDPsMQbVo2cgfxUebWFf2dT9JL9_L0NGukZXWwPsU4ED-R6Xqyk9yWvERLRC2kvvC9G4Ulk__dpsXlWf45xQhJFMn-W8-tlCwzV896cDY6QA5rcjQnV5IBV_y2CMhOcpM0VRM',
                                height: 400,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Center(child: Text('⚙️ ThesisGate hoạt động như thế nào?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700))),
                      const SizedBox(height: 8),
                      //const Center(child: Text('Chỉ với một đường link Google Sheet, hệ thống sẽ:', style: TextStyle(color: Color(0xFF434655)))),
                      const SizedBox(height: 20),
                      GridView.count(
                        crossAxisCount: 4,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.05,
                        children: [
                          _workflowCard(Icons.home, '01', 'Step 1', 'Mở ứng dụng', 'Truy cập giao diện Home để bắt đầu phiên làm việc mới.'),
                          _workflowCard(Icons.link, '02', 'Step 2', 'Nhập link Google Sheet', 'Cung cấp đường dẫn nguồn dữ liệu chứa danh sách sinh viên.'),
                          _workflowCard(Icons.verified, '03', 'Step 3', 'Validate dữ liệu', 'Kiểm tra định dạng cột và quyền truy cập vào bảng tính.'),
                          _workflowCard(Icons.settings_suggest, '04', 'Step 4', 'Sinh file hàng loạt', 'Hệ thống tự động khởi tạo các file CMT theo template chuẩn.'),
                          _workflowCard(Icons.folder_zip, '05', 'Step 5', 'Export file ZIP', 'Đóng gói tất cả file đã sinh vào định dạng nén để tải xuống.'),
                          _workflowCard(Icons.history, '06', 'Step 6', 'Lưu lịch sử', 'Tự động lưu trữ thông tin phiên làm việc vào trang History.'),
                          Container(
                            decoration: BoxDecoration(color: const Color(0xFF004AC6), borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_circle_fill, color: Colors.white, size: 44),
                                  SizedBox(height: 8),
                                  Text('Bắt đầu ngay', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                                  Text('Quay lại Dashboard', style: TextStyle(color: Colors.white70)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Divider(color: Color(0xFFEDEEF0)),
                      const SizedBox(height: 20),
                      const Center(child: Text('© 2024 ThesisGate Automator. Designed for Academic Excellence.', style: TextStyle(color: Color(0xFF434655)))),
                    ],
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _workflowCard(IconData icon, String number, String step, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEEF0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0x1A004AC6), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: const Color(0xFF004AC6)),
            ),
            const Spacer(),
            Text(number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0x22000000))),
          ],
        ),
        const SizedBox(height: 10),
        Text(step, style: const TextStyle(fontSize: 12, color: Color(0xFF434655), fontWeight: FontWeight.w600)),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(desc, style: const TextStyle(fontSize: 14, color: Color(0xFF434655))),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String active;
  final VoidCallback onDashboard;
  final VoidCallback onAbout;

  const _TopBar({required this.active, required this.onDashboard, required this.onAbout});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget navItem(String label, bool isActive, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: InkWell(
          onTap: onTap,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? cs.primary : const Color(0xFF434655),
              fontWeight: FontWeight.w600,
              decoration: isActive ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FB),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(child: Text('ThesisGate', style: TextStyle(color: cs.primary, fontSize: 24, fontWeight: FontWeight.w700))),
          Row(
            children: [
              navItem('Dashboard', active == 'dashboard', onDashboard),
              navItem('History', false, () {}),
              navItem('About', active == 'about', onAbout),
            ],
          ),
          const Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.notifications_none, color: Color(0xFF434655)),
            ),
          ),
        ],
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
