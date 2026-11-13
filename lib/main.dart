import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:adb_connector/pages/home_page.dart';
import 'package:adb_connector/pages/logcat_page.dart';
import 'package:adb_connector/models/log_window_arguments.dart';
import 'package:adb_connector/services/ios_service.dart';
import 'package:adb_connector/services/mcp_service.dart';
import 'package:adb_connector/services/release_check_service.dart';
import 'package:adb_connector/theme/vaulta.dart';
import 'package:flutter/material.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final navigatorKey = GlobalKey<NavigatorState>();
String get settingsPath =>
    '${Platform.environment['HOME']}/Library/Application Support/adb_connector/settings.json';
Future<void> saveTheme(ThemeMode mode) async {
  themeMode.value = mode;
  final file = File(settingsPath);
  Map<String, dynamic> settings = {};
  try {
    settings = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {}
  settings['theme'] = mode.name;
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(settings));
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final settings =
        jsonDecode(await File(settingsPath).readAsString())
            as Map<String, dynamic>;
    themeMode.value =
        ThemeMode.values
            .where((e) => e.name == settings['theme'])
            .firstOrNull ??
        ThemeMode.system;
  } catch (_) {}
  if (args.length >= 3 && args.first == 'multi_window') {
    final log = LogWindowArguments.parse(args[2]);
    runApp(
      AdbConnectorApp(
        home: log == null
            ? const Scaffold(body: Center(child: Text('로그 창 정보를 읽을 수 없습니다')))
            : LogcatPage(
                standaloneWindow: true,
                deviceName: log.deviceName,
                processFactory: log.isIos
                    ? () => IosService.instance.startSyslog(log.identifier)
                    : () => Process.start(log.adbPath!, [
                        '-s',
                        log.identifier,
                        'logcat',
                        '-v',
                        'threadtime',
                        '-T',
                        '1',
                      ]),
                resolvePackagePid: log.isIos
                    ? (_) async => null
                    : (packageName) async {
                        final result = await Process.run(log.adbPath!, [
                          '-s',
                          log.identifier,
                          'shell',
                          'pidof',
                          '-s',
                          packageName,
                        ]);
                        return result.stdout.toString().trim();
                      },
                onClearBuffer: log.isIos
                    ? null
                    : () async {
                        final result = await Process.run(log.adbPath!, [
                          '-s',
                          log.identifier,
                          'logcat',
                          '-c',
                        ]);
                        if (result.exitCode != 0)
                          throw ProcessException(
                            log.adbPath!,
                            ['logcat', '-c'],
                            result.stderr.toString(),
                            result.exitCode,
                          );
                      },
              ),
      ),
    );
    return;
  }
  McpService.instance.approve = (title, detail) async {
    final context = navigatorKey.currentContext;
    if (context == null) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => ApprovalDialog(title: title, detail: detail),
        ) ??
        false;
  };
  ReleaseCheckService.instance.checkDaily();
  runApp(const AdbConnectorApp());
}

class ApprovalDialog extends StatefulWidget {
  const ApprovalDialog({super.key, required this.title, required this.detail});
  final String title;
  final String detail;
  @override
  State<ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<ApprovalDialog> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(seconds: 59), () {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('에이전트 작업 요청'),
    content: SelectableText(
      '${widget.title}\n${widget.detail}\n\n60초 후 요청이 만료됩니다.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('거절'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('승인'),
      ),
    ],
  );
}

class AdbConnectorApp extends StatelessWidget {
  const AdbConnectorApp({super.key, this.home = const HomePage()});
  final Widget home;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: themeMode,
    builder: (_, mode, _) => MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ADB Connector',
      debugShowCheckedModeBanner: false,
      theme: Vaulta.theme(Brightness.light),
      darkTheme: Vaulta.theme(Brightness.dark),
      themeMode: mode,
      home: home,
    ),
  );
}
