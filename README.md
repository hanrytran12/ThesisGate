# ThesisGate - Fullstack Dart/Flutter Monorepo

Dự án này sử dụng kiến trúc Monorepo quản lý bởi [Melos](https://melos.invertase.dev/).

## Cấu trúc thư mục
- `apps/frontend/`: Ứng dụng Flutter (Client)
- `apps/backend/`: Ứng dụng Dart Server (API)
- `packages/shared_models/`: Models dữ liệu dùng chung cho cả Client và Server

---

## 🚀 Hướng dẫn khởi chạy cho người mới (Onboarding)

### 1. Yêu cầu hệ thống
- Đã cài đặt [Flutter SDK](https://flutter.dev/docs/get-started/install) và Dart.
- (Khuyên dùng) Nên sử dụng VS Code hoặc Android Studio.

### 2. Cài đặt môi trường
Sau khi clone project về, bạn mở Terminal tại thư mục gốc của project (thư mục chứa file này) và chạy các lệnh sau:

**Cài đặt Melos toàn hệ thống (Chỉ làm 1 lần đầu tiên):**
```bash
dart pub global activate melos
```

**Tải các thư viện gốc:**
```bash
dart pub get
```

### 3. Cài đặt & Liên kết các package (Bootstrap)
Lệnh này sẽ tự động tải toàn bộ thư viện cho frontend, backend và tự động liên kết (link) các package dùng chung lại với nhau:
```bash
dart run melos bs
```

### 4. Sinh code cho Models
Dự án sử dụng `json_serializable`, nên bạn cần chạy lệnh sinh code trước khi code:
```bash
dart run melos run build:models
```

---

## 🛠 Cách khởi chạy ứng dụng

**Chạy Backend Server:**
```bash
dart run melos run run:backend
```
*Server sẽ chạy tại: `http://localhost:8080`*

**Chạy Frontend:**
Mở thêm một Terminal mới và chạy:
```bash
dart run melos run run:frontend
```
*(Nếu bạn code frontend, khuyên dùng tính năng Run & Debug của IDE trực tiếp trên file `apps/frontend/lib/main.dart` để tận dụng Hot Reload).*