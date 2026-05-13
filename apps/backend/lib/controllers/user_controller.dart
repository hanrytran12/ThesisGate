import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shared_models/user_model.dart';

class UserController {
  // Hàm xử lý logic lấy thông tin User
  Future<Response> getUser(Request request) async {
    final user = User(id: '1', name: 'Gemini AI User');
    return Response.ok(
      jsonEncode(user.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }
}
