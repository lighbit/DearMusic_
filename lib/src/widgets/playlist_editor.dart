import 'package:dearmusic/src/logic/artwork_memory.dart';
import 'package:dearmusic/src/models/playlist_models.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

typedef OnPlaylistSaved = Future<void> Function(Playlist pl);

Future<void> showCreatePlaylistSheet({
  required BuildContext context,
  required List<SongModel> allSongs,
  required OnPlaylistSaved onSaved,
  required OnAudioQuery queryApi,
  Playlist? edit,
}) async {
  final cs = Theme.of(context).colorScheme;
  final mq = MediaQuery.of(context);

  final selectedIds = {...?edit?.songIds};
  final byId = {for (final s in allSongs) s.id: s};

  final missing = selectedIds.where((id) => !byId.containsKey(id)).toList();

  List<SongModel> merged = allSongs;
  if (missing.isNotEmpty) {
    final all = await queryApi.querySongs();
    final idx = {for (final s in all) s.id: s};
    final recovered = <SongModel>[
      for (final id in missing)
        if (idx[id] != null && idx[id]!.uri != null) idx[id]!,
    ];

    final selectedFromAll = <SongModel>[
      for (final id in selectedIds)
        if (byId[id] != null) byId[id]!,
    ];
    final distinctOther = <SongModel>[
      ...allSongs.where((s) => !selectedIds.contains(s.id)),
      ...recovered.where((s) => !allSongs.any((x) => x.id == s.id)),
    ];

    merged = [...selectedFromAll, ...recovered, ...distinctOther];
  }

  final controller = _PlaylistEditorController(
    name: edit?.name ?? '',
    selected: selectedIds,
  );

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: cs.surface,
    constraints: BoxConstraints(
      maxHeight: mq.size.height - mq.padding.top - 90,
    ),
    builder: (ctx) => _PlaylistEditorView(
      allSongs: merged,
      controller: controller,
      onSave: (name, ids) async {
        if (name.trim().isEmpty || ids.isEmpty) return;
        final pl = Playlist(
          id: edit?.id ?? _genId(),
          name: name.trim(),
          songIds: ids.toList(),
          createdAt: edit?.createdAt ?? DateTime.now(),
        );
        await onSaved(pl);
        if (ctx.mounted) Navigator.pop(ctx);
      },
    ),
  );
}

String _genId() => DateTime.now().millisecondsSinceEpoch.toString();

class _PlaylistEditorController {
  String name;
  final Set<int> selected;

  _PlaylistEditorController({required this.name, required this.selected});

  bool toggle(int id) =>
      selected.contains(id) ? selected.remove(id) : selected.add(id);
}

class _PlaylistEditorView extends StatefulWidget {
  final List<SongModel> allSongs;
  final _PlaylistEditorController controller;
  final void Function(String name, Set<int> ids) onSave;

  const _PlaylistEditorView({
    required this.allSongs,
    required this.controller,
    required this.onSave,
  });

  @override
  State<_PlaylistEditorView> createState() => _PlaylistEditorViewState();
}

class _PlaylistEditorViewState extends State<_PlaylistEditorView> {
  final _nameCtrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.controller.name;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    final songs = _filter(widget.allSongs, _q);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        children: [
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: easy.tr("playlist.namePlaceholder"),
              border: OutlineInputBorder(borderSide: BorderSide.none),
              filled: true,
            ),
            onChanged: (value) {
              HapticFeedback.lightImpact();
              widget.controller.name = value;
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              hintText: easy.tr("playlist.searchPlaceholder"),
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderSide: BorderSide.none),
              filled: true,
            ),
            onChanged: (value) {
              HapticFeedback.lightImpact();
              setState(() => _q = value);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  easy.tr(
                    "playlist.selectedCount",
                    namedArgs: {
                      "count": "${widget.controller.selected.length}",
                    },
                  ),
                  style: txt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.controller.selected.isNotEmpty)
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => widget.controller.selected.clear());
                  },
                  child: Text(easy.tr("playlist.clearAll")),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: songs.length,
              separatorBuilder: (_, __) => Divider(
                height: 8,
                thickness: 0.6,
                color: cs.outlineVariant.withOpacity(0.4),
              ),
              itemBuilder: (_, i) {
                final s = songs[i];
                final checked = widget.controller.selected.contains(s.id);
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => widget.controller.toggle(s.id));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: FutureBuilder<Widget>(
                              future: ArtworkMemCache.I.imageWidget(
                                id: s.albumId ?? s.id,
                                type: s.albumId != null
                                    ? ArtworkType.ALBUM
                                    : ArtworkType.AUDIO,
                                slot: ArtworkSlot.gridSmall,
                                radius: BorderRadius.circular(12),
                                placeholder: Container(
                                  color: cs.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              builder: (_, snap) =>
                                  snap.data ?? SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: txt.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),

                              Row(
                                children: [
                                  Icon(
                                    Icons.headphones_rounded,
                                    size: 14,
                                    color: cs.onSurfaceVariant.withOpacity(0.8),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      s.album ?? '—',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: txt.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurfaceVariant.withOpacity(
                                          0.85,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),

                              Row(
                                children: [
                                  Icon(
                                    Icons.person_rounded,
                                    size: 13,
                                    color: cs.onSurfaceVariant.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      s.artist ?? '—',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: txt.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        fontStyle: FontStyle.italic,
                                        color: cs.onSurfaceVariant.withOpacity(
                                          0.75,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Checkbox(
                          value: checked,
                          onChanged: (_) {
                            HapticFeedback.lightImpact();
                            setState(() => widget.controller.toggle(s.id));
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Text(easy.tr("playlist.cancel")),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onSave(
                      widget.controller.name,
                      widget.controller.selected,
                    );
                  },
                  child: Text(easy.tr("playlist.save")),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<SongModel> _filter(List<SongModel> src, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) {
      final sel = src.where((x) => widget.controller.selected.contains(x.id));
      final rest = src.where((x) => !widget.controller.selected.contains(x.id));
      return [...sel, ...rest];
    }
    return src
        .where(
          (x) =>
              x.title.toLowerCase().contains(s) ||
              (x.artist ?? '').toLowerCase().contains(s) ||
              (x.album ?? '').toLowerCase().contains(s),
        )
        .toList();
  }
}
