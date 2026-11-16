import 'package:flutter/material.dart';

import 'design.dart';

class ViewSwitchOption {
  final String label;
  final Key key;
  final VoidCallback? onSelected;
  const ViewSwitchOption(this.label, this.key, this.onSelected);
}

/// Keeps related views in one place without replacing their owning state.
class ViewSwitch extends StatelessWidget {
  final int selected;
  final List<ViewSwitchOption> options;
  const ViewSwitch({super.key, required this.selected, required this.options});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xffe9edf4),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < options.length; i++)
              Expanded(
                child: Semantics(
                  selected: selected == i,
                  inMutuallyExclusiveGroup: true,
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: selected == i ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected == i ? blue : Colors.transparent,
                      ),
                    ),
                    child: TextButton(
                      key: options[i].key,
                      onPressed: options[i].onSelected == null
                          ? null
                          : selected == i
                          ? () {}
                          : options[i].onSelected,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
                        ),
                        foregroundColor: selected == i ? blue : muted,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: Text(
                        options[i].label,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
