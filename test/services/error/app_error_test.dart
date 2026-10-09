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

  group('friendly and technical fields', () {
    test(
      'unexpected app errors drop the boilerplate body, keep the failure',
      () {
        final appError = AppError.from(
          const FormatException('bad json'),
          stackTrace: StackTrace.current,
        );

        expect(appError.category, AppErrorCategory.frontend);
        expect(appError.userMessage, isNull);
        expect(
          appError.technicalMessage,
          contains('FormatException: bad json'),
        );
        expect(appError.details, contains('FormatException: bad json'));
        expect(appError.stack, isNotNull);
      },
    );

    test('transform timeouts keep a friendly body and their detail', () {
      final appError = AppError.from(
        DioException(
          requestOptions: RequestOptions(path: '/songs'),
          type: DioExceptionType.transformTimeout,
          message: 'transform took too long',
        ),
      );

      expect(appError.category, AppErrorCategory.frontend);
      expect(appError.userMessage, contains('túl sokáig tartott'));
      expect(appError.details, 'transform took too long');
    });

    test('network errors keep the friendly body and hide the detail', () {
      final appError = AppError.from(SocketException('Network is unreachable'));

      expect(appError.category, AppErrorCategory.network);
      expect(appError.userMessage, contains('Nincs stabil kapcsolat'));
      expect(appError.details, isNull);
      expect(appError.stack, isNull);
    });

    test('an explicit user message overrides the frontend default', () {
      final appError = AppError.from(
        const FormatException('bad json'),
        userMessage: 'Egyedi üzenet',
      );

      expect(appError.userMessage, 'Egyedi üzenet');
    });
  });

  group('AppError.withTitle', () {
    test('replaces the context title, keeping the granular fields', () {
      final appError = AppError.from(
        const FormatException('bad json'),
        stackTrace: StackTrace.current,
      ).withTitle('Hiba a tárak frissítése közben');

      expect(appError.title, 'Hiba a tárak frissítése közben');
      expect(appError.technicalMessage, contains('FormatException: bad json'));
      expect(appError.stack, isNotNull);
    });

    test('keeps a granular user message from a pre-translated error', () {
      final translated = AppError.from(
        SocketException('down'),
        userMessage: 'Nem sikerült lekérni az elérhető daltárakat.',
      );

      final appError = translated.withTitle('Hiba a tárak frissítése közben');

      expect(appError.title, 'Hiba a tárak frissítése közben');
      expect(
        appError.userMessage,
        'Nem sikerült lekérni az elérhető daltárakat.',
      );
      expect(appError.category, AppErrorCategory.network);
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
