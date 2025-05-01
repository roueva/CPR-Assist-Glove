import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CustomIcons {
  static late BitmapDescriptor aedUpdated;
  static late BitmapDescriptor aedCached;

  static Future<void> loadIcons() async {
    aedUpdated = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(27.76, 37)),
      'assets/icons/AEDs.png',
    );
    aedCached = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(27.76, 37)),
      'assets/icons/AEDs_c.png',
    );
  }
}
