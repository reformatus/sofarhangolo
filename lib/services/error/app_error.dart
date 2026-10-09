import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'network_error.dart';

enum AppErrorCategory { network, backend, frontend }

class AppError implements Exception {
  const AppError({
    required this.category,
    required this.title,
    this.userMessage,
    this.technicalMessage,
    this.stackTrace,
    this.originalError,
  });

  final AppErrorCategory category;
  final String title;

  /// Friendly, always non-technical guidance. Null when the title already
  /// carries everything friendly there is to say (unexpected app errors).
  final String? userMessage;
  final String? technicalMessage;
  final StackTrace? stackTrace;
  final Object? originalError;

  bool get shouldShowTechnicalDetails => category == AppErrorCategory.frontend;

  /// A copy of this error carrying a different context [title]. Used by
  /// the layer that reports an operation's failure, so the wording lives
  /// on the error instead of being re-invented by each UI surface.
  AppError withTitle(String title) {
    return AppError(
      category: category,
      title: title,
      userMessage: userMessage,
      technicalMessage: technicalMessage,
      stackTrace: stackTrace,
      originalError: originalError,
    );
  }

  String? get details {
    if (!shouldShowTechnicalDetails) return null;
    return technicalMessage;
  }

  String? get stack {
    if (!shouldShowTechnicalDetails) return null;
    return stackTrace?.toString();
  }

  factory AppError.from(
    Object error, {
    StackTrace? stackTrace,
    String? userMessage,
    String? technicalMessage,
  }) {
    if (error is AppError) {
      return error;
    }

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.badCertificate:
          return AppError(
            category: AppErrorCategory.network,
            title: 'Biztonsági hálózati hiba',
            userMessage: userMessage ?? 'A szerver biztonsági tanúsítványa érvénytelen. Később próbáld újra.',
            technicalMessage:
                technicalMessage ?? error.message ?? error.error?.toString(),
            stackTrace: stackTrace,
            originalError: error,
          );
        case DioExceptionType.cancel:
          return AppError(
            category: AppErrorCategory.network,
            title: 'Művelet megszakítva',
            userMessage: userMessage ?? 'A kérés megszakadt. Próbáld újra.',
            technicalMessage:
                technicalMessage ?? error.message ?? error.error?.toString(),
            stackTrace: stackTrace,
            originalError: error,
          );
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return AppError(
            category: AppErrorCategory.network,
            title: 'Hálózati hiba',
            userMessage: userMessage ?? 'Nincs stabil kapcsolat a szerverrel. Ellenőrizd az internetkapcsolatot, majd próbáld újra.',
            technicalMessage:
                technicalMessage ?? error.message ?? error.error?.toString(),
            stackTrace: stackTrace,
            originalError: error,
          );
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          return AppError(
            category: AppErrorCategory.backend,
            title: 'Szerverhiba',
            userMessage:
                userMessage ??
                'A szerver hibát jelzett${statusCode != null ? ' (HTTP $statusCode)' : ''}. Próbáld újra később.',
            technicalMessage:
                technicalMessage ?? error.message ?? error.error?.toString(),
            stackTrace: stackTrace,
            originalError: error,
          );
        case DioExceptionType.transformTimeout:
          return AppError(
            category: AppErrorCategory.frontend,
            title: 'Feldolgozási hiba',
            userMessage:
                userMessage ??
                'A küldött adat feldolgozása túl sokáig tartott.',
            technicalMessage:
                technicalMessage ?? error.message ?? error.error?.toString(),
            stackTrace: stackTrace,
            originalError: error,
          );
        case DioExceptionType.unknown:
          break;
      }

      if (isNetworkRelatedError(error)) {
        return AppError(
          category: AppErrorCategory.network,
          title: 'Hálózati hiba',
          userMessage: userMessage ?? 'Nincs stabil kapcsolat a szerverrel. Ellenőrizd az internetkapcsolatot, majd próbáld újra.',
          technicalMessage:
              technicalMessage ?? error.message ?? error.error?.toString(),
          stackTrace: stackTrace,
          originalError: error,
        );
      }
    }

    if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException ||
        error is TlsException) {
      return AppError(
        category: AppErrorCategory.network,
        title: 'Hálózati hiba',
        userMessage: userMessage ?? 'Nincs stabil kapcsolat a szerverrel. Ellenőrizd az internetkapcsolatot, majd próbáld újra.',
        technicalMessage: technicalMessage ?? error.toString(),
        stackTrace: stackTrace,
        originalError: error,
      );
    }

    if (error is FormatException ||
        error is TypeError ||
        error is AssertionError) {
      return AppError(
        category: AppErrorCategory.frontend,
        title: 'Alkalmazáshiba',
        userMessage: userMessage,
        technicalMessage: technicalMessage ?? error.toString(),
        stackTrace: stackTrace,
        originalError: error,
      );
    }

    return AppError(
      category: AppErrorCategory.frontend,
      title: 'Alkalmazáshiba',
      userMessage: userMessage,
      technicalMessage: technicalMessage ?? error.toString(),
      stackTrace: stackTrace,
      originalError: error,
    );
  }

  @override
  String toString() {
    if (category == AppErrorCategory.frontend) {
      return technicalMessage ?? userMessage ?? title;
    }
    final message = userMessage;
    return message == null ? title : '$title: $message';
  }
}
