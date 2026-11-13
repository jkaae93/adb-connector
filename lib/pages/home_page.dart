import 'dart:async';

import 'package:adb_connector/models/logcat_options.dart';
import 'package:adb_connector/models/saved_device.dart';
import 'package:adb_connector/pages/file_browser_page.dart';
import 'package:adb_connector/pages/developer_tools_page.dart';
import 'package:adb_connector/models/log_window_arguments.dart';
import 'package:adb_connector/pages/settings_page.dart';
import 'package:adb_connector/services/adb_service.dart';
import 'package:adb_connector/services/device_storage.dart';
import 'package:adb_connector/services/ios_service.dart';
import 'package:adb_connector/services/release_check_service.dart';
import 'package:adb_connector/services/terminal_service.dart';
import 'package:adb_connector/theme/vaulta.dart';
import 'package:adb_connector/widgets/add_device_dialog.dart';
import 'package:adb_connector/widgets/copy_ios_install_command_button.dart';
import 'package:adb_connector/widgets/ios_install_dialog.dart';
import 'package:adb_connector/widgets/logcat_options_dialog.dart';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AdbService _adbService = AdbService();
  final IosService _iosService = IosService.instance;
  final DeviceStorage _storage = DeviceStorage();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '5555',
  );

  List<SavedDevice> _savedDevices = [];
  List<ConnectedDevice> _connectedDevices = [];
  Set<String> _iosUsbUdids = {};
  Set<String> _iosWifiUdids = {};

  final Set<String> _connectingDeviceIds = {};
  bool _isRefreshing = false;
  bool _refreshAgain = false;
  String _query = '';
  String _filter = '전체';
  String? _selectedId;
  Timer? _refreshTimer;

  bool _adbAvailable = false;
  bool _iosAvailable = false;
  bool _isInstallingAdb = false;
  String _installMessage = '';
  double? _installProgress;

  @override
  void initState() {
    super.initState();
    _adbAvailable = _adbService.isAdbAvailable();
    _iosAvailable = _iosService.isAvailable();
    _initialize();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshConnectedDevices(),
    );
  }

  Future<void> _initialize() async {
    await _adbService.loadConfiguredPath();
    if (mounted) setState(() => _adbAvailable = _adbService.isAdbAvailable());
    await _loadSavedDevices();
    await _refreshConnectedDevices();
  }

  Future<void> _installAdb() async {
    setState(() {
      _isInstallingAdb = true;
      _installMessage = '설치 준비 중...';
      _installProgress = null;
    });

    final success = await _adbService.installAdb(
      onProgress: (message, progress) {
        if (mounted) {
          setState(() {
            _installMessage = message;
            _installProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isInstallingAdb = false;
        _adbAvailable = success;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ADB 설치 완료'),
            backgroundColor: Vaulta.success,
          ),
        );
        await _refreshConnectedDevices();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ADB 설치 실패: $_installMessage'),
            backgroundColor: Vaulta.danger,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDevices() async {
    final devices = await _storage.loadDevices();
    setState(() => _savedDevices = devices);
  }

  Future<void> _refreshConnectedDevices() async {
    if (_isRefreshing) {
      _refreshAgain = true;
      return;
    }
    _isRefreshing = true;

    try {
      // Android
      if (_adbAvailable) {
        final devices = await _adbService.getConnectedDevices();
        if (mounted) {
          setState(() => _connectedDevices = devices);
          await _autoSaveConnectedDevices(devices);
        }
      }

      // iOS
      if (_iosAvailable) {
        final iosDevices = await _iosService.getConnectedDevices();
        if (mounted) {
          setState(() {
            _iosUsbUdids = iosDevices
                .where((d) => !d.isWifi)
                .map((d) => d.udid)
                .toSet();
            _iosWifiUdids = iosDevices
                .where((d) => d.isWifi)
                .map((d) => d.udid)
                .toSet();
          });
          await _autoSaveIosDevices(iosDevices);
        }
      }
    } catch (_) {
      // 실행 실패 무시
    } finally {
      _isRefreshing = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        unawaited(_refreshConnectedDevices());
      }
    }
  }

  Future<void> _autoSaveConnectedDevices(
    List<ConnectedDevice> connected,
  ) async {
    var changed = false;

    for (final device in connected) {
      if (device.state != 'device') continue;

      if (device.isIpConnection) {
        final ip = device.ip!;
        final port = device.port ?? 5555;
        final alreadySaved = _savedDevices.any(
          (d) =>
              d.platform == DevicePlatform.android &&
              d.ip == ip &&
              d.port == port,
        );
        if (alreadySaved) continue;

        final model = device.modelName ?? '';
        final newDevice = SavedDevice(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          nickname: model.isNotEmpty ? model : ip,
          ip: ip,
          port: port,
          serialName: null,
          modelName: model.isNotEmpty ? model : null,
        );
        await _storage.addDevice(newDevice);
        changed = true;
      } else {
        final serial = device.hardwareSerial?.isNotEmpty == true
            ? device.hardwareSerial!
            : device.identifier;
        final alreadySaved = _savedDevices.any(
          (d) => d.platform == DevicePlatform.android && d.serialName == serial,
        );
        if (alreadySaved) continue;

        final ip = await _adbService.getDeviceIp(device.identifier);
        if (ip == null) continue;

        final ipAlreadySaved = _savedDevices.any(
          (d) => d.platform == DevicePlatform.android && d.ip == ip,
        );
        if (ipAlreadySaved) continue;

        final model =
            device.modelName ??
            await _adbService.getDeviceModel(device.identifier);
        final serialNo = await _adbService.getDeviceSerial(device.identifier);

        final newDevice = SavedDevice(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          nickname: model.isNotEmpty ? model : serial,
          ip: ip,
          serialName: serialNo.isNotEmpty ? serialNo : serial,
          modelName: model.isNotEmpty ? model : null,
        );
        await _storage.addDevice(newDevice);
        changed = true;
      }
    }

    if (changed) await _loadSavedDevices();
  }

  Future<void> _autoSaveIosDevices(List<IosConnectedDevice> devices) async {
    var changed = false;

    for (final device in devices) {
      final alreadySaved = _savedDevices.any(
        (d) => d.platform == DevicePlatform.ios && d.serialName == device.udid,
      );
      if (alreadySaved) continue;

      final name = device.name ?? device.udid.substring(0, 8);
      final newDevice = SavedDevice(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nickname: name,
        ip: '',
        port: 0,
        serialName: device.udid,
        modelName: device.modelName,
        platform: DevicePlatform.ios,
      );
      await _storage.addDevice(newDevice);
      changed = true;
    }

    if (changed) await _loadSavedDevices();
  }

  bool _isDeviceConnected(SavedDevice device) {
    return _isDeviceConnectedViaUsb(device) ||
        _isDeviceConnectedViaWifi(device);
  }

  bool _isDeviceConnectedViaUsb(SavedDevice device) {
    if (device.isIos) {
      return device.serialName != null &&
          _iosUsbUdids.contains(device.serialName);
    }
    if (device.serialName == null) return false;
    return _connectedDevices.any(
      (c) =>
          c.state == 'device' &&
          !c.isNetworkConnection &&
          c.identifier == device.serialName,
    );
  }

  bool _isDeviceConnectedViaWifi(SavedDevice device) {
    if (device.isIos) {
      return device.serialName != null &&
          _iosWifiUdids.contains(device.serialName);
    }
    return _connectedDevices.any(
      (c) =>
          c.state == 'device' &&
          ((c.isIpConnection && c.ip == device.ip && c.port == device.port) ||
              (c.isMdnsConnection &&
                  c.hardwareSerial != null &&
                  c.hardwareSerial == device.serialName)),
    );
  }

  Future<void> _connectDevice(SavedDevice device) async {
    setState(() => _connectingDeviceIds.add(device.id));

    try {
      final result = await _adbService.connectWithRetry(
        ip: device.ip,
        port: device.port,
        serialName: device.serialName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Vaulta.success : Vaulta.danger,
          ),
        );
        await _refreshConnectedDevices();
      }
    } finally {
      if (mounted) setState(() => _connectingDeviceIds.remove(device.id));
    }
  }

  Future<void> _switchToWireless(SavedDevice device) async {
    if (device.serialName == null || device.serialName!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('시리얼 정보가 없어 전환할 수 없습니다')));
      return;
    }

    setState(() => _connectingDeviceIds.add(device.id));

    try {
      final result = await _adbService.switchToWireless(
        serial: device.serialName!,
        ip: device.ip,
        port: device.port,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Vaulta.success : Vaulta.danger,
          ),
        );
        await _refreshConnectedDevices();
      }
    } finally {
      if (mounted) setState(() => _connectingDeviceIds.remove(device.id));
    }
  }

  Future<void> _disconnectDevice(SavedDevice device) async {
    final mdns = _connectedDevices
        .where(
          (c) =>
              c.state == 'device' &&
              c.isMdnsConnection &&
              c.hardwareSerial == device.serialName,
        )
        .firstOrNull;
    final result = mdns == null
        ? await _adbService.disconnect(device.ip, device.port)
        : await _adbService
              .command(['disconnect', mdns.identifier])
              .then(
                (r) => r.exitCode == 0
                    ? ConnectResult.ok(r.stdout.toString())
                    : ConnectResult.failure(r.stderr.toString()),
              );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      await _refreshConnectedDevices();
    }
  }

  Future<void> _quickConnect() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    final port = int.tryParse(_portController.text.trim()) ?? 5555;

    final result = await _adbService.connectWithRetry(ip: ip, port: port);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Vaulta.success : Vaulta.danger,
        ),
      );
      if (result.success) {
        _ipController.clear();
        await _refreshConnectedDevices();
      }
    }
  }

  Future<void> _addOrEditDevice({SavedDevice? device}) async {
    final result = await showDialog<SavedDevice>(
      context: context,
      builder: (context) => AddDeviceDialog(device: device),
    );

    if (result == null) return;

    if (device != null) {
      await _storage.updateDevice(result);
    } else {
      await _storage.addDevice(result);
    }
    await _loadSavedDevices();
  }

  // Android logcat 또는 iOS syslog 앱 내 뷰어 열기
  Future<void> _openLogcat(SavedDevice device) async {
    String identifier;
    if (device.isIos) {
      final udid = device.serialName;
      if (udid == null) return;
      identifier = udid;
    } else {
      final connected = _connectedDevices.firstWhere((c) {
        if (c.state != 'device') return false;
        if (c.isIpConnection) return c.ip == device.ip && c.port == device.port;
        return c.identifier == device.serialName ||
            (c.isMdnsConnection && c.hardwareSerial == device.serialName);
      }, orElse: () => ConnectedDevice(identifier: '', state: ''));
      if (connected.identifier.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('연결된 기기가 아닙니다')));
        return;
      }
      identifier = connected.identifier;
    }
    try {
      await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: false,
          arguments: LogWindowArguments(
            deviceName: device.nickname,
            identifier: identifier,
            isIos: device.isIos,
            adbPath: device.isIos ? null : _adbService.adbPath,
          ).encode(),
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('로그 창을 열 수 없습니다: $error')));
    }
  }

  // 터미널에서 logcat / syslog 열기
  Future<void> _openTerminalLogcat(
    SavedDevice device,
    LogcatPreset preset,
  ) async {
    final ts = TerminalService.instance;
    final installed = ts.installedApps();

    if (installed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('지원하는 터미널 앱을 찾을 수 없습니다')));
      return;
    }

    // iOS syslog
    if (device.isIos) {
      final udid = device.serialName;
      if (udid == null) return;

      final savedId = await ts.loadSelectedId();
      TerminalApp? selected = savedId != null ? ts.appById(savedId) : null;
      final isInstalled =
          selected != null && installed.any((a) => a.id == selected!.id);
      if (!isInstalled) {
        if (!mounted) return;
        selected = await _showTerminalPickerDialog(installed);
        if (selected == null) return;
        await ts.saveSelectedId(selected.id);
      }

      final command = _iosService.buildSyslogCommand(udid);
      await ts.runCommand(selected, command);

      if (!mounted) return;
      if (ts.consumeClipboardCopied()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selected.name}은 직접 명령 실행을 지원하지 않아 클립보드에 복사했습니다.'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Android logcat
    final connected = _connectedDevices.firstWhere((c) {
      if (c.state != 'device') return false;
      if (c.isIpConnection) return c.ip == device.ip && c.port == device.port;
      return c.identifier == device.serialName ||
          (c.isMdnsConnection && c.hardwareSerial == device.serialName);
    }, orElse: () => ConnectedDevice(identifier: '', state: ''));

    if (connected.identifier.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결된 기기가 아닙니다')));
      return;
    }

    LogcatOptions options;
    TerminalApp? selected;

    if (preset == LogcatPreset.custom) {
      final savedId = await ts.loadSelectedId();
      final initialId = savedId != null && installed.any((a) => a.id == savedId)
          ? savedId
          : null;

      if (!mounted) return;
      final result = await showDialog<LogcatRunConfig>(
        context: context,
        builder: (_) => LogcatOptionsDialog(initialTerminalId: initialId),
      );
      if (result == null) return;
      options = result.options;
      selected = ts.appById(result.terminalId);
      if (selected != null) await ts.saveSelectedId(selected.id);
    } else {
      options = preset == LogcatPreset.flutter
          ? const LogcatOptions(tags: ['flutter'])
          : const LogcatOptions();

      final savedId = await ts.loadSelectedId();
      selected = savedId != null ? ts.appById(savedId) : null;

      final isInstalled =
          selected != null && installed.any((a) => a.id == selected!.id);
      if (!isInstalled) {
        if (!mounted) return;
        selected = await _showTerminalPickerDialog(installed);
        if (selected == null) return;
        await ts.saveSelectedId(selected.id);
      }
    }

    if (selected == null) return;

    final logcatArgs = [
      '-s',
      connected.identifier,
      'logcat',
      ...options.toArgs(),
    ];
    final command = '${_adbService.adbPath} ${logcatArgs.join(' ')}';
    await ts.runCommand(selected, command);

    if (!mounted) return;
    if (ts.consumeClipboardCopied()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selected.name}은 직접 명령 실행을 지원하지 않아 클립보드에 복사했습니다.'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<TerminalApp?> _showTerminalPickerDialog(List<TerminalApp> apps) {
    return showDialog<TerminalApp>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('터미널 앱 선택'),
        children: [
          for (final app in apps)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(app),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.terminal, size: 20),
                    const SizedBox(width: 12),
                    Text(app.name, style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소', style: TextStyle(color: Vaulta.textMuted)),
          ),
        ],
      ),
    );
  }

  void _openFileBrowser(SavedDevice device) {
    final connected = _connectedDevices.firstWhere((c) {
      if (c.state != 'device') return false;
      if (c.isIpConnection) return c.ip == device.ip && c.port == device.port;
      return c.identifier == device.serialName ||
          (c.isMdnsConnection && c.hardwareSerial == device.serialName);
    }, orElse: () => ConnectedDevice(identifier: '', state: ''));

    if (connected.identifier.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결된 기기가 아닙니다')));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FileBrowserPage(
          identifier: connected.identifier,
          deviceName: device.nickname,
        ),
      ),
    );
  }

  Future<void> _deleteDevice(SavedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기기 삭제'),
        content: Text("'${device.nickname}'을(를) 삭제하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Vaulta.danger),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deleteDevice(device.id);
      await _loadSavedDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectedCount = _savedDevices
        .where((d) => _isDeviceConnected(d))
        .length;
    final disconnectedCount = _savedDevices.length - connectedCount;

    final devices = _savedDevices.where((d) {
      final match = '${d.nickname} ${d.ip} ${d.modelName ?? ''}'
          .toLowerCase()
          .contains(_query.toLowerCase());
      return match &&
          switch (_filter) {
            'Android' => !d.isIos,
            'iOS' => d.isIos,
            '연결됨' => _isDeviceConnected(d),
            _ => true,
          };
    }).toList();
    final selected =
        devices.where((d) => d.id == _selectedId).firstOrNull ??
        devices.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: Vaulta.heroGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('ADB Connector'),
          ],
        ),
        actions: [
          if (disconnectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(
                  Icons.link_off,
                  size: 16,
                  color: Vaulta.danger,
                ),
                label: Text(
                  '미연결 $disconnectedCount',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Vaulta.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor: Vaulta.danger.withValues(alpha: 0.14),
                side: BorderSide.none,
              ),
            ),
          if (connectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.link, size: 16, color: Vaulta.success),
                label: Text(
                  '연결 $connectedCount',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Vaulta.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor: Vaulta.success.withValues(alpha: 0.14),
                side: BorderSide.none,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
              if (mounted)
                setState(() => _adbAvailable = _adbService.isAdbAvailable());
              await _refreshConnectedDevices();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _refreshConnectedDevices,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '기기 추가',
            onPressed: () => _addOrEditDevice(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: ReleaseCheckService.instance.notice,
            builder: (context, release, _) => release == null
                ? const SizedBox.shrink()
                : MaterialBanner(
                    content: Text('새 버전 $release을 사용할 수 있습니다'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsPage(),
                          ),
                        ),
                        child: const Text('확인'),
                      ),
                    ],
                  ),
          ),
          if (!_adbAvailable) _buildAdbInstallBanner(),
          if (!_iosAvailable) _buildIosBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final list = Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      decoration: BoxDecoration(
                        gradient: Vaulta.heroGradient,
                        borderRadius: BorderRadius.circular(Vaulta.radiusHero),
                        boxShadow: [
                          BoxShadow(
                            color: Vaulta.accent.withValues(alpha: 0.35),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          gradient: Vaulta.heroGlow,
                          borderRadius: BorderRadius.circular(
                            Vaulta.radiusHero,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '내 기기',
                                    style: TextStyle(
                                      color: Vaulta.heroLabel,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    connectedCount > 0
                                        ? '$connectedCount대 연결됨'
                                        : '기기를 연결하세요',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            _heroStat('$connectedCount', '연결됨'),
                            _heroDivider(),
                            _heroStat('$disconnectedCount', '미연결'),
                            _heroDivider(),
                            _heroStat('${_savedDevices.length}', '저장됨'),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '기기 검색',
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children:
                            [
                                  ('전체', _savedDevices.length),
                                  (
                                    'Android',
                                    _savedDevices.where((d) => !d.isIos).length,
                                  ),
                                  (
                                    'iOS',
                                    _savedDevices.where((d) => d.isIos).length,
                                  ),
                                  ('연결됨', connectedCount),
                                ]
                                .map(
                                  (filter) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text('${filter.$1} ${filter.$2}'),
                                      selected: filter.$1 == _filter,
                                      onSelected: (_) =>
                                          setState(() => _filter = filter.$1),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    Expanded(
                      child: devices.isEmpty
                          ? _buildEmptyDevices()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              itemCount: devices.length,
                              itemBuilder: (context, index) {
                                final device = devices[index];
                                final connected = _isDeviceConnected(device);
                                final usbOnly =
                                    _isDeviceConnectedViaUsb(device) &&
                                    !_isDeviceConnectedViaWifi(device);
                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: connected
                                          ? Vaulta.actionCircle
                                          : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                      child: Icon(
                                        device.isIos
                                            ? Icons.phone_iphone_rounded
                                            : Icons.phone_android_rounded,
                                        color: connected
                                            ? Colors.white
                                            : Vaulta.textMuted,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            device.nickname,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (connected && !usbOnly)
                                          VaultaStatusPill.connected()
                                        else if (connected)
                                          VaultaStatusPill.usb()
                                        else
                                          VaultaStatusPill.disconnected(),
                                      ],
                                    ),
                                    subtitle: Text(
                                      connected
                                          ? '${device.isIos ? 'iOS' : device.ip} · ${device.modelName ?? ''}'
                                                .trim()
                                          : (device.isIos
                                                ? '연결되지 않음'
                                                : '연결되지 않음 · ${device.ip}'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!device.isIos)
                                          _inlineConnectButton(device),
                                        Icon(
                                          wide && selected?.id == device.id
                                              ? Icons.chevron_right
                                              : Icons.arrow_forward_ios,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      setState(() => _selectedId = device.id);
                                      if (!wide)
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => Scaffold(
                                              appBar: AppBar(
                                                title: Text(device.nickname),
                                              ),
                                              body: _deviceDetails(device),
                                            ),
                                          ),
                                        );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
                if (!wide) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: list),
                    Expanded(
                      flex: 4,
                      child: selected == null
                          ? _buildNoSelection()
                          : _deviceDetails(selected),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildQuickConnectSection(),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(color: Vaulta.heroLabel, fontSize: 12),
      ),
    ],
  );

  Widget _heroDivider() => Container(
    width: 1,
    height: 40,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: Colors.white.withValues(alpha: 0.25),
  );

  Widget _inlineConnectButton(SavedDevice device) {
    if (_connectingDeviceIds.contains(device.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_isDeviceConnectedViaWifi(device)) {
      return TextButton(
        onPressed: () => _disconnectDevice(device),
        child: const Text('해제'),
      );
    }
    final viaUsb = _isDeviceConnectedViaUsb(device);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 34),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFamily: Vaulta.fontFamily,
          ),
        ),
        onPressed: () =>
            viaUsb ? _switchToWireless(device) : _connectDevice(device),
        child: Text(viaUsb ? 'Wi-Fi 전환' : '연결'),
      ),
    );
  }

  Widget _buildEmptyDevices() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? Vaulta.textMuted : Vaulta.lightTextSecondary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Vaulta.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.phone_android,
              size: 32,
              color: Vaulta.accent,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '표시할 기기가 없습니다',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            '새 기기를 추가하거나 연결하면 여기에 표시됩니다',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _addOrEditDevice(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('기기 추가'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelection() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 40,
            color: dark ? Vaulta.textMuted : Vaulta.lightTextSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            '기기를 선택하세요',
            style: TextStyle(
              color: dark ? Vaulta.textMuted : Vaulta.lightTextSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(
    IconData icon,
    String label,
    bool enabled,
    VoidCallback onTap,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final disabledColor = dark ? Vaulta.textMuted : Vaulta.lightTextSecondary;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: enabled
                    ? Vaulta.actionCircle
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: enabled ? Colors.white : disabledColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled ? null : disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceDetails(SavedDevice device) {
    final connected = _isDeviceConnected(device);
    final transport = _connectedDevices
        .where(
          (c) =>
              c.state == 'device' &&
              (c.identifier == device.serialName ||
                  (c.isMdnsConnection &&
                      c.hardwareSerial == device.serialName) ||
                  (c.isIpConnection &&
                      c.ip == device.ip &&
                      c.port == device.port)),
        )
        .firstOrNull;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? Vaulta.textMuted : Vaulta.lightTextSecondary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: connected
                        ? Vaulta.actionCircle
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      device.isIos ? Icons.phone_iphone : Icons.phone_android,
                      size: 28,
                      color: connected ? Colors.white : Vaulta.textMuted,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                device.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Vaulta.accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                device.isIos ? 'iOS' : 'Android',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Vaulta.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (connected)
                          VaultaStatusPill.connected()
                        else
                          VaultaStatusPill.disconnected(),
                        const SizedBox(height: 8),
                        Text(
                          device.isIos
                              ? (device.serialName ?? '')
                              : '${device.ip}:${device.port}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!device.isIos) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _connectingDeviceIds.contains(device.id)
                  ? null
                  : () => _isDeviceConnectedViaWifi(device)
                        ? _disconnectDevice(device)
                        : _isDeviceConnectedViaUsb(device)
                        ? _switchToWireless(device)
                        : _connectDevice(device),
              icon: Icon(
                _isDeviceConnectedViaWifi(device) ? Icons.link_off : Icons.wifi,
              ),
              label: Text(
                _isDeviceConnectedViaWifi(device)
                    ? '연결 해제'
                    : _isDeviceConnectedViaUsb(device)
                    ? 'Wi-Fi로 전환'
                    : '연결',
              ),
            ),
          ],
          const SizedBox(height: 20),
          const VaultaSectionTitle('빠른 실행'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _quickAction(
                    Icons.description_outlined,
                    device.isIos ? 'Syslog' : 'Logcat',
                    connected,
                    () => _openLogcat(device),
                  ),
                  if (!device.isIos)
                    _quickAction(
                      Icons.folder_open_outlined,
                      '파일',
                      connected,
                      () => _openFileBrowser(device),
                    ),
                  if (!device.isIos)
                    _quickAction(
                      Icons.build_outlined,
                      '개발 도구',
                      transport != null,
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              DeveloperToolsPage(serial: transport!.identifier),
                        ),
                      ),
                    ),
                  _quickAction(
                    Icons.terminal,
                    '터미널',
                    connected,
                    () => _openTerminalLogcat(device, LogcatPreset.all),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const VaultaSectionTitle('관리'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addOrEditDevice(device: device),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('수정'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _deleteDevice(device),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Vaulta.danger,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('삭제'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIosBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Vaulta.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Vaulta.radiusCard),
        border: Border.all(color: Vaulta.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const VaultaListIcon(Icons.phone_iphone),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'iPhone/iPad 지원을 위해 libimobiledevice를 설치하세요',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton.tonal(
            onPressed: () async {
              final installed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const IosInstallDialog(),
              );
              if (!mounted || installed != true) return;
              setState(() => _iosAvailable = _iosService.isAvailable());
              await _refreshConnectedDevices();
            },
            child: const Text('설치'),
          ),
          const CopyIosInstallCommandButton(),
        ],
      ),
    );
  }

  Widget _buildAdbInstallBanner() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Vaulta.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Vaulta.radiusCard),
        border: Border.all(color: Vaulta.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Vaulta.warning.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isInstallingAdb ? Icons.downloading : Icons.warning_amber,
              color: Vaulta.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isInstallingAdb ? 'ADB 설치 중' : 'ADB가 설치되지 않았습니다',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _isInstallingAdb
                      ? _installMessage
                      : '자동으로 설치하려면 "설치" 버튼을 눌러주세요',
                  style: TextStyle(
                    fontSize: 12,
                    color: dark
                        ? Vaulta.textSecondary
                        : Vaulta.lightTextSecondary,
                  ),
                ),
                if (_isInstallingAdb) ...[
                  const SizedBox(height: 10),
                  if (_installProgress != null)
                    VaultaProgressBar(value: _installProgress!)
                  else
                    const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!_isInstallingAdb)
            FilledButton.icon(
              onPressed: _installAdb,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('설치'),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickConnectSection() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? Vaulta.surface : Vaulta.lightSurface,
        border: Border(
          top: BorderSide(color: dark ? Vaulta.stroke : Vaulta.lightStroke),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Vaulta.actionCircle,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            '빠른 연결',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                hintText: 'IP 주소 (예: 192.168.0.100)',
                isDense: true,
              ),
              onSubmitted: (_) => _quickConnect(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 88,
            child: TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: '포트', isDense: true),
              onSubmitted: (_) => _quickConnect(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _quickConnect, child: const Text('연결')),
        ],
      ),
    );
  }
}
