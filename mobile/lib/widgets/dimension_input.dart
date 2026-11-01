import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';

/// Two big numeric fields (长 / 宽) + unit segmented control.
class DimensionInput extends StatelessWidget {
  const DimensionInput({
    super.key,
    required this.lengthController,
    required this.widthController,
    required this.unit,
    required this.onUnitChanged,
    this.lengthError,
    this.widthError,
    this.onSwap,
    this.lengthLabel = '长边',
    this.widthLabel = '短边',
    this.autofocus = false,
  });

  final TextEditingController lengthController;
  final TextEditingController widthController;
  final String unit;
  final ValueChanged<String> onUnitChanged;
  final String? lengthError;
  final String? widthError;
  final VoidCallback? onSwap;
  final String lengthLabel;
  final String widthLabel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _field(context, lengthController, lengthLabel, lengthError, autofocus)),
            Padding(
              padding: const EdgeInsets.only(top: 24, left: 6, right: 6),
              child: Text('×', style: TextStyle(fontSize: 22, color: AppColors.sub(context))),
            ),
            Expanded(child: _field(context, widthController, widthLabel, widthError, false)),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                onPressed: onSwap,
                tooltip: '交换长宽',
                iconSize: 24,
                constraints: const BoxConstraints(minWidth: AppSizes.minTouch, minHeight: AppSizes.minTouch),
                icon: Icon(Icons.swap_horiz_rounded, color: AppColors.accent(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'mm', label: Text('mm')),
                ButtonSegment<String>(value: 'cm', label: Text('cm')),
              ],
              selected: <String>{unit},
              showSelectedIcon: false,
              onSelectionChanged: (Set<String> selection) => onUnitChanged(selection.first),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                '只填数字，单位用左边的 mm / cm 切换',
                style: TextStyle(fontSize: 12.5, color: AppColors.sub(context)),
                maxLines: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(BuildContext context, TextEditingController controller, String label, String? error, bool autofocus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.sub(context), fontWeight: FontWeight.w600)),
        ),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          textAlign: TextAlign.center,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            LengthLimitingTextInputFormatter(8),
          ],
          style: numberStyle(context, size: 24),
          decoration: InputDecoration(
            hintText: unit == 'cm' ? '80' : '800',
            suffixText: unit,
            suffixStyle: TextStyle(fontSize: 13, color: AppColors.sub(context)),
            errorText: error,
            errorMaxLines: 2,
          ),
        ),
      ],
    );
  }
}

/// Stepper + direct input for piece counts.
class QuantityInput extends StatelessWidget {
  const QuantityInput({super.key, required this.controller, this.min = 1, this.max = 20000, this.onChanged});

  final TextEditingController controller;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;

  int get _value => int.tryParse(controller.text) ?? min;

  void _set(BuildContext context, int value) {
    final int clamped = value.clamp(min, max);
    controller.text = '$clamped';
    onChanged?.call(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          onPressed: () => _set(context, _value - 1),
          icon: const Icon(Icons.remove),
          tooltip: '减少一片',
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: numberStyle(context, size: 24),
            onChanged: (String value) => onChanged?.call(int.tryParse(value) ?? min),
            decoration: const InputDecoration(suffixText: '片'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton.filledTonal(
          onPressed: () => _set(context, _value + 1),
          icon: const Icon(Icons.add),
          tooltip: '增加一片',
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        ),
      ],
    );
  }
}
