import 'package:dio/dio.dart';

class NetworkApiException implements Exception {
  final String? exceptionMessage;
  final String defaultErrorMessage;
  final Response<dynamic>? response;

  NetworkApiException(
      {this.exceptionMessage,
      this.response,
      required this.defaultErrorMessage});

  int get statusCode => response?.statusCode ?? 500;

  String get message => exceptionMessage ?? defaultErrorMessage;

  @override
  String toString() {
    return 'NetworkApiException{message: $message, statusCode: $statusCode}';
  }
}
