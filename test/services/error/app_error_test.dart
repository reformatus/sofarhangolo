import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/services/error/app_error.dart';
import 'package:sofarhangolo/services/error/network_error.dart';

void main() {
  group('AppError.from', () {
    test('classifies unknown Dio socket failures as network errors', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/asset.pdf'),
        type: DioExceptionType.unknown,
        error: SocketException('Failed host lookup'),
        message: 'Failed host lookup',
      );

      final appError = AppError.from(error);

      expect(appError.category, AppErrorCategory.network);
      expect(appError.shouldShowTechnicalDetails, isFalse);
      expect(appError.stack, isNull);
    });

    test('classifies raw socket failures as network errors', () {
      final appError = AppError.from(SocketException('Network is unreachable'));

      expect(appError.category, AppErrorCategory.network);
      expect(appError.shouldShowTechnicalDetails, isFalse);
    });
  });

  group('isRetryableDioException', () {
    test('retries unknown Dio socket failures', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/asset.pdf'),
        type: DioExceptionType.unknown,
        error: SocketException('Failed host lookup'),
      );

      expect(isRetryableDioException(error), isTrue);
    });

    test('does not retry 404 responses', () {
      final error = DioException.badResponse(
        statusCode: 404,
        requestOptions: RequestOptions(path: '/asset.pdf'),
        response: Response<void>(
          requestOptions: RequestOptions(path: '/asset.pdf'),
          statusCode: 404,
        ),
      );

      expect(isRetryableDioException(error), isFalse);
    });
  });
}
