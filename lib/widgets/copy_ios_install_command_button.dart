import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyIosInstallCommandButton extends StatelessWidget {
  const CopyIosInstallCommandButton({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.content_copy_outlined, size: 18),
    tooltip: '설치 명령어 복사',
    color: color,
    onPressed: () async {
      await Clipboard.setData(
        const ClipboardData(text: 'brew install libimobiledevice'),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('설치 명령어를 복사했습니다')));
    },
  );
}
