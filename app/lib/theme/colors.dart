import 'package:flutter/material.dart';

/// Design tokens matching the SoloDesk prototype styling
class SoloDeskColors {
  // Canvas & Surface
  static const Color background = Color(0xFFF6F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color sidebarNav = Color(0xFF22213B);
  static const Color sidebarHover = Color(0x14FFFFFF); // ~8% white
  static const Color navActive = Color(0xFF6B5DE0);
  static const Color navText = Color(0xFFC9C8DC);
  static const Color navMuted = Color(0xFF8583A6);

  // Ink & Text
  static const Color ink = Color(0xFF202338);
  static const Color muted = Color(0xFF777B91);
  static const Color borderLine = Color(0xFFE8EAF2);

  // Brand Primaries
  static const Color primary = Color(0xFF6657D9);
  static const Color primaryLight = Color(0xFF8174ED);
  static const Color primaryPale = Color(0xFFF0EEFF);
  static const Color primaryDark = Color(0xFF5546C9);

  // Semantic Status Colors
  // Green / Success / Paid / Included
  static const Color green = Color(0xFF16866A);
  static const Color greenBg = Color(0xFFE7F7F0);
  static const Color greenBorder = Color(0xFFCAEDDE);

  // Amber / Warning / Needs Review / Potentially Outside
  static const Color amber = Color(0xFFAC6C16);
  static const Color amberBg = Color(0xFFFFF4DF);
  static const Color amberBorder = Color(0xFFF3DBA9);

  // Red / Danger / Overdue / Offline
  static const Color red = Color(0xFFBF4A5A);
  static const Color redBg = Color(0xFFFFEDF0);
  static const Color redBorder = Color(0xFFFFCCD4);

  // Blue / Info / Lead
  static const Color blue = Color(0xFF366AD9);
  static const Color blueBg = Color(0xFFEAF1FF);
  static const Color blueBorder = Color(0xFFCCDDFE);
}
