import 'package:adb_connector/widgets/copy_ios_install_command_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copies the install command and confirms success', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CopyIosInstallCommandButton())),
    );
    await tester.tap(find.byTooltip('설치 명령어 복사'));
    await tester.pump();
    expect(copied, 'brew install libimobiledevice');
    expect(find.text('설치 명령어를 복사했습니다'), findsOneWidget);
  });
}
