import 'dart:convert';
import 'dart:typed_data';
import 'package:adb_connector/services/adb_service.dart';
import 'package:adb_connector/theme/vaulta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class QrPairingPage extends StatefulWidget {
  const QrPairingPage({super.key});
  @override
  State<QrPairingPage> createState() => _QrPairingPageState();
}

class _QrPairingPageState extends State<QrPairingPage> {
  final terminal = Terminal(maxLines: 1000);
  Pty? process;
  String status = 'QR 페어링을 준비하고 있습니다';
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    final adb = AdbService();
    final help = await adb.command(['help']);
    if (!mounted) return;
    if (!'${help.stdout}${help.stderr}'.contains('--qr')) {
      setState(
        () => status = '선택한 ADB는 QR 페어링을 지원하지 않습니다. QR 지원 Canary ADB를 선택하세요.',
      );
      return;
    }
    try {
      final pty = Pty.start(
        adb.adbPath,
        arguments: ['pair', '--qr'],
        rows: 40,
        columns: 80,
      );
      process = pty;
      utf8.decoder.bind(pty.output.cast<List<int>>()).listen(terminal.write);
      terminal.onOutput = (text) =>
          pty.write(Uint8List.fromList(utf8.encode(text)));
      setState(() => status = '기기의 무선 디버깅에서 QR 코드 페어링을 선택하세요');
      final code = await pty.exitCode;
      process = null;
      if (mounted)
        setState(
          () => status = code == 0
              ? '페어링이 완료되었습니다. 연결 상태를 확인하세요.'
              : '페어링이 종료되었습니다 (코드 $code).',
        );
    } catch (e) {
      if (mounted) setState(() => status = 'QR 페어링을 시작할 수 없습니다: $e');
    }
  }

  @override
  void dispose() {
    process?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('QR 페어링')),
      body: VaultaPageWidth(
        maxWidth: 900,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const VaultaListIcon(Icons.qr_code_2),
                  title: Text(status, style: const TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Vaulta.radiusCard),
                    border: Border.all(
                      color: dark ? Vaulta.stroke : Vaulta.lightStroke,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Vaulta.radiusCard),
                    child: TerminalView(terminal),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
