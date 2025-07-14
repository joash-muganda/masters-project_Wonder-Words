import 'dart:ui';

import 'package:flutter/material.dart';

Color hexToColor(String hex) {
  assert(RegExp(r'^#([0-9A-Fa-f]{6})|([0-9a-fA-F]{8})$').hasMatch(hex));
  return Color(int.parse(hex.substring(1), radix: 16) +
      (hex.length == 7 ? 0xFF000000 : 0x0000000));
}

class ColorTheme {
  static Color primaryColor = hexToColor("#628F5F");
  static Color secondaryColor = hexToColor("#999EB6");
  static Color accentBlueColor = hexToColor("#A8B9CD");
  static Color accentYellowColor = hexToColor("#FFF06E");
  static Color backgroundColor = hexToColor("#FEFAEB");
  static Color textColor = hexToColor("#000000");
  static Color pink = hexToColor("#EDCACB");
  static Color orange = hexToColor("#E9C466");
  static Color yellow = hexToColor("#FFF06E");
  static Color green = hexToColor("#9AC997");
  static Color darkPurple = hexToColor("#727999");
}
