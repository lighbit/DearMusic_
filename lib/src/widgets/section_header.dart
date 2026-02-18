import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onTap;

  const SectionHeader({
    super.key,
    required this.title,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (action.isNotEmpty)
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
                child: Text(action),
              ),
          ],
        ),
      ),
    );
  }
}
