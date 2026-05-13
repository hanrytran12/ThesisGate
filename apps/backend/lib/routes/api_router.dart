import 'package:shelf_router/shelf_router.dart';
import '../controllers/user_controller.dart';

class ApiRouter {
  final UserController _userController = UserController();

  Router get router {
    final router = Router();

    // Định nghĩa các endpoints tại đây
    router.get('/user', _userController.getUser);

    return router;
  }
}
