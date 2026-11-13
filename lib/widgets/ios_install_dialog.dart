import 'dart:convert';
import 'dart:io';

import 'package:adb_connector/services/ios_service.dart';
import 'package:adb_connector/theme/vaulta.dart';
import 'package:adb_connector/widgets/copy_ios_install_command_button.dart';
import 'package:flutter/material.dart';

class IosInstallDialog extends StatefulWidget {
  const IosInstallDialog({super.key, this.startInstall, this.isInstalled});

  final Future<Process> Function()? startInstall;
  final bool Function()? isInstalled;

  @override
  State<IosInstallDialog> createState() => _IosInstallDialogState();
}

class _IosInstallDialogState extends State<IosInstallDialog> {
  bool _running = true;
  bool _success = false;
  String _status = 'Homebrew로 설치하고 있습니다...';
  String _output = '';
  final ScrollController _logScroll = ScrollController();
  static const _maxOutput = 100000;

  @override
  void initState() {
    super.initState();
    _install();
  }

  void _append(String text) {
    if (!mounted) return;
    final follow =
        !_logScroll.hasClients ||
        _logScroll.position.pixels >= _logScroll.position.maxScrollExtent - 24;
    setState(() {
      _output += text;
      if (_output.length > _maxOutput) {
        _output = _output.substring(_output.length - _maxOutput);
      }
    });
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() {
      _running = true;
      _success = false;
      _status = 'Homebrew로 설치하고 있습니다...';
      _output = '';
    });
    try {
      final process =
          await (widget.startInstall ??
              IosService.instance.installWithHomebrew)();
      await process.stdin.close();
      const decoder = Utf8Decoder(allowMalformed: true);
      final stdoutDone = process.stdout.transform(decoder).forEach(_append);
      final stderrDone = process.stderr.transform(decoder).forEach(_append);
      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      final installed =
          (widget.isInstalled ?? IosService.instance.isAvailable)();
      if (!mounted) return;
      setState(() {
        _running = false;
        _success = exitCode == 0 && installed;
        _status = _success
            ? '설치가 완료되었습니다.'
            : exitCode == 0
            ? '설치는 끝났지만 iOS 도구를 찾을 수 없습니다. 아래 로그를 확인해 주세요.'
            : '설치에 실패했습니다 (종료 코드 $exitCode). 권한이나 인증이 필요하다면 명령을 복사해 터미널에서 실행해 주세요.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _status = '설치를 시작하지 못했습니다: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    child: AlertDialog(
      title: const Text('libimobiledevice 설치'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status),
            if (_running) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Container(
              height: 220,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Vaulta.bg
                    : Vaulta.lightBg,
                borderRadius: BorderRadius.circular(Vaulta.radiusChip),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Vaulta.stroke
                      : Vaulta.lightStroke,
                ),
              ),
              child: SingleChildScrollView(
                controller: _logScroll,
                child: SelectableText(
                  _output.isEmpty ? '설치 로그를 기다리는 중...' : _output,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_running && !_success) const CopyIosInstallCommandButton(),
        if (!_running && !_success)
          TextButton(onPressed: _install, child: const Text('다시 시도')),
        TextButton(
          onPressed: _running
              ? null
              : () => Navigator.of(context).pop(_success),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}
