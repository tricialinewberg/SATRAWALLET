import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme/colors.dart';

/// Shown once, right after the master sequence is recognized, before the
/// user lands on the initial PIN setup screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        SatraRoutes.pinSetup,
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      body: SafeArea(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, color: SatraColors.medium, size: 110),
              const SizedBox(width: 14),
              const Text(
                'SATRA',
                style: TextStyle(
                  color: SatraColors.medium,
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
