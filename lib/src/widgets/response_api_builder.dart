import 'dart:async';

import 'package:api_manger/api_manger.dart';
import 'package:api_manger/src/widgets/error_widget_holder.dart';
import 'package:api_manger/src/widgets/no_data_holder.dart';
import 'package:api_manger/src/widgets/show_progress.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ResponseApiBuilder<T> extends StatefulWidget {
  final ApiReq<T> future;
  final DataBuilder<T>? dataBuilder;
  final RefreshCallBack? refreshCallBack;
  final DataAndLoadingBuilder<T>? dataAndLoadingBuilder;
  final NoDataBuilder? noDataBuilder;
  final LoadingBuilder loadingBuilder;
  final ErrorBuilder? errorBuilder;
  final NoDataChecker<T?>? noDataChecker;
  final String? noDataMessage;
  final String? retryBtnMessage;
  final bool refreshFailedReq;

  const ResponseApiBuilder({
    super.key,
    required this.future,
    this.dataBuilder,
    this.dataAndLoadingBuilder,
    this.noDataBuilder,
    this.loadingBuilder = loadingWidgetHolder,
    this.refreshCallBack,
    this.errorBuilder,
    this.noDataChecker,
    this.refreshFailedReq = true,
    this.noDataMessage,
    this.retryBtnMessage,
  });

  @override
  ResponseApiBuilderState<T> createState() => ResponseApiBuilderState<T>();
}

class ResponseApiBuilderState<T> extends State<ResponseApiBuilder<T>> {
  final ValueNotifier<ResponseApi<T>?> _notifier =
      ValueNotifier<ResponseApi<T>?>(null);

  void refresh() {
    _getReq();
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  void _getReq() {
    _isLoading = true;
    _notifier.value = null;
    widget.future().then((value) {
      _notifier.value = value;
      _isLoading = false;
    });
  }

  @override
  dispose() {
    super.dispose();
    _connectivitySubscription?.cancel();
  }

  @override
  void initState() {
    _getReq();
    if (widget.refreshFailedReq) {
      _connectivitySubscription = Connectivity()
          .onConnectivityChanged
          .listen((List<ConnectivityResult> result) {
        final bool connected = result.first != ConnectivityResult.none;
        if (connected && (_notifier.value?.hasErrorOrNoData ?? true)) {
          _getReq();
        }
      });
    }
    super.initState();
  }

  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _notifier,
      builder: (context, value, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _getWidget(
            context: context,
            res: value,
            isDone: !_isLoading,
            isLoading: _isLoading,
          ),
        );
      },
    );
  }

  Widget _getWidget({
    required BuildContext context,
    ResponseApi<T>? res,
    required bool isDone,
    required bool isLoading,
  }) {
    if (isLoading) {
      if (widget.dataAndLoadingBuilder != null) {
        return widget.dataAndLoadingBuilder!(
            context, res?.data, !isDone, refresh);
      }
      return widget.loadingBuilder(context);
    }

    if (res!.hasError) {
      return errorWidgetHolder(
        context,
        res.error,
        refresh,
        retryMessage: widget.retryBtnMessage ?? res.retryBtnMessage ?? "",
        errorBuilder: widget.errorBuilder,
      );
    }

    if (isDone && isNoData(res, widget.noDataChecker)) {
      if (widget.noDataBuilder == null) {
        return noDataWidgetHolder(
            widget.noDataMessage ?? res.noDataMessage ?? "");
      }
      return widget.noDataBuilder!(context, refresh);
    }

    if (isNoData(res, widget.noDataChecker)) {
      if (widget.noDataBuilder == null) {
        return noDataWidgetHolder(
            widget.noDataMessage ?? res.noDataMessage ?? "");
      }
      return widget.noDataBuilder!(context, refresh);
    }

    if (widget.dataAndLoadingBuilder != null) {
      return widget.dataAndLoadingBuilder!(context, res.data, !isDone, refresh);
    }

    return widget.dataBuilder != null
        ? widget.dataBuilder!(context, res.data as T, refresh)
        : const SizedBox.shrink();
  }

  bool isNoData(ResponseApi<T> res, bool Function(T? body)? noDataChecker) {
    final T? data = res.data;

    if (noDataChecker != null) return noDataChecker(data);

    if (res.isNoData) return true;

    if (data == null) return true;

    if (data.runtimeType.toString().startsWith('List') &&
        (data as List).isEmpty) return true;

    return false;
  }
}
