import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'route_observer.dart';
import 'routes.dart';
import 'screens/calculator_screen.dart';
import 'screens/escape_confirmation_screen.dart';
import 'screens/inheritance_claim_screen.dart';
import 'screens/inheritance_heirs_screen.dart';
import 'screens/inheritance_message_test_screen.dart';
import 'screens/inheritance_password_screen.dart';
import 'screens/inheritance_periods_screen.dart';
import 'screens/inheritance_setup_screen.dart';
import 'screens/nfc_key_password_setup_screen.dart';
import 'screens/nfc_transfer_screen.dart';
import 'screens/pending_escape_recovery_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/send_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/support_screen.dart';
import 'screens/trusted_contacts_screen.dart';
import 'screens/wallet_backup_screen.dart';
import 'screens/wallet_home_screen.dart';
import 'services/app_settings_service.dart';
import 'services/breez_service.dart';
import 'services/inheritance_background_service.dart';
import 'services/inheritance_service.dart';
import 'services/pin_service.dart';
import 'theme/colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());

  // The calculator is the privacy screen and must be painted immediately.
  // Both the foreground-task plugin init and the inheritance test resume touch
  // encrypted storage and Android services, so they must not delay the first
  // frame. Schedule them right after runApp — the scheduler runs them on the
  // next microtask, after the first frame has been submitted.
  unawaited(_postFirstFrameBootstrap());
}

Future<void> _postFirstFrameBootstrap() async {
  // Best-effort: a corrupt Keystore or a foreground-task plugin hiccup here
  // must never affect the calculator or prevent the app from opening.
  try {
    InheritanceBackgroundService.initialize();
    await InheritanceService.instance.resumePendingDeliveryTest();
  } catch (error, stackTrace) {
    debugPrint('[main] post-first-frame bootstrap failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _lockRequired = false;
  bool _lockScheduled = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_warmUpWalletBestEffort());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      unawaited(_lockIfTimeoutElapsed());
    }
  }

  Future<void> _lockIfTimeoutElapsed() async {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return;

    final timeoutMinutes =
        await AppSettingsService.instance.getLockTimeoutMinutes();
    final elapsed = DateTime.now().difference(backgroundedAt);
    if (timeoutMinutes == 0 || elapsed >= Duration(minutes: timeoutMinutes)) {
      _lockRequired = true;
      _scheduleLock();
    }
  }

  void _scheduleLock() {
    if (_lockScheduled) return;
    _lockScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lockScheduled = false;
      if (!_lockRequired || !mounted) return;

      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        _scheduleLock();
        return;
      }

      _lockRequired = false;
      navigator.pushNamedAndRemoveUntil(
        SatraRoutes.calculator,
        (route) => false,
      );
    });
  }

  Future<void> _warmUpWalletBestEffort() async {
    // This runs only after the calculator's first frame. If this installation
    // already has a PIN, connect Breez while the user types it, so opening the
    // wallet usually reuses an in-flight or ready connection.
    if (!mounted) return;
    try {
      if (await PinService().hasPin()) {
        await BreezService.instance.initialize();
      }
    } catch (error, stackTrace) {
      // WalletHomeScreen owns the visible error/retry UI. A failed warm-up is
      // intentionally silent and its initialization future remains retryable.
      debugPrint('[main] wallet warm-up failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Calculadora',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: SatraColors.navy,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: SatraColors.background,
      ),
      initialRoute: SatraRoutes.calculator,
      navigatorObservers: [satraRouteObserver],
      onGenerateRoute: _buildRoute,
    );
  }
}

Route<dynamic>? _buildRoute(RouteSettings settings) {
  final builder = switch (settings.name) {
    SatraRoutes.calculator => (_) => const CalculatorScreen(),
    SatraRoutes.pinSetup => (_) => PinSetupScreen(
          changing: settings.arguments == true,
        ),
    SatraRoutes.walletHome => (_) => const WalletHomeScreen(),
    SatraRoutes.receive => (_) => const ReceiveScreen(),
    SatraRoutes.send => (_) => const SendScreen(),
    SatraRoutes.escapeConfirmation => (_) => const EscapeConfirmationScreen(),
    SatraRoutes.nfcTransfer => (_) => const NfcTransferScreen(),
    SatraRoutes.walletBackup => (_) => const WalletBackupScreen(),
    SatraRoutes.trustedContacts => (_) => const TrustedContactsScreen(),
    SatraRoutes.pendingEscapeRecovery => (_) =>
        const PendingEscapeRecoveryScreen(),
    SatraRoutes.nfcKeyPasswordSetup => (_) => const NfcKeyPasswordSetupScreen(),
    SatraRoutes.inheritance => (_) => const InheritanceSetupScreen(),
    SatraRoutes.inheritanceHeirs => (_) => const InheritanceHeirsScreen(),
    SatraRoutes.inheritancePassword => (_) => const InheritancePasswordScreen(),
    SatraRoutes.inheritancePeriods => (_) => const InheritancePeriodsScreen(),
    SatraRoutes.inheritanceMessageTest => (_) =>
        const InheritanceMessageTestScreen(),
    SatraRoutes.inheritanceClaim => (_) => const InheritanceClaimScreen(),
    SatraRoutes.support => (_) => const SupportScreen(),
    SatraRoutes.settings => (_) => const SettingsScreen(),
    _ => null,
  };
  if (builder == null) return null;
  return CupertinoPageRoute<void>(builder: builder, settings: settings);
}
