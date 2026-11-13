import 'dart:io';

import 'package:adb_connector/widgets/ios_install_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows installation output and a verified success', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IosInstallDialog(
              startInstall: () => Process.start('/usr/bin/printf', ['설치 완료\n']),
              isInstalled: () => true,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('설치가 완료되었습니다.'), findsOneWidget);
    expect(find.textContaining('설치 완료'), findsOneWidget);
  });

  testWidgets('shows failure and retains the copy and retry actions', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IosInstallDialog(
              startInstall: () => Process.start('/usr/bin/false', []),
              isInstalled: () => false,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('설치에 실패했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.byTooltip('설치 명령어 복사'), findsOneWidget);
  });

  testWidgets(
    'does not report success when tools are missing after exit zero',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IosInstallDialog(
                startInstall: () => Process.start('/usr/bin/true', []),
                isInstalled: () => false,
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('iOS 도구를 찾을 수 없습니다'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    },
  );

  testWidgets('explains when Homebrew cannot be started', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IosInstallDialog(
              startInstall: () async =>
                  throw const FileSystemException('Homebrew를 찾을 수 없습니다'),
              isInstalled: () => false,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Homebrew를 찾을 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
