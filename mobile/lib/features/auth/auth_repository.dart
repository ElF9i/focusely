import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<void> _save(Map<String, dynamic> data) async {
    await storage.write(key: 'token', value: data['token']);
    await storage.write(key: 'uid', value: data['userId']);
  }

  Future<void> login(String email, String password) async {
    final r = await _dio.post('/api/auth/login', data: {'email': email, 'password': password});
    await _save(r.data);
  }

  Future<void> register(Map<String, dynamic> body) async {
    final r = await _dio.post('/api/auth/register', data: body);
    await _save(r.data);
  }

  Future<bool> isLoggedIn() async => (await storage.read(key: 'token')) != null;

  Future<void> logout() async {
    await storage.delete(key: 'token');
    await storage.delete(key: 'uid');
  }
}
