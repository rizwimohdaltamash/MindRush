import 'package:flutter/material.dart';

import '../theme.dart';

/// Numeric keypad for Sprint Duels.
///
/// Digits only -- every generated answer is a non-negative whole number, so a
/// minus or decimal key would be dead weight on a screen where speed is the
/// whole point.
class Keypad extends StatelessWidget {
  const Keypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.accent,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
          _Key(label: digit, onTap: () => onDigit(digit)),
        const SizedBox.shrink(),
        _Key(label: '0', onTap: () => onDigit('0')),
        _Key(
          icon: Icons.backspace_outlined,
          accent: accent,
          onTap: onBackspace,
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap, this.accent});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final content = icon != null
        ? Icon(icon, color: accent ?? AppColors.text, size: 22)
        : Text(
            label!,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          );

    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: content,
        ),
      ),
    );
  }
}
