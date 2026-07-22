import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'debug/escape_debug_log.dart';
import 'route_observer.dart';
import 'routes.dart';
import 'screens/calculator_screen.dart';
import 'screens/escape_confirmation_screen.dart';
import 'screens/inheritance_setup_screen.dart';
import 'screens/nfc_key_password_setup_screen.dart';
import 'screens/nfc_transfer_screen.dart';
import 'screens/pending_escape_recovery_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/send_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/trusted_contacts_screen.dart';
import 'screens/wallet_backup_screen.dart';
import 'screens/wallet_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xiaomi Calculator Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      navigatorKey: satraNavigatorKey, // TEMPORARY — see lib/debug/escape_debug_log.dart
      initialRoute: SatraRoutes.calculator,
      navigatorObservers: [satraRouteObserver],
      routes: {
        SatraRoutes.calculator: (context) => const CalculatorScreen(),
        SatraRoutes.splash: (context) => const SplashScreen(),
        SatraRoutes.pinSetup: (context) => const PinSetupScreen(),
        SatraRoutes.walletHome: (context) => const WalletHomeScreen(),
        SatraRoutes.receive: (context) => const ReceiveScreen(),
        SatraRoutes.send: (context) => const SendScreen(),
        SatraRoutes.escapeConfirmation: (context) => const EscapeConfirmationScreen(),
        SatraRoutes.nfcTransfer: (context) => const NfcTransferScreen(),
        SatraRoutes.walletBackup: (context) => const WalletBackupScreen(),
        SatraRoutes.trustedContacts: (context) => const TrustedContactsScreen(),
        SatraRoutes.pendingEscapeRecovery: (context) => const PendingEscapeRecoveryScreen(),
        SatraRoutes.nfcKeyPasswordSetup: (context) => const NfcKeyPasswordSetupScreen(),
        SatraRoutes.inheritance: (context) => const InheritanceSetupScreen(),
      },
    );
  }
}
