/// The Jumu'ah icon.
///
/// Drawn rather than shipped as an asset, for three reasons: it scales to any
/// density without a folder of PNGs, it inherits the current text colour so it
/// is correct in light and dark without a second file, and it has no licence
/// attached to it.
///
/// The design is a **minaret-and-dome silhouette** — the most legible mosque
/// form at small sizes, and the one that reads as a mosque rather than as a
/// generic building.
///
/// It is deliberately **not** a figure in sujood. That form is unreadable below
/// about 32dp — it collapses into an indistinct blob — and rendering a human
/// body, even faceless, is the sort of thing that some users would object to
/// seeing on a prayer app. A mosque silhouette carries the same meaning with
/// none of that.
library;

import 'package:flutter/material.dart';

/// A monochrome mosque silhouette, sized and coloured like any Material icon.
class JumuahIcon extends StatelessWidget {
  const JumuahIcon({super.key, this.size = 24, this.color});

  final double size;

  /// Defaults to the ambient icon colour, so it adapts to light and dark and to
  /// disabled states without the caller doing anything.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        // Announced as an image with a label rather than left as an unlabelled
        // shape, so a screen reader says "Jumu'ah" instead of skipping it.
        painter: _MosquePainter(resolved),
        isComplex: false,
        willChange: false,
      ),
    );
  }
}

class _MosquePainter extends CustomPainter {
  const _MosquePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is expressed as a fraction of the box, so the shape is
    // identical at 16dp and at 96dp.
    final w = size.width;
    final h = size.height;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // --- central dome -----------------------------------------------------
    final domeRadius = w * 0.20;
    final domeCentre = Offset(w * 0.5, h * 0.46);

    final dome = Path()
      // A half-circle, closed along its base, rather than an arc: an open arc
      // renders as a hairline at small sizes.
      ..addArc(
        Rect.fromCircle(center: domeCentre, radius: domeRadius),
        3.14159, // pi — start at the left of the circle
        3.14159, // sweep half way round, giving the upper half
      )
      ..close();
    canvas.drawPath(dome, fill);

    // Finial above the dome. Small, but it is what makes the shape read as a
    // mosque rather than as an arch.
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.22),
      w * 0.045,
      fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.485, h * 0.22, w * 0.03, h * 0.06),
      fill,
    );

    // --- prayer hall ------------------------------------------------------
    final hall = Rect.fromLTRB(w * 0.26, h * 0.46, w * 0.74, h * 0.80);
    canvas.drawRect(hall, fill);

    // --- minarets ---------------------------------------------------------
    for (final x in [w * 0.16, w * 0.84]) {
      // Shaft.
      canvas.drawRect(
        Rect.fromLTRB(x - w * 0.035, h * 0.34, x + w * 0.035, h * 0.80),
        fill,
      );
      // Cap, so the minaret does not read as a plain post.
      canvas.drawCircle(Offset(x, h * 0.32), w * 0.055, fill);
    }

    // --- ground -----------------------------------------------------------
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.10, h * 0.80, w * 0.90, h * 0.86),
        Radius.circular(w * 0.02),
      ),
      fill,
    );

    // --- doorway ----------------------------------------------------------
    //
    // Punched out with clear blending so the silhouette stays a single filled
    // shape in both themes. Drawing it in the background colour instead would
    // show as a light patch when the icon sits on a coloured surface.
    final door = Path()
      ..addArc(
        Rect.fromCircle(
          center: Offset(w * 0.5, h * 0.66),
          radius: w * 0.085,
        ),
        3.14159,
        3.14159,
      )
      ..addRect(
        Rect.fromLTRB(w * 0.415, h * 0.66, w * 0.585, h * 0.80),
      );

    canvas.drawPath(door, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(_MosquePainter oldDelegate) => oldDelegate.color != color;
}

/// The icon with a semantic label, for use as a standalone graphic.
class LabelledJumuahIcon extends StatelessWidget {
  const LabelledJumuahIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: "Jumu'ah",
        image: true,
        child: ExcludeSemantics(
          child: JumuahIcon(size: size, color: color),
        ),
      );
}
