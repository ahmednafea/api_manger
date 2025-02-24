import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:api_manger/src/api_util.dart';
import 'package:api_manger/src/base_cache_api_db.dart';
import 'package:api_manger/src/future_queue.dart';
import 'package:api_manger/src/interceptors/interceptors.dart';
import 'package:api_manger/src/network_api_exception.dart';
import 'package:api_manger/src/response_api.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// Must be top-level function
dynamic _parseAndDecode(String response) {
  return jsonDecode(response);
}

Future<dynamic> _parseJsonCompute(String text) {
  return compute(_parseAndDecode, text);
}

class ApiManager {
  final DateTime _firstCallTime = DateTime.now();

  ApiManager(
    this._dio, {
    required this.errorGeneralParser,
    required this.apiCacheDB,
    required this.defaultErrorMessage,
    required this.networkErrorMessage,
    this.getAuthHeader,
    this.getDefaultHeader,
    this.noDataMessage,
    this.retryBtnMessage,
    this.connectionTimeOutMessage,
    this.receivingTimeOutMessage,
    this.sendingTimeOutMessage,
    this.isDevelopment = false,

    /// if response body Length > largeResponseLength package will parse response in another isolate(Thread)
    /// may take much time but it will improve rendering performance
    int largeResponseLength = 100000,
    this.onNetworkChanged,
  }) {
    if (isDevelopment) {
      _dio.interceptors.add(LogInterceptorX(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        logPrint: print,
      ));
    }

    (_dio.transformer as BackgroundTransformer).jsonDecodeCallback = (text) {
      if (text.length > largeResponseLength) return _parseJsonCompute(text);
      return _parseAndDecode(text);
    };

    Connectivity().onConnectivityChanged.distinct().listen((List<ConnectivityResult> connectivityResult) {
      // to ignore onNetworkChanged in firstCall
      if (DateTime.now().isAfter(
        _firstCallTime.add(const Duration(seconds: 2)),
      )) {
        final bool connected = connectivityResult.first != ConnectivityResult.none;
        if (onNetworkChanged != null) {
          onNetworkChanged!(connected, connectivityResult.first);
        }
      }
    });
  }

  final Dio _dio;

  /// if true we will print some information to know what happens
  final bool isDevelopment;

  /// used to make persistenceCache
  final BaseApiCacheDb apiCacheDB;

  ///send when auth=true
  final FutureOr<Map<String, String>> Function()? getAuthHeader;

  ///use it when u need to send header Like [accept language]
  final FutureOr<Map<String, String>> Function()? getDefaultHeader;

  /// return when errorGeneralParser or errorParser return null
  final String Function() defaultErrorMessage;

  /// return when SocketException
  final String Function() networkErrorMessage;

  /// used with ResponseApiBuilder when no data
  final String Function()? noDataMessage;

  /// used with ResponseApiBuilder when req is not successful
  final String Function()? retryBtnMessage;

  /// When DioErrorType is connectTimeout
  final String Function()? connectionTimeOutMessage;

  /// When DioErrorType is sendTimeout
  final String Function()? sendingTimeOutMessage;

  /// When DioErrorType is receiveTimeout
  final String Function()? receivingTimeOutMessage;

  /// if ur backend used the same error structure
  /// u need to define how to parsing it
  /// also, u can override it in every request
  final String Function(dynamic body, int statusCode) errorGeneralParser;

  /// listen to network connectivity
  /// true == connected to wifi or mobile network
  /// false == no internet
  final void Function(bool connected, ConnectivityResult connectivityResult)? onNetworkChanged;

  /// used to save response in memory
  final Map<String, dynamic> _httpCaching = HashMap<String, dynamic>();

  Future<ResponseApi<T>> _guardSendRequest<T>({
    required Future<_ResponseWithDataSource> Function() request,
    dynamic Function(dynamic body)? editBody,
    T Function(dynamic body)? parserFunction,
  }) async {
    try {
      final res = await request();
      dynamic body = res.response.data;
      if (editBody != null) {
        body = editBody(body);
      }
      return ResponseApi<T>.success(
        data: _parse(body, parserFunction),
        response: res.response,
        dataSource: res.dataSource,
        defaultErrorMessage: defaultErrorMessage.call(),
        noDataMessage: noDataMessage?.call(),
        retryBtnMessage: retryBtnMessage?.call(),
      );
    } catch (e, stacktrace) {
      if (isDevelopment && (e is! NetworkApiException)) {
        log('ApiManger: $e \n$stacktrace');
      }
      return ResponseApi<T>.error(
        exception: e as NetworkApiException,
        response: e.response!,
        defaultErrorMessage: defaultErrorMessage.call(),
        noDataMessage: noDataMessage?.call(),
        retryBtnMessage: retryBtnMessage?.call(),
      );
    }
  }

  Future<ResponseApi<T>> post<T>(
    String url,
      { T Function(dynamic body)? parserFunction,
    dynamic Function(dynamic body)? editBody,
    Map<String, String> headers = const <String, String>{},
    bool auth = false,
    bool queue = false,
    dynamic postBody,
    ProgressCallback? onSendProgress,
    String Function(dynamic body, int statusCode)? errorParser,
  }) async {
    return await _guardSendRequest(
        request: () => _sendRequestImpl(
              url,
              auth: auth,
              headers: headers,
              body: postBody,
              queue: queue,
              onSendProgress: onSendProgress,
              method: 'POST',
              errorParser: errorParser,
            ),
        editBody: editBody,
        parserFunction: parserFunction);
  }

  Future<ResponseApi<T>> patch<T>(
    String url,
    T Function(dynamic body) parserFunction, {
    required dynamic Function(dynamic body) editBody,
    Map<String, String> headers = const <String, String>{},
    bool auth = false,
    bool queue = false,
    dynamic dataBody,
    required ProgressCallback onSendProgress,
    required String Function(dynamic body, int statusCode) errorParser,
  }) async {
    return await _guardSendRequest(
        request: () => _sendRequestImpl(
              url,
              auth: auth,
              headers: headers,
              body: dataBody,
              queue: queue,
              onSendProgress: onSendProgress,
              method: 'patch',
              errorParser: errorParser,
            ),
        editBody: editBody,
        parserFunction: parserFunction);
  }

  Future<ResponseApi<T>> put<T>(
    String url,
    {T Function(dynamic body)? parserFunction,
      dynamic Function(dynamic body)? editBody,
    Map<String, String> headers = const <String, String>{},
    bool auth = false,
    bool queue = false,
    dynamic dataBody,
    ProgressCallback? onSendProgress,
    String Function(dynamic body, int statusCode)? errorParser,
  }) async {
    return await _guardSendRequest(
        request: () => _sendRequestImpl(
              url,
              auth: auth,
              headers: headers,
              body: dataBody,
              queue: queue,
              onSendProgress: onSendProgress,
              method: 'PUT',
              errorParser: errorParser,
            ),
        editBody: editBody,
        parserFunction: parserFunction);
  }

  ///first time get data from api and cache it in memory if statusCode >=200<300
  ///any other time response will return from cache
  @Deprecated('use get with memoryCache: true instead of  getWithCache')
  Future<ResponseApi<T>> getWithCache<T>(
    String url,
    T Function(dynamic body) parserFunction, {
    dynamic Function(dynamic body)? editBody,
    Map<String, String> headers = const <String, String>{},
    bool auth = false,
    bool queue = false,
    String Function(dynamic body, int statusCode)? errorParser,
  }) async {
    return await _guardSendRequest(
        request: () => _sendRequestImpl(
              url,
              auth: auth,
              headers: headers,
              memoryCache: true,
              queue: queue,
              method: 'GET',
              errorParser: errorParser,
            ),
        editBody: editBody,
        parserFunction: parserFunction);
  }

  Future<ResponseApi<T>> get<T>(
    String url,
   { T Function(dynamic body)? parserFunction,
     dynamic Function(dynamic body)? editBody,
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
    bool auth = false,
    bool queue = false,
    bool memoryCache = false,
    dynamic postBody,
    bool persistenceCache = false,
    String Function(dynamic body, int statusCode)? errorParser,
  }) async {
    return await _guardSendRequest(
        request: () => _sendRequestImpl(
              url,
              auth: auth,
              body: postBody,
              headers: headers,
              queue: queue,
              memoryCache: memoryCache,
              persistenceCache: persistenceCache,
              method: 'GET',
              errorParser: errorParser,
              // queryParameters: queryParameters,
            ),
        editBody: editBody,
        parserFunction: parserFunction);
  }

  Future<ResponseApi<T>> delete<T>(
    String url,
    T Function(dynamic body) parserFunction, {
    dynamic Function(dynamic body)? editBody,
    Map<String, String> headers = const <String, String>{},
    bool auth = false,
    bool queue = false,
    dynamic dataBody,
    String Function(dynamic body, int statusCode)? errorParser,
  }) async {
    return await _guardSendRequest(
        request: () => _sendRequestImpl(
              url,
              auth: auth,
              headers: headers,
              queue: queue,
              body: dataBody,
              method: 'delete',
              errorParser: errorParser,
            ),
        editBody: editBody,
        parserFunction: parserFunction);
  }

  T _parse<T>(dynamic body, T Function(dynamic body)? parserFunction) {
    if (parserFunction == null) return body;

    try {
      return parserFunction(body);
    } catch (e, stacktrace) {
      if (e is FormatException || e is TypeError || e is NoSuchMethodError) {
        if (isDevelopment) log('ApiManger: parserFunction=> $e \n$stacktrace');

        return throw NetworkApiException(defaultErrorMessage: defaultErrorMessage());
      }
      throw NetworkApiException(
          exceptionMessage: e.toString(), defaultErrorMessage: defaultErrorMessage());
    }
  }

  dynamic _getFromMemoryCache(String hash) {
    return _httpCaching[hash];
  }

  Future<Response<dynamic>?> _getFromPersistenceCache(String hash) async {
    try {
      return responseFromRawJson(await apiCacheDB.get(hash));
    } catch (e, stacktrace) {
      if (isDevelopment) {
        log('ApiManger: _getFromPersistenceCache=> $e \n$stacktrace');
      }

      return null;
    }
  }

  bool _validResponse(int? statusCode) {
    return statusCode != null && statusCode >= 200 && statusCode < 300;
  }

  void _saveToMemoryCache(Response<dynamic> res, String hash) {
    if (_validResponse(res.statusCode ?? 500)) {
      _httpCaching[hash] = res;
    }
  }

  Future<void> _saveToPersistenceCache(Response<dynamic> res, String hash) async {
    if (_validResponse(res.statusCode)) {
      await apiCacheDB.add(
        hash,
        responseToRawJson(res),
      );
    }
  }

  String _getCacheHash(String url, String method, Map<String, String> headers, {dynamic body}) {
    final allPram = '$url+ $method+ $headers+ $body';
    var hashedStr = base64.encode(utf8.encode(allPram)).split('').toSet().join('');
    var hashedUrl = base64.encode(utf8.encode(url)).split('').toSet().join('');
    return '$hashedUrl+ $hashedStr';
  }

  Future<_ResponseWithDataSource> _sendRequestImpl(
    String url, {
    required String method,
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
    bool auth = false,
    bool memoryCache = false,
    bool persistenceCache = false,
    bool queue = false,
    ProgressCallback? onSendProgress,
    dynamic body,
    String Function(dynamic body, int statusCode)? errorParser,
  }) async {
    final Map<String, String> headers0 = <String, String>{
      ...headers,
      ...auth ? await getAuthHeader?.call() ?? {} : <String, String>{},
      ...await getDefaultHeader?.call() ?? {},
    };
    final String cacheHash = _getCacheHash(url, method, headers0, body: body);
    try {
      if (memoryCache) {
        final dynamic dataFromCache = _getFromMemoryCache(cacheHash);
        if (dataFromCache != null) {
          return _ResponseWithDataSource(
            response: dataFromCache,
            dataSource: DataSource.memoryCache,
          );
        }
      }

      Response<dynamic> res;
      if (queue) {
        res = await ApiFutureQueue().run(
          () => _dio.request(
            url,
            options: Options(headers: headers0, method: method),
            data: body,
            onSendProgress: onSendProgress,
            queryParameters: queryParameters,
          ),
        );
      } else {
        res = await _dio.request(
          url,
          options: Options(headers: headers0, method: method),
          data: body,
          onSendProgress: onSendProgress,
          queryParameters: queryParameters,
        );
      }

      if (memoryCache) _saveToMemoryCache(res, cacheHash);
      if (persistenceCache) await _saveToPersistenceCache(res, cacheHash);
      return _ResponseWithDataSource(
        response: res,
        dataSource: DataSource.internet,
      );
    } catch (error) {
      final dynamic dataFromCache = await _getCacheIfSocketException(
        error,
        persistenceCache,
        cacheHash,
      );
      if (dataFromCache != null) {
        return _ResponseWithDataSource(
          response: dataFromCache,
          dataSource: DataSource.persistenceCache,
        );
      }

      throw _handleError(error, errorParser ?? errorGeneralParser);
    }
  }

  Future<dynamic> _getCacheIfSocketException(
    dynamic error,
    bool persistenceCache,
    String cacheHash,
  ) async {
    if (error is DioException && error.error is SocketException && persistenceCache) {
      return await _getFromPersistenceCache(cacheHash);
    }
    return null;
  }

  String _handleError(
      dynamic exception, String? Function(dynamic body, int statusCode) errorParser) {
    final Response<dynamic> response = exception?.response;
    dynamic responseBody;
    String error = defaultErrorMessage();
    final statusCode = response.statusCode ?? 500;
    if (exception is DioException) {
      if (exception.error is SocketException) {
        throw NetworkApiException(
          exceptionMessage: networkErrorMessage(),
          defaultErrorMessage: error,
        );
      }
      if (exception.type == DioExceptionType.connectionTimeout) {
        throw NetworkApiException(
          exceptionMessage: connectionTimeOutMessage?.call(),
          response: response,
          defaultErrorMessage: error,
        );
      }
      if (exception.type == DioExceptionType.receiveTimeout) {
        throw NetworkApiException(
          exceptionMessage: receivingTimeOutMessage?.call(),
          response: response,
          defaultErrorMessage: error,
        );
      }
      if (exception.type == DioExceptionType.sendTimeout) {
        throw NetworkApiException(
          exceptionMessage: sendingTimeOutMessage?.call(),
          response: response,
          defaultErrorMessage: error,
        );
      }
      try {
        responseBody = response.data;
        error = errorParser(responseBody, statusCode) ?? error;
      } catch (e) {
        throw NetworkApiException(
            exceptionMessage: error, response: response, defaultErrorMessage: error);
      }
    }

    switch (response.statusCode) {
      // case 401:
      //   throw Exception('Error : Your Token Is Expired-$statusCode');
      //   break;
      //Todo handle when Token Expired 401
      default:
        throw NetworkApiException(
            exceptionMessage: error,
            response: response,
            defaultErrorMessage: defaultErrorMessage());
    }
  }
}

class _ResponseWithDataSource {
  final Response response;
  final DataSource dataSource;

  _ResponseWithDataSource({
    required this.response,
    this.dataSource = DataSource.internet,
  });
}
