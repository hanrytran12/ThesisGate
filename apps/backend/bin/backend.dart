import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

import 'package:backend/middlewares/cors_middleware.dart';
import 'package:backend/routes/api_router.dart';

void main() async {
  // 1. Khởi tạo Router
  final apiRouter = ApiRouter();

  // 2. Thiết lập Pipeline với Middleware và Router
  final pipeline = Pipeline()
      .addMiddleware(addCorsHeaders)
      .addHandler(apiRouter.router);

  // 3. Chạy Server
  final server = await serve(pipeline, '0.0.0.0', 8080);
  print('Server đang chạy tại: http://${server.address.host}:${server.port}');
}