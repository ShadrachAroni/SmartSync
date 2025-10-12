import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  static Future<bool> ensureBlePermissions() async {
    if (Platform.isAndroid) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      final advertise = await Permission.bluetoothAdvertise.request();
      final notif = await Permission.notification.request();
      return scan.isGranted &&
          connect.isGranted &&
          advertise.isGranted &&
          notif.isGranted;
    } else if (Platform.isIOS) {
      final bt = await Permission.bluetooth.request();
      return bt.isGranted;
    }
    return true;
  }
}
