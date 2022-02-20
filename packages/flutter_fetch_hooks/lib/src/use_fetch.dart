import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_fetch_hooks/src/retry_option.dart';
import 'package:flutter_fetch_hooks/src/type.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:retry/retry.dart';

import 'fetch_state.dart';
import 'hash.dart';

final FetcherState _globalFetcherCache = <String, DateTime>{};

FetchState<T?> useFetch<T>({
  List<Object?> keys = const <Object?>[],
  required Fetcher<T> fetcher,
  T? fallbackData,
  RetryOption? retryOption,
  Duration deduplicationInterval = const Duration(seconds: 2),
}) {
  final context = useContext();
  final ref = useRef<FetchState<T?>>(const FetchState(
    value: null,
    isValidating: false,
  ));
  final buffer = StringBuffer();
  final keysHashCode = convertToHash(buffer, keys);
  // ignore: omit_local_variable_types
  final FetchState<T?> listenableValue = SharedAppData.getValue(
    context,
    keysHashCode,
    () => FetchState(
      value: fallbackData,
      isValidating: false,
    ),
  );
  final revalidate = _makeRevalidateFunc(
    path: keysHashCode,
    fetcher: fetcher,
  );

  useEffect(() {
    ref.value = listenableValue;
    return;
  }, [listenableValue]);

  useEffect(() {
    Future(() async {
      final fetchTimeStamp = _globalFetcherCache[keysHashCode];
      if (fetchTimeStamp == null) {
        _globalFetcherCache[keysHashCode] = DateTime.now();
        Timer(deduplicationInterval, () {
          _globalFetcherCache.remove(keysHashCode);
        });
        final fetchState = ref.value;
        SharedAppData.setValue(
          context,
          keysHashCode,
          FetchState(
            value: fetchState.value,
            isValidating: true,
          ),
        );
        final result = await revalidate();
        SharedAppData.setValue(
          context,
          keysHashCode,
          FetchState(
            value: result,
            isValidating: false,
          ),
        );
      }
    });
    return;
  }, [keysHashCode]);
  return ref.value;
}

FutureReturned<T> _makeRevalidateFunc<T>({
  required String path,
  required Fetcher<T> fetcher,
  RetryOption? retryOption,
}) {
  return () async {
    return revalidateWithRetry(fetcher, retryOption: retryOption);
  };
}

Future<T> revalidateWithRetry<T>(
  Fetcher<T> fetcher, {
  RetryOption? retryOption,
}) async {
  if (retryOption == null) {
    return fetcher();
  }

  final onRetry = retryOption.onRetry;
  if (onRetry == null) {
    throw ArgumentError('onRetry are not specified.');
  }
  if (retryOption.maxRetryAttempts <= 0) {
    throw ArgumentError('maxRetryAttempts are not specified.');
  }
  return retry(
    () async {
      return fetcher();
    },
    retryIf: (exception) async {
      return await onRetry(exception);
    },
    maxAttempts: retryOption.maxRetryAttempts,
  );
}