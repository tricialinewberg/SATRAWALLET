import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'routes.dart';
import 'screens/calculator_screen.dart';
import 'screens/escape_confirmation_screen.dart';
import 'screens/nfc_transfer_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/send_screen.dart';
import 'screens/splash_screen.dart';
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
      initialRoute: SatraRoutes.calculator,
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
      },
    );
  }
}
