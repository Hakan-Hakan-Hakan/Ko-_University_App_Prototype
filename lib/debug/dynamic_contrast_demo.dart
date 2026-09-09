import 'package:flutter/material.dart';

import '../widgets/dynamic_contrast_text.dart';

/// Standalone showcase for [DynamicContrastText].
///
/// Deliberately its own entrypoint so no app screen is touched:
///
/// ```sh
/// flutter run -t lib/debug/dynamic_contrast_demo.dart -d <device>
/// ```
///
/// Swipe vertically (TikTok-style PageView). Every caption is one plain
/// white string — the color changes you see are the difference blend
/// resolving against the pixels underneath.
void main() => runApp(const DynamicContrastDemoApp());

class DynamicContrastDemoApp extends StatelessWidget {
  const DynamicContrastDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _DemoFeed(),
    );
  }
}

class _DemoFeed extends StatelessWidget {
  const _DemoFeed();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        key: const ValueKey<String>('contrast-demo-feed'),
        scrollDirection: Axis.vertical,
        children: const [
          _SplitPage(),
          _GradientPage(),
          _BitmapPage(),
          _AnimatedPage(),
        ],
      ),
    );
  }
}

class _CaptionBlock extends StatelessWidget {
  const _CaptionBlock({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DynamicContrastText(
          title,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Figtree'),
        ),
        const SizedBox(height: 12),
        DynamicContrastText(
          caption,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Figtree'),
        ),
      ],
    );
  }
}

/// Page 1: a hard black/white split — the headline crosses it and must
/// bifurcate mid-glyph.
class _SplitPage extends StatelessWidget {
  const _SplitPage();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ColoredBox(color: Colors.black)),
            Expanded(child: ColoredBox(color: Colors.white)),
          ],
        ),
        Center(
          child: _CaptionBlock(
            title: 'Spring Fest at Koç',
            caption: 'One string, two colors — split at the exact pixel',
          ),
        ),
      ],
    );
  }
}

/// Page 2: a diagonal multi-color gradient — every glyph lands on a
/// different backdrop color.
class _GradientPage extends StatelessWidget {
  const _GradientPage();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: const [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF800020),
                Color(0xFFFFD54F),
                Color(0xFFFAF9F6),
                Color(0xFF0D47A1),
              ],
            ),
          ),
        ),
        Center(
          child: _CaptionBlock(
            title: 'ClubUp weekly digest',
            caption: 'Per-pixel complement across a 4-stop gradient',
          ),
        ),
      ],
    );
  }
}

/// Page 3: a real bitmap (the app icon, cover-scaled) — the case a feed
/// actually hits with CachedNetworkImage photos.
class _BitmapPage extends StatelessWidget {
  const _BitmapPage();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: const [
        Image(
          image: AssetImage('assets/branding/clubup_app_icon_1024.png'),
          fit: BoxFit.cover,
        ),
        Center(
          child: _CaptionBlock(
            title: 'Over a real photo',
            caption: 'Same white string, blended against bitmap pixels',
          ),
        ),
      ],
    );
  }
}

/// Page 4: the backdrop slides continuously under a static string, so the
/// text recolors live, frame by frame, with no rebuild of the text itself.
class _AnimatedPage extends StatefulWidget {
  const _AnimatedPage();

  @override
  State<_AnimatedPage> createState() => _AnimatedPageState();
}

class _AnimatedPageState extends State<_AnimatedPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final Alignment slide = AlignmentTween(
              begin: const Alignment(-2, 0),
              end: const Alignment(2, 0),
            ).evaluate(_controller);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: slide.add(const Alignment(-1.6, 0)),
                  end: slide.add(const Alignment(1.6, 0)),
                  colors: const [
                    Color(0xFF09090B),
                    Color(0xFFFAF9F6),
                    Color(0xFF09090B),
                  ],
                ),
              ),
            );
          },
        ),
        const Center(
          child: _CaptionBlock(
            title: 'Live backdrop',
            caption: 'The gradient moves — the text recolors every frame',
          ),
        ),
      ],
    );
  }
}
