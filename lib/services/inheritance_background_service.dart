import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'inheritance_service.dart';

/// Android foreground observer used only by the short inheritance test.
///
/// A visible persistent notification is required by Android while this runs.
/// It does not make the release of real funds depend on a phone process.
class InheritanceBackgroundService {
  InheritanceBackgroundService._();

  static void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'satra_inheritance_test',
        channelName: 'Teste de herança',
        channelDescription:
            'Mantém o teste de inatividade ativo com o app minimizado.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 7817,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Teste de herança ativo',
      notificationText: 'Monitorando a prova de vida da Satra Wallet',
      callback: inheritanceBackgroundCallback,
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void inheritanceBackgroundCallback() {
  FlutterForegroundTask.setTaskHandler(_InheritanceTaskHandler());
}

class _InheritanceTaskHandler extends TaskHandler {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final result = await InheritanceService.instance.runBackgroundTestCheck();
      if (result.completed) {
        await FlutterForegroundTask.updateService(
          notificationTitle: result.accepted
              ? 'Teste aceito pelo relay'
              : 'Falha no teste de herança',
          notificationText: result.accepted
              ? 'Confira a mensagem no aplicativo Nostr do herdeiro.'
              : 'Nenhum relay confirmou a mensagem. Abra a Satra Wallet.',
        );
        await FlutterForegroundTask.stopService();
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _check();

  @override
  void onRepeatEvent(DateTime timestamp) {
    _check();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
