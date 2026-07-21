import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Shared password-entry dialog used wherever a screen needs to encrypt or
/// decrypt the NFC recovery-key envelope (see
/// `services/nfc_credential_crypto.dart`). Returns null if the user
/// cancels or dismisses without entering anything.
Future<String?> promptForNfcKeyPassword(
  BuildContext context, {
  String title = 'Senha da chave física',
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title, style: const TextStyle(color: SatraColors.navy)),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        style: const TextStyle(color: SatraColors.navy),
        decoration: const InputDecoration(labelText: 'Senha'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
}
