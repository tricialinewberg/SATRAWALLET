import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettingsService {
  AppSettingsService._();

  static final AppSettingsService instance = AppSettingsService._();
  static const _lockTimeoutKey = 'satra_lock_timeout_minutes';
  static const defaultLockTimeoutMinutes = 3;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<int> getLockTimeoutMinutes() async {
    final stored = int.tryParse(
      await _storage.read(key: _lockTimeoutKey) ?? '',
    );
    return switch (stored) {
      0 || 3 || 5 || 10 => stored!,
      _ => defaultLockTimeoutMinutes,
    };
  }

  Future<void> setLockTimeoutMinutes(int minutes) {
    if (!const {0, 3, 5, 10}.contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    return _storage.write(
      key: _lockTimeoutKey,
      value: minutes.toString(),
    );
  }
}
