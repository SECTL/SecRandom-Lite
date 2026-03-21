import 'package:flutter/material.dart';

class DeviceSizeHelper {
  static const double _kSmallDeviceMaxWidth = 300;
  static const double _kSmallDeviceMaxHeight = 450;

  static bool isSmallDevice(BoxConstraints constraints) {
    return constraints.maxWidth <= _kSmallDeviceMaxWidth &&
        constraints.maxHeight <= _kSmallDeviceMaxHeight;
  }

  static bool isSmallDeviceFromMedia(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width <= _kSmallDeviceMaxWidth &&
        size.height <= _kSmallDeviceMaxHeight;
  }
}
