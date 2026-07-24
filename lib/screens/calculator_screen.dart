import 'dart:async';

import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/biometric_service.dart';
import '../services/inheritance_service.dart';
import '../services/pin_service.dart';
import '../widgets/calculator_button.dart';

/// Fixed master sequence that opens the one-time initial setup, but only
/// while no personal PIN has been configured yet. Digits are compared
/// against the raw keystrokes (see [_rawInput]), not the collapsed display
/// value, so a leading zero isn't lost the way a real calculator would lose it.
const _masterSequence = '21';

/// Heir-only entry sequence. Lets someone who installed the app fresh (e.g.
/// an heir who never used Satra before) reach the inheritance decryption
/// screen without configuring a wallet or a PIN. Only active in the virgin
/// state (no PIN yet) so it can't become a backdoor into a real user's
/// wallet. Deliberately 6 digits — longer than the 4-digit PIN so a normal
/// PIN guess can never collide with it. The owner shares this sequence
/// with the heir out-of-band (e.g. printed on the sealed card alongside the
/// release password and the npub). This is convenience, not security: the
/// actual protection on the inheritance vault is the Argon2id+AES-GCM
/// encryption + the release password, both identical whether the heir
/// decrypts via this sequence or the side menu.
const _heirSequence = '589301';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final PinService _pinService = PinService();
  final BiometricService _biometricService = BiometricService();

  String _display = '0';
  String _currentValue = '0';
  double? _storedValue;
  String? _pendingOperator;
  String? _lastOperator;
  double? _lastOperand;
  bool _waitingForSecondOperand = false;
  bool _justCalculated = false;
  String _expression = '';

  // Raw digits typed since the last reset, used only for secret-sequence
  // detection. Set to null once the entry can no longer be a plain PIN
  // (an operator, a decimal point, or a sign/percent was used).
  String? _rawInput = '';

  void _appendDigit(String digit) {
    setState(() {
      if (_justCalculated) {
        _currentValue = digit;
        _display = digit;
        _expression = '';
        _storedValue = null;
        _pendingOperator = null;
        _lastOperator = null;
        _lastOperand = null;
        _waitingForSecondOperand = false;
        _justCalculated = false;
        _rawInput = digit;
        return;
      }

      if (_rawInput != null) {
        _rawInput = _rawInput! + digit;
      }

      if (_waitingForSecondOperand) {
        _currentValue = digit;
        _waitingForSecondOperand = false;
      } else if (_currentValue == '-0') {
        _currentValue = digit == '0' ? '-0' : '-$digit';
      } else if (_currentValue == '0' && digit != '0') {
        _currentValue = digit;
      } else if (_currentValue == '0' && digit == '0') {
        _currentValue = '0';
      } else {
        _currentValue += digit;
      }

      _display = _buildDisplay();
    });
  }

  void _appendDecimal() {
    setState(() {
      _rawInput = null;

      if (_justCalculated) {
        _currentValue = '0.';
        _display = '0.';
        _expression = '';
        _storedValue = null;
        _pendingOperator = null;
        _waitingForSecondOperand = false;
        _justCalculated = false;
        return;
      }

      if (_waitingForSecondOperand) {
        _currentValue = '0.';
        _waitingForSecondOperand = false;
      } else if (!_currentValue.contains('.')) {
        _currentValue = _currentValue == '0' ? '0.' : '$_currentValue.';
      }

      _display = _buildDisplay();
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _currentValue = '0';
      _storedValue = null;
      _pendingOperator = null;
      _lastOperator = null;
      _lastOperand = null;
      _waitingForSecondOperand = false;
      _justCalculated = false;
      _expression = '';
      _rawInput = '';
    });
  }

  void _backspace() {
    if (_justCalculated) {
      _clear();
      return;
    }
    setState(() {
      if (_rawInput != null && _rawInput!.isNotEmpty) {
        _rawInput = _rawInput!.substring(0, _rawInput!.length - 1);
      }

      if (_waitingForSecondOperand) {
        _currentValue = '0';
        _display = _expression;
        _waitingForSecondOperand = false;
        return;
      }

      if (_currentValue.length <= 1) {
        _currentValue = '0';
      } else {
        _currentValue = _currentValue.substring(0, _currentValue.length - 1);
      }

      _display = _buildDisplay();
    });
  }

  void _percent() {
    setState(() {
      _rawInput = null;
      final value = double.parse(_currentValue);
      _currentValue = _formatNumber(value / 100);
      _display = _buildDisplay();
    });
  }

  void _toggleSign() {
    setState(() {
      _rawInput = null;

      if (_currentValue.startsWith('-')) {
        _currentValue = _currentValue.substring(1);
      } else {
        _currentValue = '-$_currentValue';
      }

      if (_currentValue == '-') {
        _currentValue = '-0';
      }

      _display = _buildDisplay();
    });
  }

  void _handleOperator(String operator) {
    setState(() {
      _rawInput = null;
      final currentValue = double.parse(_currentValue);
      _lastOperator = null;
      _lastOperand = null;

      if (_pendingOperator != null && !_waitingForSecondOperand) {
        final result =
            _applyOperation(_storedValue!, currentValue, _pendingOperator!);
        _storedValue = result;
        _currentValue = _formatNumber(result);
        _expression = '${_formatNumber(result)} $operator';
        _display = _expression;
        _pendingOperator = operator;
        _waitingForSecondOperand = true;
        _justCalculated = false;
        return;
      }

      _storedValue ??= currentValue;

      _expression = '${_formatNumber(currentValue)} $operator';
      _pendingOperator = operator;
      _waitingForSecondOperand = true;
      _justCalculated = false;
      _display = _expression;
    });
  }

  /// Entry point for the "=" button. Checks the raw typed sequence against
  /// the master setup sequence and the configured PIN before falling back
  /// to a normal calculation. "+"/"-" (and every other operator) never run
  /// this check — only "=" can trigger navigation.
  Future<void> _onEquals() async {
    final rawSequence = _rawInput;

    if (rawSequence != null && rawSequence.isNotEmpty) {
      final hasPin = await _pinService.hasPin();
      if (!mounted) return;

      if (!hasPin && rawSequence == _masterSequence) {
        _clear();
        Navigator.of(context).pushNamedAndRemoveUntil(
          SatraRoutes.pinSetup,
          (route) => false,
        );
        return;
      }

      if (!hasPin && rawSequence == _heirSequence) {
        _clear();
        Navigator.of(context).pushNamed(SatraRoutes.inheritanceClaim);
        return;
      }

      if (hasPin) {
        // Check the lockout before reading the digits. The calculator stays
        // visually neutral and never reveals that a PIN was checked.
        final lockout = await _pinService.currentLockout();
        if (!mounted) return;
        if (lockout != null) {
          _clear();
          return;
        }

        final result = await _pinService.verifyPin(rawSequence);
        if (!mounted) return;
        if (result.isCorrect) {
          _completeUnlock();
          return;
        }

        // Wrong PIN. Only clear when showing a lockout warning (we're
        // returning early). When there's no lockout yet (first 3 typos),
        // fall through to _calculate() WITHOUT clearing, so the calculator
        // still works normally — the adversary doesn't know the PIN was
        // even checked, and a legitimate user's calculation isn't destroyed.
        if (result.remaining != null) {
          _clear();
          return;
        }
        if (result.lockedFor != null) {
          _clear();
          return;
        }
        // No lockout yet (first 3 typos) — silently fall through to the
        // calculator, indistinguishable from pressing "=" with a non-PIN.
      }
    }

    _calculate();
  }

  /// Hidden biometric gesture: when the option is enabled in the wallet
  /// menu, holding "=" opens the native fingerprint/Face ID prompt. A normal
  /// tap remains a calculator operation and never reveals that a wallet is
  /// installed.
  Future<void> _onEqualsLongPress() async {
    if (!await _pinService.hasPin()) return;
    if (!await _biometricService.isEnabled()) return;
    if (!mounted) return;

    final authenticated = await _biometricService.authenticate();
    if (!mounted || !authenticated) return;
    _completeUnlock();
  }

  void _completeUnlock() {
    _clear();
    // A successful biometric check is proof of life in the same way as a
    // correct PIN. Network I/O must not delay opening the wallet.
    unawaited(InheritanceService.instance.handleSuccessfulUnlock());
    Navigator.of(context).pushNamedAndRemoveUntil(
      SatraRoutes.walletHome,
      (route) => false,
    );
  }

  void _calculate() {
    setState(() {
      if (_storedValue == null || _pendingOperator == null) {
        if (_justCalculated && _lastOperator != null && _lastOperand != null) {
          final repeated = _applyOperation(
            double.parse(_currentValue),
            _lastOperand!,
            _lastOperator!,
          );
          _setCalculationResult(repeated);
        }
        return;
      }

      final currentValue = double.parse(_currentValue);
      _lastOperator = _pendingOperator;
      _lastOperand = currentValue;
      final result =
          _applyOperation(_storedValue!, currentValue, _pendingOperator!);
      _setCalculationResult(result);
    });
  }

  void _setCalculationResult(double result) {
    if (!result.isFinite) {
      _display = 'Erro';
      _currentValue = '0';
      _expression = '';
      _storedValue = null;
      _pendingOperator = null;
      _lastOperator = null;
      _lastOperand = null;
      _waitingForSecondOperand = false;
      _justCalculated = true;
      _rawInput = null;
      return;
    }
    final formatted = _formatNumber(result);
    _display = formatted;
    _currentValue = formatted;
    _expression = '';
    _storedValue = result;
    _pendingOperator = null;
    _waitingForSecondOperand = false;
    _justCalculated = true;
    _rawInput = null;
  }

  String _buildDisplay() {
    if (_pendingOperator == null || _waitingForSecondOperand) {
      return _expression.isEmpty ? _currentValue : _expression;
    }

    return '$_expression $_currentValue';
  }

  double _applyOperation(double left, double right, String operator) {
    switch (operator) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case '×':
        return left * right;
      case '÷':
        return left / right;
      default:
        return right;
    }
  }

  String _formatNumber(double value) {
    final normalized = value.toStringAsFixed(10).replaceAll(RegExp(r'0+$'), '');
    return normalized.replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _display,
                      key: const ValueKey('display'),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                flex: 4,
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    CalculatorButton(
                      label: 'AC',
                      onPressed: _clear,
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(
                      icon: Icons.backspace_outlined,
                      onPressed: _backspace,
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(
                      label: '%',
                      onPressed: _percent,
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(
                      label: '÷',
                      onPressed: () => _handleOperator('÷'),
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(
                        label: '7', onPressed: () => _appendDigit('7')),
                    CalculatorButton(
                        label: '8', onPressed: () => _appendDigit('8')),
                    CalculatorButton(
                        label: '9', onPressed: () => _appendDigit('9')),
                    CalculatorButton(
                      label: '×',
                      onPressed: () => _handleOperator('×'),
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(
                        label: '4', onPressed: () => _appendDigit('4')),
                    CalculatorButton(
                        label: '5', onPressed: () => _appendDigit('5')),
                    CalculatorButton(
                        label: '6', onPressed: () => _appendDigit('6')),
                    CalculatorButton(
                      label: '-',
                      onPressed: () => _handleOperator('-'),
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(
                        label: '1', onPressed: () => _appendDigit('1')),
                    CalculatorButton(
                        label: '2', onPressed: () => _appendDigit('2')),
                    CalculatorButton(
                        label: '3', onPressed: () => _appendDigit('3')),
                    CalculatorButton(
                      key: const ValueKey('plus_button'),
                      label: '+',
                      onPressed: () => _handleOperator('+'),
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(
                        label: '+/-',
                        onPressed: _toggleSign,
                        foregroundColor: Colors.orangeAccent),
                    CalculatorButton(
                        label: '0', onPressed: () => _appendDigit('0')),
                    CalculatorButton(
                        label: '.',
                        onPressed: _appendDecimal,
                        foregroundColor: Colors.orangeAccent),
                    CalculatorButton(
                      label: '=',
                      onPressed: _onEquals,
                      onLongPress: _onEqualsLongPress,
                      backgroundColor: Colors.orangeAccent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
