import 'package:flutter/material.dart';

class ShortcutCard extends StatelessWidget {
  final Icon icon;
  final String title;
  final VoidCallback onTap;

  const ShortcutCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const radius = BorderRadius.all(Radius.circular(16));

    return Expanded(
      child: Card.filled(
        shape: const RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              spacing: 8,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    color: colorScheme.secondaryContainer,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: IconTheme(
                      data: IconThemeData(
                        color: colorScheme.onSecondaryContainer,
                      ),
                      child: icon,
                    ),
                  ),
                ),
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
