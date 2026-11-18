import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/errors.dart';
import '../services/file_store.dart';
import '../services/lyrics_corrections.dart';
import '../services/lyrics_layout.dart';
import '../services/repository.dart';
import '../theme.dart';

/// Correction des paroles : on touche une ligne du PDF, on corrige le texte,
/// l'appli réécrit la ligne (Arial) et laisse tout le reste intact.
/// Renvoie le chemin du nouveau PDF une fois enregistré.
class LyricsEditScreen extends StatefulWidget {
  final Song song;
  const LyricsEditScreen({super.key, required this.song});

  @override
  State<LyricsEditScreen> createState() => _LyricsEditScreenState();
}

class _PageRgba {
  final Uint8List rgba;
  final int width, height;
  _PageRgba(this.rgba, this.width, this.height);
}

class _LyricsEditScreenState extends State<LyricsEditScreen> {
  static const _renderWidth = 1000;

  String? _error;
  String? _busy = 'Ouverture des paroles…';
  late String _originalPath;
  late Uint8List _original;
  late LyricsFonts _fonts;
  List<LyricsPage> _pages = const [];
  final _originalPixels = <int, _PageRgba>{};
  Map<String, LyricsEdit> _saved = const {};
  final _edits = <String, LyricsEdit>{};
  Uint8List? _preview;
  List<Uint8List?> _images = const [];
  int _version = 0;

  bool get _dirty {
    if (_edits.length != _saved.length) return true;
    for (final e in _edits.entries) {
      final s = _saved[e.key];
      if (s == null || s.text != e.value.text) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final (originalPath, saved) = await LyricsCorrections.load(widget.song);
      _originalPath = originalPath;
      _original = await FileStore.instance.load(Repository.lyricsBucket, originalPath);
      _pages = extractLyrics(_original);
      if (_pages.every((p) => p.lines.isEmpty)) {
        throw 'Ce PDF ne contient pas de texte modifiable (c\'est sans doute une image ou un scan).';
      }
      try {
        _fonts = await LyricsCorrections.fonts();
      } catch (_) {
        throw 'La police Arial n\'est pas encore installée dans l\'appli.';
      }
      // Ne garde que les corrections qui correspondent encore à une ligne.
      final keys = {for (final p in _pages) ...p.segments.map((s) => s.key)};
      _saved = {for (final e in saved.entries) if (keys.contains(e.key)) e.key: e.value};
      _edits.addAll(_saved);
      await _render();
    } catch (e) {
      if (mounted) setState(() => _error = e is String ? e : explain(e));
    }
  }

  /// Refait l'aperçu avec les corrections en cours, puis ses images.
  Future<void> _render() async {
    final version = ++_version;
    final pdf = _edits.isEmpty ? _original : await applyLyricsEdits(_original, _pages, _edits, _fonts);
    final renderer = await openPageRenderer(Uint8List.fromList(pdf));
    if (renderer == null) {
      throw 'La correction des paroles se fait depuis la version web de l\'appli.';
    }
    try {
      final images = <Uint8List?>[];
      for (var i = 0; i < renderer.pageCount; i++) {
        images.add(await renderer.render(i, _renderWidth));
      }
      if (version != _version || !mounted) return;
      setState(() {
        _preview = pdf;
        _images = images;
        _busy = null;
      });
    } finally {
      renderer.close();
    }
  }

  /// Pixels de la page d'origine, pour retrouver la couleur d'une ligne.
  Future<_PageRgba?> _pixels(int page) async {
    final cached = _originalPixels[page];
    if (cached != null) return cached;
    final renderer = await openPageRenderer(Uint8List.fromList(_original));
    if (renderer == null) return null;
    try {
      final jpeg = await renderer.render(page, _renderWidth);
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return _originalPixels[page] = _PageRgba(data.buffer.asUint8List(), frame.image.width, frame.image.height);
    } finally {
      renderer.close();
    }
  }

  LyricsSegment? _hit(int page, Offset local, Size shown) {
    final p = _pages[page];
    final scale = p.size.width / shown.width;
    final pt = local * scale;
    LyricsSegment? best;
    var bestDist = double.infinity;
    for (final s in p.segments) {
      final box = s.box.inflate(4);
      if (box.contains(pt)) return s;
      final d = (box.center - pt).distance;
      if (pt.dy >= box.top - 6 && pt.dy <= box.bottom + 6 && d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    return best;
  }

  Future<void> _editSegment(LyricsSegment s) async {
    final current = _edits[s.key]?.text ?? s.text;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LineEditor(original: s.text, current: current),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = 'Mise à jour de l\'aperçu…');
    try {
      if (result == s.text) {
        _edits.remove(s.key);
      } else {
        final pixels = await _pixels(s.page);
        final color = pixels == null
            ? const Color(0xFF000000)
            : sampleTextColor(pixels.rgba, pixels.width, pixels.height, s.box, pixels.width / _pages[s.page].size.width);
        _edits[s.key] = LyricsEdit(result, color);
      }
      await _render();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is String ? e : explain(e))));
      }
    }
  }

  Future<void> _save() async {
    final pdf = _preview;
    if (pdf == null) return;
    setState(() => _busy = 'Enregistrement…');
    try {
      final path = await LyricsCorrections.save(
        song: widget.song,
        originalPath: _originalPath,
        edits: Map.of(_edits),
        pdf: pdf,
        onProgress: (step) {
          if (mounted) setState(() => _busy = step);
        },
      );
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : ${explain(e)}')));
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner les corrections ?'),
        content: const Text('Les corrections non enregistrées seront perdues.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuer')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abandonner')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _error == null && _images.isNotEmpty;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Modifier les paroles'),
            Text(widget.song.title, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ]),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: ready && _busy == null && _dirty ? _save : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Enregistrer'),
              ),
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                ),
              )
            : Stack(children: [
                if (ready)
                  Column(children: [
                    Container(
                      width: double.infinity,
                      color: AppColors.gold.withValues(alpha: 0.15),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Icon(Icons.touch_app_rounded, size: 20, color: theme.colorScheme.tertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _edits.isEmpty
                                ? 'Touche une ligne pour la corriger.'
                                : '${_edits.length} ligne${_edits.length > 1 ? 's' : ''} corrigée${_edits.length > 1 ? 's' : ''} (encadrées en doré). Touche une ligne pour la corriger.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _images.length,
                        itemBuilder: (context, i) => _page(i),
                      ),
                    ),
                  ]),
                if (_busy != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(alpha: ready ? 0.6 : 1),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(_busy!),
                        ]),
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }

  Widget _page(int i) {
    final page = i < _pages.length ? _pages[i] : null;
    final image = _images[i];
    if (page == null || image == null) return const SizedBox.shrink();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 12),
          child: AspectRatio(
            aspectRatio: page.size.width / page.size.height,
            child: LayoutBuilder(builder: (context, c) {
              final scale = c.maxWidth / page.size.width;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (_busy != null) return;
                  final s = _hit(i, d.localPosition, c.biggest);
                  if (s != null) _editSegment(s);
                },
                child: Stack(children: [
                  Positioned.fill(child: Image.memory(image, fit: BoxFit.fill, gaplessPlayback: true)),
                  for (final s in page.segments.where((s) => _edits.containsKey(s.key)))
                    Positioned(
                      left: (s.box.left - 4) * scale,
                      top: (s.box.top - 3) * scale,
                      width: (s.box.width + 8) * scale,
                      height: (s.box.height + 6) * scale,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.gold, width: 2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Feuille de correction d'une ligne.
class _LineEditor extends StatefulWidget {
  final String original;
  final String current;
  const _LineEditor({required this.original, required this.current});

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rtl = isRtlText(_text.text.isEmpty ? widget.original : _text.text);
    final changed = widget.current != widget.original;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Corriger la ligne', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: true,
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          textAlign: rtl ? TextAlign.right : TextAlign.left,
          minLines: 1,
          maxLines: 3,
          style: const TextStyle(fontSize: 20, height: 1.6, fontFamilyFallback: ['Amiri']),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, ''),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Effacer la ligne'),
          ),
          if (changed)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, widget.original),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Remettre l\'original'),
            ),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, _text.text.trim()),
            child: const Text('Valider'),
          ),
        ]),
      ]),
    );
  }
}
