import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_provider.g.dart';

final Dio appDio = _buildAppDio();

Dio _buildAppDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: Duration(seconds: 3),
      sendTimeout: Duration(seconds: 3),
      receiveTimeout: Duration(seconds: 5),
    ),
  );

  dio.interceptors.add(
    RetryInterceptor(
      dio: dio,
      retries: 2,
      retryDelays: const [Duration(milliseconds: 200), Duration(seconds: 3)],
      retryEvaluator: (error, attempt) {
        print(
          "\n---\nRetrying ${DateTime.now().toString()}\n$error\nfor the $attempt. time",
        );

        if (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.badCertificate) {
          return true;
        }

        if (error.type == DioExceptionType.badResponse) {
          final statusCode = error.response?.statusCode;
          return statusCode != null && statusCode >= 500;
        }

        return false;
      },
    ),
  );

  return dio;
}

@Riverpod(keepAlive: true)
Dio dio(Ref ref) => appDio;
