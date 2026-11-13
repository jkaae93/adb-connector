import 'dart:convert';

class LogWindowArguments {
  const LogWindowArguments({
    required this.deviceName,
    required this.identifier,
    required this.isIos,
    this.adbPath,
  });

  final String deviceName;
  final String identifier;
  final bool isIos;
  final String? adbPath;

  String encode() => jsonEncode({
    'type': 'device-log',
    'deviceName': deviceName,
    'identifier': identifier,
    'isIos': isIos,
    'adbPath': adbPath,
  });

  static LogWindowArguments? parse(String input) {
    try {
      final data = jsonDecode(input);
      if (data is! Map<String, dynamic> ||
          data['type'] != 'device-log' ||
          data['deviceName'] is! String ||
          data['identifier'] is! String ||
          (data['identifier'] as String).isEmpty ||
          data['isIos'] is! bool)
        return null;
      if (data['isIos'] == false &&
          (data['adbPath'] is! String || (data['adbPath'] as String).isEmpty))
        return null;
      return LogWindowArguments(
        deviceName: data['deviceName'] as String,
        identifier: data['identifier'] as String,
        isIos: data['isIos'] as bool,
        adbPath: data['adbPath'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
