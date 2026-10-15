import 'package:bio_flutter/bio_flutter.dart';
import 'package:flutter/material.dart';

/// Shared colors, text, and decorations for the protein engineering plugin.
///
/// Deliberately distinct from the rest of biocentral's visual style; see the
/// plugin's design exploration for the rationale.
abstract final class EngineeringStyle {
  static const background = Color(0xFFF6F7F5);
  static const surface = Colors.white;
  static const border = Color(0xFFE4E7E2);
  static const dividerLight = Color(0xFFF0F1EF);
  static const textPrimary = Color(0xFF171A1C);
  static const textSecondary = Color(0xFF5B6460);
  static const textMuted = Color(0xFF8A9490);

  static const accent = Color(0xFF0E7490);
  static const accentSoft = Color(0xFFEEF4F3);
  static const mutationColor = Color(0xFF8E24AA);

  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFDCFCE7);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3E2);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEE2E2);

  static const monoFontFamily = 'JetBrains Mono';

  static const cardDecoration = BoxDecoration(
    color: surface,
    border: Border.fromBorderSide(BorderSide(color: border)),
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );

  static const cartoonStyle = CartoonStyle(
    helixColor: Color(0xFF9E793D),
    sheetColor: Color(0xFF2E7D32),
    outlineColor: Colors.black,
    outlineThickness: 0.12,
    pencilTexture: true,
  );

  /// A pill-shaped status chip in [color], for round/measurement status.
  static Widget chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
