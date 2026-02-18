import 'package:flutter/material.dart';

class EmptyAlbums extends StatelessWidget {
  final String message;
  final String? primaryText;
  final VoidCallback? onPrimary;
  final String? secondaryText;
  final VoidCallback? onSecondary;

  const EmptyAlbums({
    super.key,
    required this.message,
    this.primaryText,
    this.onPrimary,
    this.secondaryText,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.album_rounded,
            color: cs.onSurfaceVariant,
            size: 36,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: txt.titleMedium?.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          'Coba pilih folder musik yang benar atau jalankan scan ulang.',
          textAlign: TextAlign.center,
          style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (primaryText != null && onPrimary != null)
              FilledButton.icon(
                onPressed: onPrimary,
                icon: const Icon(Icons.folder_rounded),
                label: Text(primaryText!),
              ),
            if (secondaryText != null && onSecondary != null)
              OutlinedButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(secondaryText!),
              ),
          ],
        ),
      ],
    );
  }
}

class EmptyArtists extends StatelessWidget {
  final String message;
  final String? primaryText;
  final VoidCallback? onPrimary;
  final String? secondaryText;
  final VoidCallback? onSecondary;

  const EmptyArtists({
    super.key,
    required this.message,
    this.primaryText,
    this.onPrimary,
    this.secondaryText,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.people_rounded,
            color: cs.onSurfaceVariant,
            size: 36,
          ),
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: txt.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Coba pilih folder musik yang benar atau jalankan scan ulang.',
          textAlign: TextAlign.center,
          style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (primaryText != null && onPrimary != null)
              FilledButton.icon(
                onPressed: onPrimary,
                icon: const Icon(Icons.folder_rounded),
                label: Text(primaryText!),
              ),
            if (secondaryText != null && onSecondary != null)
              OutlinedButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(secondaryText!),
              ),
          ],
        ),
      ],
    );
  }
}

class EmptySongs extends StatelessWidget {
  final String message;
  final String? primaryText;
  final VoidCallback? onPrimary;
  final String? secondaryText;
  final VoidCallback? onSecondary;

  const EmptySongs({
    super.key,
    required this.message,
    this.primaryText,
    this.onPrimary,
    this.secondaryText,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.music_note_rounded,
            color: cs.onSurfaceVariant,
            size: 36,
          ),
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: txt.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Coba pilih folder musik yang benar atau jalankan scan ulang.',
          textAlign: TextAlign.center,
          style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (primaryText != null && onPrimary != null)
              FilledButton.icon(
                onPressed: onPrimary,
                icon: const Icon(Icons.folder_rounded),
                label: Text(primaryText!),
              ),
            if (secondaryText != null && onSecondary != null)
              OutlinedButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(secondaryText!),
              ),
          ],
        ),
      ],
    );
  }
}
