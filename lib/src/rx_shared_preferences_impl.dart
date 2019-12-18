import 'dart:async';
import 'dart:collection';

import 'package:rx_shared_preferences/src/interface/rx_shared_preferences.dart';
import 'package:rx_shared_preferences/src/logger/logger.dart';
import 'package:rx_shared_preferences/src/model/key_and_value.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

///
/// Default [IRxSharedPreferences] implementation
///
class RxSharedPreferences implements IRxSharedPreferences {
  ///
  /// Trigger subject
  ///
  final _keyValuesSubject = PublishSubject<Iterable<KeyAndValue<dynamic>>>();

  ///
  /// Future of [SharedPreferences]
  ///
  final Future<SharedPreferences> _sharedPrefsFuture;

  ///
  /// Logger
  ///
  final Logger _logger;

  ///
  /// Constructor
  ///
  RxSharedPreferences(
    FutureOr<SharedPreferences> sharedPreference, [
    this._logger,
  ])  : assert(sharedPreference != null),
        _sharedPrefsFuture = Future.value(sharedPreference) {
    _keyValuesSubject
        .listen((pairs) => _logger?.keysChanged(UnmodifiableListView(pairs)));
  }

  ///
  /// Internal
  ///

  ///
  /// Workaround to capture generics
  ///
  static Type _typeOf<T>() => T;

  ///
  /// Get [Stream] from the persistent storage
  ///
  Stream<T> _getStream<T>(String key, Future<T> get(String key)) {
    return _keyValuesSubject
        .map((pairs) {
          return pairs.firstWhere(
            (pair) => pair.key == key,
            orElse: () => null,
          );
        })
        .where((pair) => pair != null)
        .startWith(null) // Dummy value to trigger initial load.
        .asyncMap((pair) async {
          if (pair == null) {
            return get(key);
          }
          if (T == _typeOf<List<String>>()) {
            return (pair.value as List)?.cast<String>() as T;
          }
          return pair.value as T;
        })
        .doOnData((value) => _logger?.doOnDataStream(KeyAndValue(key, value)))
        .doOnError((e, StackTrace s) => _logger?.doOnErrorStream(e, s));
  }

  ///
  /// Get value from the persistent storage by [key]
  ///
  Future<T> _get<T>([String key]) async {
    read<T>(SharedPreferences sharedPreferences, String key) {
      if (T == dynamic) {
        return sharedPreferences.get(key) as T;
      }
      if (T == double) {
        return sharedPreferences.getDouble(key) as T;
      }
      if (T == int) {
        return sharedPreferences.getInt(key) as T;
      }
      if (T == bool) {
        return sharedPreferences.getBool(key) as T;
      }
      if (T == String) {
        return sharedPreferences.getString(key) as T;
      }
      if (T == _typeOf<List<String>>()) {
        return sharedPreferences.getStringList(key)?.cast<String>() as T;
      }
      // Get all keys
      if (T == _typeOf<Set<String>>() && key == null) {
        return sharedPreferences.getKeys() as T;
      }
      return null;
    }

    final prefs = await _sharedPrefsFuture;
    final value = read<T>(prefs, key);
    _logger?.readValue(T, key, value);

    return value;
  }

  ///
  /// Set [value] associated with [key]
  ///
  Future<bool> _setValue<T>(String key, T value) async {
    write<T>(SharedPreferences sharedPreferences, String key, T value) {
      if (T == dynamic) {
        return value != null
            ? Future.value(false)
            : sharedPreferences.remove(key);
      }
      if (T == double) {
        return sharedPreferences.setDouble(key, value as double);
      }
      if (T == int) {
        return sharedPreferences.setInt(key, value as int);
      }
      if (T == bool) {
        return sharedPreferences.setBool(key, value as bool);
      }
      if (T == String) {
        return sharedPreferences.setString(key, value as String);
      }
      if (T == _typeOf<List<String>>()) {
        return sharedPreferences.setStringList(
          key,
          (value as List)?.cast<String>(),
        );
      }
      return Future.value(false);
    }

    final prefs = await _sharedPrefsFuture;
    final result = await write<T>(prefs, key, value);
    _logger?.writeValue(T, key, value, result);

    // Trigger key changes
    if (result ?? false) {
      _sendKeyValueChanged([KeyAndValue<T>(key, value)]);
    }

    return result;
  }

  ///
  /// Add pairs to subject to trigger.
  /// Do nothing if subject already closed.
  ///
  void _sendKeyValueChanged(Iterable<KeyAndValue<dynamic>> pairs) {
    try {
      _keyValuesSubject.add(pairs);
    } catch (e) {
      print(e);
      // Do nothing
    }
  }

  //
  // Get and set methods (implements [ILikeSharedPreferences])
  //

  @override
  Future<bool> containsKey(String key) =>
      _sharedPrefsFuture.then((prefs) => prefs.containsKey(key));

  @override
  Future<dynamic> get(String key) => _get<dynamic>(key);

  @override
  Future<bool> getBool(String key) => _get<bool>(key);

  @override
  Future<double> getDouble(String key) => _get<double>(key);

  @override
  Future<int> getInt(String key) => _get<int>(key);

  @override
  Future<Set<String>> getKeys() => _get<Set<String>>();

  @override
  Future<String> getString(String key) => _get<String>(key);

  @override
  Future<List<String>> getStringList(String key) => _get<List<String>>(key);

  @override
  Future<bool> clear() async {
    final SharedPreferences prefs = await _sharedPrefsFuture;
    final Set<String> keys = prefs.getKeys();
    print(keys);
    final bool result = await prefs.clear();

    keys.forEach((key) => _logger?.writeValue(dynamic, key, null, result));

    if (result ?? false) {
      _sendKeyValueChanged(
        keys.map((key) {
          return KeyAndValue<dynamic>(
            key,
            null,
          );
        }),
      );
    }

    return result;
  }

  @override
  Future<void> reload() async {
    final SharedPreferences prefs = await _sharedPrefsFuture;
    await prefs.reload();

    prefs.getKeys().forEach(
      (key) {
        _logger?.readValue(
          dynamic,
          key,
          prefs.get(key),
        );
      },
    );
    _sendKeyValueChanged(
      prefs
          .getKeys()
          .map(
            (key) => KeyAndValue<dynamic>(
              key,
              prefs.get(key),
            ),
          )
          .toList(growable: false),
    );
  }

  @deprecated
  @override
  Future<bool> commit() => _sharedPrefsFuture.then((prefs) => prefs.commit());

  @override
  Future<bool> remove(String key) => _setValue<dynamic>(key, null);

  @override
  Future<bool> setBool(String key, bool value) => _setValue<bool>(key, value);

  @override
  Future<bool> setDouble(String key, double value) =>
      _setValue<double>(key, value);

  @override
  Future<bool> setInt(String key, int value) => _setValue<int>(key, value);

  @override
  Future<bool> setString(String key, String value) =>
      _setValue<String>(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _setValue<List<String>>(key, value);

  //
  // Get streams (implements [IRxSharedPreferences])
  //

  @override
  Stream<dynamic> getStream(String key) => _getStream<dynamic>(key, get);

  @override
  Stream<bool> getBoolStream(String key) => _getStream<bool>(key, getBool);

  @override
  Stream<double> getDoubleStream(String key) =>
      _getStream<double>(key, getDouble);

  @override
  Stream<int> getIntStream(String key) => _getStream<int>(key, getInt);

  @override
  Stream<String> getStringStream(String key) =>
      _getStream<String>(key, getString);

  @override
  Stream<List<String>> getStringListStream(String key) =>
      _getStream<List<String>>(key, getStringList);

  @override
  Future<void> dispose() => _keyValuesSubject.close();
}
