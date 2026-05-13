import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_models/user_model.dart'; // Dùng Model chung

void main() => runApp(MaterialApp(home: HomeScreen()));

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  User? user;

  // Hàm gọi API từ Backend
  Future<void> fetchData() async {
    // Lưu ý: Nếu dùng trình giả lập Android, hãy thay 'localhost' bằng '10.0.2.2'
    final response = await http.get(Uri.parse('http://localhost:8080/user'));

    if (response.statusCode == 200) {
      setState(() {
        user = User.fromJson(jsonDecode(response.body));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Flutter Fullstack Dart')),
      body: Center(
        child: user == null
            ? Text('Chưa có dữ liệu')
            : Text('Xin chào: ${user!.name} (ID: ${user!.id})'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: fetchData,
        child: Icon(Icons.refresh),
      ),
    );
  }
}