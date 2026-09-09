import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Text that inverts its color per-pixel against whatever is painted
/// beneath it (images, video frames, gradients), Instagram/Twitter style.
///
/// The widget paints strictly white glyphs and composites them onto the
/// backdrop with [BlendMode.difference] (or [BlendMode.exclusion]):
///
/// ```
/// result = |backdrop - white|  =>  dark backdrop -> light text
///                                  light backdrop -> dark text
/// ```
///
/// Because the blend happens at composite time on the GPU, a single string
/// straddling a black/white boundary bifurcates its color exactly at that
/// boundary — no CPU-side pixel decoding, no `Image.toByteData`.
///
/// ### Placement rules (these are load-bearing)
///
/// * The widget must be painted **after** its background in the same
///   paint order — i.e. as a later sibling in the same [Stack]:
///
/// ```dart
/// Stack(
///   fit: StackFit.expand,
///   children: [
///     CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
///     Align(
///       alignment: Alignment.bottomLeft,
///       child: DynamicContrastText(
///         caption,
///         fontSize: 15,
///         fontWeight: FontWeight.w600,
///       ),
///     ),
///   ],
/// )
/// ```
///
/// * Do **not** wrap this widget (or the subtree between it and its
///   background) in a [RepaintBoundary]: the boundary rasterizes the
///   subtree into its own offscreen layer, so the blend sees a transparent
///   backdrop instead of the image. Putting a [RepaintBoundary] around the
///   *entire* feed item (background + text together) is fine and is the
///   recommended pattern for scrolling feeds.
/// * The `saveLayer` this widget records is clipped to the text's own
///   bounds, so the offscreen allocation is a few text lines tall — not
///   the whole feed card.
///
/// ### Known limitations
///
/// * A ~50% gray backdrop inverts to ~50% gray text. That is inherent to
///   difference blending (Instagram has the same failure mode); if the
///   content regularly contains large mid-gray regions, keep a scrim or
///   shadow behind the text instead.
/// * Backdrops hosted in platform views (`UiKitView`/`AndroidView`, e.g.
///   some WebView/map/video configurations) are composited by the OS, not
///   by Flutter, so there is no backdrop to blend against. Texture-backed
///   video (`VideoPlayer`'s default on mobile) works.
class DynamicContrastText extends StatelessWidget {
  /// Creates dynamic-contrast text from a plain [String].
  const DynamicContrastText(
    String this.text, {
    super.key,
    this.style,
    this.fontSize,
    this.fontWeight,
    this.letterSpacing,
    this.height,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.blendMode = BlendMode.difference,
  })  : span = null,
        assert(
          blendMode == BlendMode.difference ||
              blendMode == BlendMode.exclusion,
          'Only difference/exclusion preserve the white-base inversion math.',
        );

  /// Creates dynamic-contrast text from a [TextSpan] tree.
  ///
  /// Per-span *structural* styling (size, weight, spacing) is respected,
  /// but any per-span [TextStyle.color] is overridden to white in the
  /// root style and asserted against in debug mode: a non-white base color
  /// breaks the inversion scaling.
  const DynamicContrastText.rich(
    TextSpan this.span, {
    super.key,
    this.style,
    this.fontSize,
    this.fontWeight,
    this.letterSpacing,
    this.height,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.blendMode = BlendMode.difference,
  })  : text = null,
        assert(
          blendMode == BlendMode.difference ||
              blendMode == BlendMode.exclusion,
          'Only difference/exclusion preserve the white-base inversion math.',
        );

  /// Plain-text content. Mutually exclusive with [span].
  final String? text;

  /// Rich-text content. Mutually exclusive with [text].
  final TextSpan? span;

  /// Optional base style. Its color is ignored — the blend tree requires a
  /// strict white base — but every structural property carries through.
  final TextStyle? style;

  /// Structural overrides applied on top of [style].
  final double? fontSize;
  final FontWeight? fontWeight;
  final double? letterSpacing;
  final double? height;

  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  /// [BlendMode.difference] (hard inversion, default) or
  /// [BlendMode.exclusion] (lower-contrast, softer inversion).
  final BlendMode blendMode;

  TextStyle get _effectiveStyle => (style ?? const TextStyle()).copyWith(
        // Strict white base: difference/exclusion against pure white is the
        // only configuration that yields a mathematically exact inversion.
        color: const Color(0xFFFFFFFF),
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        // Glyph decorations that paint outside the glyph mask (shadows,
        // background paints) blend unpredictably; strip them.
        shadows: const <Shadow>[],
        background: null,
      );

  bool _debugSpanColorsAreWhite(TextSpan root) {
    bool ok = true;
    root.visitChildren((InlineSpan child) {
      final Color? color = child.style?.color;
      if (color != null && color != const Color(0xFFFFFFFF)) {
        ok = false;
        return false;
      }
      return true;
    });
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      span == null || _debugSpanColorsAreWhite(span!),
      'DynamicContrastText.rich spans must not set a non-white color: the '
      'difference blend inverts the backdrop only for pure-white source '
      'pixels. Remove TextStyle.color from the spans.',
    );
    final Text child = span != null
        ? Text.rich(
            span!,
            style: _effectiveStyle,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
          )
        : Text(
            text!,
            style: _effectiveStyle,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
          );
    return _BackdropBlend(blendMode: blendMode, child: child);
  }
}

/// Composites its child onto the current canvas through [blendMode].
///
/// This is the piece `ColorFiltered` cannot provide: a [ColorFilter] runs
/// over its own child's raster in isolation (difference against a
/// transparent layer, which would flood the layer opaque white), whereas
/// the effect needs the child blended against the *backdrop*. A
/// `Canvas.saveLayer` with a blend-mode [Paint] is the primitive
/// `ColorFiltered` itself lowers to — used here directly so the layer is
/// composited against previously painted siblings, entirely on the GPU.
class _BackdropBlend extends SingleChildRenderObjectWidget {
  const _BackdropBlend({required this.blendMode, super.child});

  final BlendMode blendMode;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackdropBlend(blendMode);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBackdropBlend renderObject,
  ) {
    renderObject.blendMode = blendMode;
  }
}

class _RenderBackdropBlend extends RenderProxyBox {
  _RenderBackdropBlend(this._blendMode);

  BlendMode _blendMode;
  set blendMode(BlendMode value) {
    if (value == _blendMode) {
      return;
    }
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }
    // Tight bounds: the offscreen buffer saveLayer allocates is limited to
    // the text's own rect, keeping the per-frame cost negligible inside
    // high-velocity vertical PageViews / timelines. Painting through
    // context.canvas (rather than a compositing layer) is deliberate — the
    // blend must resolve against siblings already drawn on this canvas.
    final Rect bounds = offset & size;
    context.canvas.saveLayer(bounds, Paint()..blendMode = _blendMode);
    context.paintChild(child!, offset);
    context.canvas.restore();
  }
}
