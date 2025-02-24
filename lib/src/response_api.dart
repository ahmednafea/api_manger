import 'package:api_manger/src/network_api_exception.dart';
import 'package:dio/dio.dart';

enum DataSource {
  internet,
  memoryCache,
  persistenceCache,
}

class ResponseApi<T> {
  ResponseApi.success({
    required this.data,
    required this.response,
    this.dataSource = DataSource.internet,
    this.defaultErrorMessage = 'error',
    this.noDataMessage = 'No Data',
    this.retryBtnMessage = 'Try again',
  }) : status = ApiStatus.success;

  ResponseApi.error({
    required this.exception,
    required this.response,
    this.dataSource = DataSource.internet,
    this.defaultErrorMessage = 'error',
    this.noDataMessage = 'No Data',
    this.retryBtnMessage = 'Try again',
  }) : status = ApiStatus.error;

  T? data;
  DataSource dataSource = DataSource.internet;
  Response<dynamic> response;

  NetworkApiException? exception;

  final String defaultErrorMessage;
  final String? noDataMessage;
  final String? retryBtnMessage;

  String get error {
    if ((exception?.message.isEmpty ?? true)) return defaultErrorMessage;
    return exception?.message ?? "";
  }

  ApiStatus status;

  bool get isSuccess => status == ApiStatus.success;

  bool get hasError => status == ApiStatus.error;

  bool get isNoData => data == null;

  bool get hasErrorOrNoData => hasError || isNoData;

  int get statusCode => response.statusCode ?? 500;

  @override
  String toString() {
    if (status == ApiStatus.error) {
      return 'Status: $status \nError: $error \nstatusCode: $statusCode \n$dataSource';
    }
    return 'Status: $status \nData: $data \nstatusCode: $statusCode \n$dataSource';
  }
}

enum ApiStatus { success, error }
