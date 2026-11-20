import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const baseUrl = 'http://192.168.1.14:8080';
const storage = FlutterSecureStorage();

/// Adresse du serveur : celle saisie dans l'app (icone serveur de la page de connexion), sinon la valeur par defaut.
Future<String> currentBaseUrl() async {
  final custom = await storage.read(key: 'server_url');
  return (custom == null || custom.isEmpty) ? baseUrl : custom;
}

Dio createDio() {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 15),
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      options.baseUrl = await currentBaseUrl();
      final token = await storage.read(key: 'token');
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
  ));
  return dio;
}

/// Vrai si l'erreur vient d'un probleme de reseau (pas de reponse du serveur).
bool isOfflineError(Object e) =>
    e is DioException &&
    e.response == null &&
    (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout);

/// Message lisible a partir d'une erreur Dio
String errorMessage(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is String && d.isNotEmpty) return d;
    if (isOfflineError(e)) {
      return 'Serveur injoignable. Verifie le Wi-Fi, le pare-feu et l\'adresse du serveur.';
    }
    return 'Erreur reseau (${e.response?.statusCode ?? e.type.name})';
  }
  return e.toString();
}

/// Identifiant de l'utilisateur connecte (lu dans le jeton si besoin).
Future<String?> currentUid() async {
  var uid = await storage.read(key: 'uid');
  if (uid != null) return uid;
  final token = await storage.read(key: 'token');
  if (token == null) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])));
    uid = (jsonDecode(payload) as Map)['sub'] as String?;
    if (uid != null) await storage.write(key: 'uid', value: uid);
    return uid;
  } catch (_) {
    return null;
  }
}

Future<bool> pingServer(String url) async {
  try {
    final r = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      validateStatus: (_) => true,
    )).get('$url/swagger/v1/swagger.json');
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}
