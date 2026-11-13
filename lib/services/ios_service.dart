import 'dart:async';
import 'dart:io';

class IosConnectedDevice {
  IosConnectedDevice({
    required this.udid,
    this.name,
    this.modelName,
    this.isWifi = false,
  });

  final String udid;
  final String? name;
  final String? modelName;
  final bool isWifi;
}

class IosService {
  IosService._();

  static final IosService instance = IosService._();

  static const _timeout = Duration(seconds: 5);

  List<String> get _toolPaths => {
    '/opt/homebrew/bin',
    '/usr/local/bin',
    ...?Platform.environment['PATH']?.split(':'),
    '/usr/bin',
  }.where((path) => path.isNotEmpty).toList();

  String? _resolveToolPath(String tool) {
    for (final dir in _toolPaths) {
      final file = File('$dir/$tool');
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  String? get _ideviceIdPath => _resolveToolPath('idevice_id');
  String? get _ideviceSyslogPath => _resolveToolPath('idevicesyslog');
  String? get homebrewPath => _resolveToolPath('brew');

  bool isAvailable() =>
      _ideviceIdPath != null &&
      _resolveToolPath('ideviceinfo') != null &&
      _ideviceSyslogPath != null;

  Future<Process> installWithHomebrew() async {
    final brew = homebrewPath;
    if (brew == null) {
      throw const FileSystemException(
        'Homebrew를 찾을 수 없습니다. Homebrew를 설치하거나 터미널에서 설치 명령을 실행해 주세요.',
      );
    }
    final brewDir = File(brew).parent.path;
    final existingPath = Platform.environment['PATH'] ?? '';
    return Process.start(
      brew,
      ['install', 'libimobiledevice'],
      environment: {
        'PATH':
            '$brewDir:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$existingPath',
        'NONINTERACTIVE': '1',
        'HOMEBREW_NO_AUTO_UPDATE': '1',
        'HOMEBREW_NO_INSTALL_CLEANUP': '1',
        'HOMEBREW_NO_COLOR': '1',
        'TERM': 'dumb',
      },
    );
  }

  Future<ProcessResult> _run(String tool, List<String> args) async {
    final path = _resolveToolPath(tool);
    if (path == null) return ProcessResult(0, 1, '', '$tool not found');
    try {
      return await Process.run(path, args).timeout(_timeout);
    } on TimeoutException {
      return ProcessResult(0, 1, '', 'timed out');
    }
  }

  Future<List<IosConnectedDevice>> getConnectedDevices() async {
    final usbResult = await _run('idevice_id', ['-l']);
    final wifiResult = await _run('idevice_id', ['-n']);

    final usbUdids = _parseUdidList(usbResult.stdout as String);
    final wifiUdids = _parseUdidList(wifiResult.stdout as String);

    // 합집합, WiFi 여부 표시
    final allUdids = <String>{...usbUdids, ...wifiUdids};
    final devices = <IosConnectedDevice>[];

    for (final udid in allUdids) {
      final isWifi = wifiUdids.contains(udid) && !usbUdids.contains(udid);
      final name = await getDeviceName(udid);
      final model = await getDeviceModel(udid);
      devices.add(
        IosConnectedDevice(
          udid: udid,
          name: name.isEmpty ? null : name,
          modelName: model.isEmpty ? null : model,
          isWifi: isWifi,
        ),
      );
    }

    return devices;
  }

  List<String> _parseUdidList(String output) {
    return output
        .split('\n')
        .map((l) => l.trim())
        .where(
          (l) => RegExp(
            r'^(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})$',
          ).hasMatch(l),
        )
        .toList();
  }

  Future<String> getDeviceName(String udid) async {
    final r = await _run('ideviceinfo', ['-u', udid, '-k', 'DeviceName']);
    return (r.stdout as String).trim();
  }

  Future<String> getDeviceModel(String udid) async {
    final r = await _run('ideviceinfo', ['-u', udid, '-k', 'ProductType']);
    return (r.stdout as String).trim();
  }

  Future<Process> startSyslog(String udid) async {
    final path = _ideviceSyslogPath ?? 'idevicesyslog';
    return Process.start(path, ['-u', udid]);
  }

  String buildSyslogCommand(String udid) {
    final path = _ideviceSyslogPath ?? 'idevicesyslog';
    return '$path -u $udid';
  }
}
