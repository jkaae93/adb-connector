import 'dart:convert';
import 'dart:io';
import 'package:adb_connector/main.dart';
import 'package:adb_connector/pages/qr_pairing_page.dart';
import 'package:adb_connector/services/adb_service.dart';
import 'package:adb_connector/services/mcp_service.dart';
import 'package:adb_connector/theme/vaulta.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final adb = AdbService();
  String version = '확인 중...';
  String? releaseInfo;
  Map<String, dynamic>? release;
  bool busy = false;
  double? downloadProgress;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final result = await adb.command(['version']);
    if (mounted)
      setState(
        () => version = result.exitCode == 0
            ? result.stdout.toString().trim()
            : result.stderr.toString(),
      );
  }

  void _message(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseAdb() async {
    final selected = await FilePicker.pickFiles(dialogTitle: 'ADB 실행 파일 선택');
    final path = selected?.files.single.path;
    if (path == null) return;
    final ok = await adb.setAdbPath(path);
    if (!ok) {
      _message('올바른 ADB 실행 파일이 아닙니다');
      return;
    }
    await _loadVersion();
    _message('ADB 경로가 변경되었습니다');
  }

  Future<void> _showCommand(String title, List<String> args) async {
    final result = await adb.command(args);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText('${result.stdout}${result.stderr}'.trim()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _discover() async {
    final response = await adb.command(['mdns', 'services']);
    if (!mounted) return;
    if (response.exitCode != 0) {
      _message(response.stderr.toString());
      return;
    }
    final entries = response.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where(
          (parts) => parts.length >= 3 && parts[1].contains('_adb-tls-connect'),
        )
        .toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('무선 디버깅 기기'),
        content: SizedBox(
          width: 450,
          child: entries.isEmpty
              ? const Text('검색된 연결 서비스가 없습니다. 기기에서 무선 디버깅을 켜고 같은 네트워크에 연결하세요.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: entries
                      .map(
                        (parts) => ListTile(
                          title: Text(parts[0]),
                          subtitle: Text(parts.last),
                          trailing: const Icon(Icons.link),
                          onTap: () async {
                            Navigator.pop(context);
                            final address = parts.last;
                            final result = await adb.command([
                              'connect',
                              address,
                            ]);
                            _message('${result.stdout}${result.stderr}'.trim());
                          },
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _restartServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ADB 서버 재시작'),
        content: const Text('다른 프로그램의 ADB 연결도 일시적으로 끊어집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('재시작'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final stop = await adb.command(['kill-server']);
    if (stop.exitCode != 0) {
      _message(stop.stderr.toString());
      return;
    }
    final start = await adb.command(['start-server']);
    _message(
      start.exitCode == 0 ? 'ADB 서버가 재시작되었습니다' : start.stderr.toString(),
    );
  }

  Future<void> _pair() async {
    final host = TextEditingController();
    final port = TextEditingController();
    final code = TextEditingController();
    final fields = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('무선 디버깅 페어링'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('기기의 무선 디버깅에서 페어링 코드로 기기 페어링을 선택하세요.'),
              const SizedBox(height: 12),
              TextField(
                controller: host,
                decoration: const InputDecoration(labelText: 'IP 주소'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '페어링 포트'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: const InputDecoration(labelText: '페어링 코드'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, [
              host.text.trim(),
              port.text.trim(),
              code.text.trim(),
            ]),
            child: const Text('페어링'),
          ),
        ],
      ),
    );
    if (fields == null) return;
    final number = int.tryParse(fields[1]);
    if (fields[0].isEmpty ||
        number == null ||
        number < 1 ||
        number > 65535 ||
        !RegExp(r'^\d{6}$').hasMatch(fields[2])) {
      _message('주소, 포트, 6자리 코드를 확인하세요');
      return;
    }
    final result = await adb.pair(fields[0], number, fields[2]);
    _message(result.message);
  }

  Future<void> _checkRelease() async {
    setState(() {
      busy = true;
      releaseInfo = null;
    });
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/jkaae93/adb-connector/releases/latest',
        ),
      );
      request.headers.set('User-Agent', 'ADB-Connector');
      final response = await request.close();
      if (response.statusCode != 200)
        throw HttpException('GitHub HTTP ${response.statusCode}');
      final data =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final plist =
          '${File(Platform.resolvedExecutable).parent.parent.path}/Info.plist';
      final local = await Process.run('/usr/libexec/PlistBuddy', [
        '-c',
        'Print :CFBundleShortVersionString',
        plist,
      ]);
      final localVersion = local.exitCode == 0
          ? local.stdout.toString().trim()
          : '알 수 없음';
      if (mounted)
        setState(() {
          release = data;
          releaseInfo =
              '현재 $localVersion · 최신 ${data['tag_name']}\n${data['body'] ?? ''}';
        });
    } catch (e) {
      if (mounted) setState(() => releaseInfo = '릴리스를 확인하지 못했습니다: $e');
    } finally {
      client.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _downloadRelease() async {
    final assets = (release?['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final asset = assets
        .where((a) => (a['name'] as String).endsWith('-macos.zip'))
        .firstOrNull;
    if (asset == null) {
      _message('macOS ZIP 파일을 찾을 수 없습니다');
      return;
    }
    final destination = await FilePicker.saveFile(
      dialogTitle: '릴리스 다운로드',
      fileName: asset['name'] as String,
    );
    if (destination == null) return;
    setState(() {
      busy = true;
      downloadProgress = 0;
    });
    final client = HttpClient();
    Directory? temporary;
    try {
      final request = await client.getUrl(
        Uri.parse(asset['browser_download_url'] as String),
      );
      final response = await request.close();
      if (response.statusCode != 200)
        throw HttpException('HTTP ${response.statusCode}');
      temporary = await Directory.systemTemp.createTemp(
        'adb-connector-update-',
      );
      final file = File('${temporary.path}/release.zip');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (response.contentLength > 0 && mounted)
          setState(() => downloadProgress = received / response.contentLength);
      }
      await sink.close();
      final digest = asset['digest'] as String?;
      if (digest != null && digest.startsWith('sha256:')) {
        final hash = await Process.run('/usr/bin/shasum', [
          '-a',
          '256',
          file.path,
        ]);
        if (hash.exitCode != 0 ||
            hash.stdout.toString().split(' ').first != digest.substring(7))
          throw const FormatException('다운로드 검증에 실패했습니다');
      }
      await file.copy(destination);
      _message('다운로드 완료: $destination');
    } catch (e) {
      _message('다운로드 실패: $e');
    } finally {
      client.close();
      if (temporary != null && await temporary.exists())
        await temporary.delete(recursive: true);
      if (mounted)
        setState(() {
          busy = false;
          downloadProgress = null;
        });
    }
  }

  bool get _hasSignedUpdate {
    final assets = release?['assets'] as List<dynamic>? ?? const [];
    return assets.whereType<Map<String, dynamic>>().any(
      (a) => a['name'] == 'appcast.xml' && a['state'] == 'uploaded',
    );
  }

  Future<void> _installSignedUpdate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('서명된 업데이트 설치'),
        content: const Text(
          '업데이트 확인 시 에이전트 서버와 진행 중인 에이전트 작업이 종료됩니다. 설치 중 앱이 재시작되므로 직접 실행한 파일 전송과 설치 작업을 먼저 완료해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('업데이트 확인'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (McpService.instance.running) {
        await McpService.instance.stop();
        if (mounted) setState(() {});
      }
      await autoUpdater.setFeedURL(
        'https://github.com/jkaae93/adb-connector/releases/latest/download/appcast.xml',
      );
      await autoUpdater.checkForUpdates();
    } catch (error) {
      _message('업데이트를 시작하지 못했습니다: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정 및 도구')),
    body: VaultaPageWidth(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const VaultaSectionTitle('화면'),
          Card(
            child: ListTile(
              leading: const VaultaListIcon(Icons.palette_outlined),
              title: const Text('테마'),
              trailing: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeMode,
                builder: (context, mode, _) => DropdownButton<ThemeMode>(
                  value: mode,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('시스템 설정'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('라이트'),
                    ),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('다크')),
                  ],
                  onChanged: (value) {
                    if (value != null) saveTheme(value);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const VaultaSectionTitle('ADB'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const VaultaListIcon(Icons.terminal),
                  title: const Text('실행 파일'),
                  subtitle: SelectableText('${adb.adbPath}\n$version'),
                  trailing: TextButton(
                    onPressed: _chooseAdb,
                    child: const Text('변경'),
                  ),
                ),
                ListTile(
                  leading: const VaultaListIcon(Icons.phonelink_setup),
                  title: const Text('페어링 코드로 연결'),
                  onTap: _pair,
                ),
                ListTile(
                  leading: const VaultaListIcon(Icons.qr_code_2),
                  title: const Text('QR 코드로 페어링'),
                  subtitle: const Text('QR 페어링을 지원하는 Canary ADB 필요'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const QrPairingPage(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const VaultaListIcon(Icons.wifi_find),
                  title: const Text('mDNS 기기 검색'),
                  onTap: _discover,
                ),
                ListTile(
                  leading: const VaultaListIcon(Icons.monitor_heart_outlined),
                  title: const Text('서버 상태'),
                  onTap: () => _showCommand('ADB 서버 상태', ['server-status']),
                ),
                ListTile(
                  leading: const VaultaListIcon(Icons.sync),
                  title: const Text('오프라인 기기 재연결'),
                  onTap: () => _showCommand('재연결', ['reconnect', 'offline']),
                ),
                ListTile(
                  leading: const VaultaListIcon(Icons.restart_alt),
                  title: const Text('ADB 서버 재시작'),
                  onTap: _restartServer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const VaultaSectionTitle('AI 에이전트'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const VaultaListIcon(Icons.hub_outlined),
                  title: const Text('로컬 MCP 서버'),
                  subtitle: const Text('앱이 실행 중일 때 이 Mac에서 접속합니다'),
                  value: McpService.instance.running,
                  onChanged: (enabled) async {
                    try {
                      if (enabled) {
                        await McpService.instance.start();
                      } else {
                        await McpService.instance.stop();
                      }
                      if (mounted) setState(() {});
                    } catch (e) {
                      _message('MCP 서버 오류: $e');
                    }
                  },
                ),
                ValueListenableBuilder<List<McpActivity>>(
                  valueListenable: McpService.instance.activity,
                  builder: (context, events, _) => ListTile(
                    leading: const VaultaListIcon(Icons.history),
                    title: const Text('에이전트 요청 내역'),
                    subtitle: Text(
                      events.isEmpty
                          ? '이번 실행 중 요청이 없습니다'
                          : '최근 ${events.length}개 상태',
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('에이전트 요청 내역'),
                        content: SizedBox(
                          width: 520,
                          height: 360,
                          child: ValueListenableBuilder<List<McpActivity>>(
                            valueListenable: McpService.instance.activity,
                            builder: (context, items, _) => items.isEmpty
                                ? const Center(child: Text('요청 내역이 없습니다'))
                                : ListView.builder(
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return ListTile(
                                        title: Text(
                                          '${item.name} · ${item.status}',
                                        ),
                                        subtitle: Text(
                                          '${item.time.toLocal().toString().split('.').first}\n${item.detail}',
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (McpService.instance.running)
                  ListTile(
                    title: const Text('연결 설정 복사'),
                    subtitle: Text(
                      'http://127.0.0.1:${McpService.instance.port}/mcp',
                    ),
                    trailing: const Icon(Icons.copy),
                    onTap: () {
                      final service = McpService.instance;
                      Clipboard.setData(
                        ClipboardData(
                          text: const JsonEncoder.withIndent('  ').convert({
                            'url': 'http://127.0.0.1:${service.port}/mcp',
                            'headers': {
                              'Authorization': 'Bearer ${service.token}',
                            },
                          }),
                        ),
                      );
                      _message('연결 설정을 복사했습니다');
                    },
                  ),
                if (McpService.instance.running)
                  ListTile(
                    title: const Text('stdio 연결 설정 복사'),
                    subtitle: const Text('Python 3이 필요하며 앱이 실행 중이어야 합니다'),
                    trailing: const Icon(Icons.copy),
                    onTap: () {
                      final service = McpService.instance;
                      final contents = File(
                        Platform.resolvedExecutable,
                      ).parent.parent.path;
                      final bridge =
                          '$contents/Frameworks/App.framework/Resources/flutter_assets/scripts/mcp_bridge.py';
                      Clipboard.setData(
                        ClipboardData(
                          text: const JsonEncoder.withIndent('  ').convert({
                            'command': '/usr/bin/python3',
                            'args': [bridge],
                            'env': {
                              'ADB_CONNECTOR_MCP_URL':
                                  'http://127.0.0.1:${service.port}/mcp',
                              'ADB_CONNECTOR_MCP_TOKEN': service.token,
                            },
                          }),
                        ),
                      );
                      _message('stdio 연결 설정을 복사했습니다');
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const VaultaSectionTitle('앱 업데이트'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const VaultaListIcon(Icons.system_update_alt),
                  title: const Text('GitHub 릴리스'),
                  subtitle: Text(releaseInfo ?? '최신 정식 릴리스를 확인합니다'),
                  trailing: TextButton(
                    onPressed: busy ? null : _checkRelease,
                    child: const Text('확인'),
                  ),
                ),
                if (release != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      onPressed: busy ? null : _downloadRelease,
                      icon: const Icon(Icons.download),
                      label: const Text('macOS ZIP 다운로드'),
                    ),
                  ),
                if (_hasSignedUpdate)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.icon(
                      onPressed: busy ? null : _installSignedUpdate,
                      icon: const Icon(Icons.system_update_alt),
                      label: const Text('서명된 업데이트 설치'),
                    ),
                  ),
                if (downloadProgress != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: VaultaProgressBar(value: downloadProgress!),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
