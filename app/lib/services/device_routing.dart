import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Valhalla on the device (valhalla-mobile), through MainActivity's channel.
/// Android only for now: on iOS the library has to be built from source
/// (xcframework), so iOS keeps online routing.
abstract final class DeviceRouting {
  static const _channel = MethodChannel('org.roadto/valhalla');

  static bool get supported => Platform.isAndroid;

  /// Region file kinds to install so routing can run on the device.
  static const kinds = {'routing', 'routing_config'};

  /// Runs a Valhalla /route request (JSON) with the given config file and
  /// returns Valhalla's JSON answer.
  static Future<String> route(String configPath, String requestJson) => _run('route', configPath, requestJson);

  /// Same for /trace_attributes (speed limits along a route).
  static Future<String> traceAttributes(String configPath, String requestJson) =>
      _run('traceAttributes', configPath, requestJson);

  static Future<String> _run(String method, String configPath, String requestJson) async {
    final response = await _channel.invokeMethod<String>(method, {'config': configPath, 'request': requestJson});
    if (response == null) throw PlatformException(code: 'empty', message: 'no answer from Valhalla');
    return response;
  }
}
