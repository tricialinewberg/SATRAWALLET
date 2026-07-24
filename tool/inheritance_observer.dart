import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calculadora/services/inheritance_observer.dart';
import 'package:nostr/nostr.dart';

const defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
];

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  if (options == null) {
    stderr.writeln(
      'Uso: dart run tool/inheritance_observer.dart '
      '--owner <npub-ou-hex> [--interval-minutes 15] [--relay wss://...]',
    );
    exitCode = 64;
    return;
  }

  final observer = InheritanceObserver(relays: options.relays);
  while (true) {
    final observation = await observer.observe(options.ownerPubkeyHex);
    stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(observation.toMap()));
    if (options.interval == null) return;
    await Future<void>.delayed(options.interval!);
  }
}

_ObserverOptions? _parseArguments(List<String> arguments) {
  String? owner;
  int? intervalMinutes;
  final relays = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (index + 1 >= arguments.length) return null;
    final value = arguments[++index];
    switch (argument) {
      case '--owner':
        owner = value;
      case '--interval-minutes':
        intervalMinutes = int.tryParse(value);
        if (intervalMinutes == null || intervalMinutes < 1) return null;
      case '--relay':
        final uri = Uri.tryParse(value);
        if (uri == null || (uri.scheme != 'wss' && uri.scheme != 'ws')) {
          return null;
        }
        relays.add(value);
      default:
        return null;
    }
  }
  if (owner == null) return null;
  String ownerHex;
  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(owner)) {
    ownerHex = owner;
  } else {
    try {
      final decoded = Bech32Entity.decode(payload: owner);
      if (decoded.prefix != Nip19Prefix.npub) return null;
      ownerHex = decoded.data;
    } catch (_) {
      return null;
    }
  }
  return _ObserverOptions(
    ownerPubkeyHex: ownerHex,
    relays: relays.isEmpty ? defaultRelays : relays,
    interval:
        intervalMinutes == null ? null : Duration(minutes: intervalMinutes),
  );
}

class _ObserverOptions {
  final String ownerPubkeyHex;
  final List<String> relays;
  final Duration? interval;

  const _ObserverOptions({
    required this.ownerPubkeyHex,
    required this.relays,
    required this.interval,
  });
}
