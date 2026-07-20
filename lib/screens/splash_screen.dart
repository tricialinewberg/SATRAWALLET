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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: SatraColors.navy,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.bolt, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 12),
              const Text(
                'SATRA',
                style: TextStyle(
                  color: SatraColors.navy,
                  fontSize: 36,
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
