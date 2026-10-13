import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Une carte à la fois, qu'on fait glisser sur le côté pour passer à la suivante.
/// La hauteur suit la carte affichée, et des points indiquent la position.
class SwipeCards extends StatefulWidget {
  final int count;
  final IndexedWidgetBuilder itemBuilder;

  const SwipeCards({super.key, required this.count, required this.itemBuilder});

  @override
  State<SwipeCards> createState() => _SwipeCardsState();
}

class _SwipeCardsState extends State<SwipeCards> {
  final _controller = PageController();
  final _heights = <int, double>{};
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final p = _controller.page;
      if (p != null && p != _page) setState(() => _page = p);
    });
  }

  @override
  void didUpdateWidget(SwipeCards old) {
    super.didUpdateWidget(old);
    if (widget.count != old.count) _heights.removeWhere((i, _) => i >= widget.count);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Hauteur interpolée entre la carte de gauche et celle de droite pendant le glissement.
  double get _height {
    final page = _page.clamp(0, (widget.count - 1).toDouble()).toDouble();
    final i = page.floor();
    final a = _heights[i] ?? _heights.values.fold<double>(0, (m, h) => h > m ? h : m);
    final b = _heights[i + 1] ?? a;
    return a + (b - a) * (page - i);
  }

  @override
  Widget build(BuildContext context) {
    final current = _page.round().clamp(0, widget.count - 1);
    final height = _height;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        // Avant la première mesure, on laisse une hauteur raisonnable.
        height: height > 0 ? height : 170,
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.count,
          itemBuilder: (context, i) => OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: _MeasureSize(
              onChange: (h) {
                if (mounted && _heights[i] != h) setState(() => _heights[i] = h);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: widget.itemBuilder(context, i),
              ),
            ),
          ),
        ),
      ),
      if (widget.count > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.count; i++)
              GestureDetector(
                onTap: () =>
                    _controller.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == current ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == current
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ]),
        ),
    ]);
  }
}

/// Signale la hauteur de son enfant après chaque mise en page.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onChange;

  const _MeasureSize({required this.onChange, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize renderObject) => renderObject.onChange = onChange;
}

class _RenderMeasureSize extends RenderProxyBox {
  ValueChanged<double> onChange;
  double? _last;

  _RenderMeasureSize(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h != _last) {
      _last = h;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(h));
    }
  }
}
