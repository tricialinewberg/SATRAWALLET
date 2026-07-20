import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

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
      home: const CalculatorScreen(),
    );
  }
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  String _currentValue = '0';
  double? _storedValue;
  String? _pendingOperator;
  bool _waitingForSecondOperand = false;
  bool _justCalculated = false;
  String _expression = '';
  bool _showWelcomeScreen = false;

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
        return;
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
    });
  }

  void _backspace() {
    setState(() {
      if (_justCalculated) {
        _clear();
        return;
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
      final value = double.parse(_currentValue);
      _currentValue = _formatNumber(value / 100);
      _display = _buildDisplay();
    });
  }

  void _toggleSign() {
    setState(() {
      if (_currentValue == '3221') {
        _showWelcomeScreen = true;
        _display = 'Seja bem-vindo(a) ao Satra';
        return;
      }

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
    if (_showWelcomeScreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Seja bem-vindo(a) ao Satra',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                    CalculatorButton(label: '=', onPressed: _calculate, backgroundColor: Colors.orangeAccent),
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

class CalculatorButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  const CalculatorButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.backgroundColor = const Color(0xFF2C2C2C),
    this.foregroundColor = Colors.white,
  }) : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: 26, color: foregroundColor)
              : Text(
                  label!,
                  style: TextStyle(
                    fontSize: 28,
                    color: foregroundColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}
