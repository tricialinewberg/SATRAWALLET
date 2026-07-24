import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../theme/colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _lockTimeout;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final timeout = await AppSettingsService.instance.getLockTimeoutMinutes();
    if (mounted) {
      setState(() {
        _lockTimeout = timeout;
      });
    }
  }

  Future<void> _setTimeout(int value) async {
    setState(() => _lockTimeout = value);
    await AppSettingsService.instance.setLockTimeoutMinutes(value);
  }

  String _timeoutLabel(int value) => switch (value) {
        0 => 'Imediatamente',
        3 => 'Após 3 minutos',
        5 => 'Após 5 minutos',
        10 => 'Após 10 minutos',
        _ => '$value minutos',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SatraColors.background,
      appBar: AppBar(
        title: const Text('Configurações'),
        backgroundColor: SatraColors.background,
        foregroundColor: SatraColors.navy,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _SettingsHeader(),
          const SizedBox(height: 24),
          const Text(
            'PRIVACIDADE',
            style: TextStyle(
              color: SatraColors.medium,
              fontSize: 12,
              letterSpacing: .8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: SatraColors.light),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.timer_outlined, color: SatraColors.navy),
                  title: Text(
                    'Bloquear ao sair do app',
                    style: TextStyle(
                      color: SatraColors.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Ao voltar depois desse período, a calculadora será exibida.',
                  ),
                ),
                if (_lockTimeout == null)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: SatraColors.medium,
                      strokeWidth: 2,
                    ),
                  )
                else
                  RadioGroup<int>(
                    groupValue: _lockTimeout,
                    onChanged: (selected) {
                      if (selected != null) _setTimeout(selected);
                    },
                    child: Column(
                      children: [
                        for (final value in const [0, 3, 5, 10])
                          RadioListTile<int>(
                            value: value,
                            activeColor: SatraColors.medium,
                            title: Text(_timeoutLabel(value)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'SEGURANÇA',
            style: TextStyle(
              color: SatraColors.medium,
              fontSize: 12,
              letterSpacing: .8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Card(
            color: Colors.white,
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.visibility_off_outlined),
                  title: Text('Saldo oculto ao abrir'),
                  subtitle: Text('Ativado por padrão para sua privacidade.'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('PIN e biometria'),
                  subtitle: Text(
                    'A alteração continua disponível no menu principal.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SatraColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: SatraColors.medium,
            child: Icon(Icons.tune, color: Colors.white),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Ajuste a experiência sem alterar as chaves ou os fundos da carteira.',
              style: TextStyle(color: Colors.white, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
