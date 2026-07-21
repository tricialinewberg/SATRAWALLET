import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/pin_service.dart';
import '../widgets/calculator_button.dart';

/// Fixed master sequence that opens the one-time initial setup, but only
/// while no personal PIN has been configured yet. Digits are compared
/// against the raw keystrokes (see [_rawInput]), not the collapsed display
/// value, so a leading zero isn't lost the way a real calculator would lose it.
const _masterSequence = '5893';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final PinService _pinService = PinService();

  String _display = '0';
  String _currentValue = '0';
  double? _storedValue;
  String? _pendingOperator;
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
        _currentValue = _currentValue == '0' ? '0.' : _currentValue + '.';
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
      _waitingForSecondOperand = false;
      _justCalculated = false;
      _expression = '';
      _rawInput = '';
    });
  }

  void _backspace() {
    setState(() {
      if (_justCalculated) {
        _clear();
        return;
      }

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

      if (_pendingOperator != null && !_waitingForSecondOperand) {
        final result = _applyOperation(_storedValue!, currentValue, _pendingOperator!);
        _storedValue = result;
        _currentValue = _formatNumber(result);
        _expression = '${_formatNumber(result)} $operator';
        _display = _expression;
        _pendingOperator = operator;
        _waitingForSecondOperand = true;
        _justCalculated = false;
        return;
      }

      if (_storedValue == null) {
        _storedValue = currentValue;
      }

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
          SatraRoutes.splash,
          (route) => false,
        );
        return;
      }

      if (hasPin) {
        final matches = await _pinService.verifyPin(rawSequence);
        if (!mounted) return;
        if (matches) {
          _clear();
          Navigator.of(context).pushNamedAndRemoveUntil(
            SatraRoutes.walletHome,
            (route) => false,
          );
          return;
        }
      }
    }

    _calculate();
  }

  void _calculate() {
    setState(() {
      if (_storedValue == null || _pendingOperator == null) {
        return;
      }

      final currentValue = double.parse(_currentValue);
      final result = _applyOperation(_storedValue!, currentValue, _pendingOperator!);
      _display = _formatNumber(result);
      _currentValue = _formatNumber(result);
      _expression = '';
      _storedValue = result;
      _pendingOperator = null;
      _waitingForSecondOperand = false;
      _justCalculated = true;
      _rawInput = null;
    });
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    _display,
                    key: const ValueKey('display'),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w300),
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
                    CalculatorButton(label: '7', onPressed: () => _appendDigit('7')),
                    CalculatorButton(label: '8', onPressed: () => _appendDigit('8')),
                    CalculatorButton(label: '9', onPressed: () => _appendDigit('9')),
                    CalculatorButton(
                      label: '×',
                      onPressed: () => _handleOperator('×'),
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(label: '4', onPressed: () => _appendDigit('4')),
                    CalculatorButton(label: '5', onPressed: () => _appendDigit('5')),
                    CalculatorButton(label: '6', onPressed: () => _appendDigit('6')),
                    CalculatorButton(
                      label: '-',
                      onPressed: () => _handleOperator('-'),
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(label: '1', onPressed: () => _appendDigit('1')),
                    CalculatorButton(label: '2', onPressed: () => _appendDigit('2')),
                    CalculatorButton(label: '3', onPressed: () => _appendDigit('3')),
                    CalculatorButton(
                      key: const ValueKey('plus_button'),
                      label: '+',
                      onPressed: () => _handleOperator('+'),
                      foregroundColor: Colors.orangeAccent,
                    ),
                    CalculatorButton(label: '+/-', onPressed: _toggleSign, foregroundColor: Colors.orangeAccent),
                    CalculatorButton(label: '0', onPressed: () => _appendDigit('0')),
                    CalculatorButton(label: '.', onPressed: _appendDecimal, foregroundColor: Colors.orangeAccent),
                    CalculatorButton(
                      label: '=',
                      onPressed: _onEquals,
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
