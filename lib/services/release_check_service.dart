import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ReleaseCheckService {
  ReleaseCheckService._();
  static final instance = ReleaseCheckService._();
  final notice = ValueNotifier<String?>(null);

  Future<void> checkDaily() async {
    final cache = File(
      '${Platform.environment['HOME']}/Library/Application Support/adb_connector/release_check.json',
    );
    final plist =
        '${File(Platform.resolvedExecutable).parent.parent.path}/Info.plist';
    final local = await Process.run('/usr/libexec/PlistBuddy', [
      '-c',
      'Print :CFBundleShortVersionString',
      plist,
    ]);
    if (local.exitCode != 0) return;
    final current = local.stdout.toString().trim();
    try {
      final saved =
          jsonDecode(await cache.readAsString()) as Map<String, dynamic>;
      final checked = DateTime.tryParse(saved['checked'] as String? ?? '');
      if (checked != null &&
          DateTime.now().difference(checked) < const Duration(days: 1)) {
        final cachedNotice = saved['notice'] as String?;
        notice.value = cachedNotice != null && isNewer(cachedNotice, current)
            ? cachedNotice
            : null;
        return;
      }
    } catch (_) {}
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/jkaae93/adb-connector/releases/latest',
        ),
      );
      request.headers.set('User-Agent', 'ADB-Connector');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return;
      final data =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final latest = data['tag_name'] as String;
      if (isNewer(latest, current)) notice.value = latest;
      await cache.parent.create(recursive: true);
      await cache.writeAsString(
        jsonEncode({
          'checked': DateTime.now().toIso8601String(),
          'notice': notice.value,
        }),
      );
    } catch (_) {
      // Network failure is non-fatal; settings offers manual retry.
    } finally {
      client.close(force: true);
    }
  }

  @visibleForTesting
  static bool isNewer(String remote, String local) {
    List<int>? parse(String input) {
      final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(input);
      return match == null
          ? null
          : [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
    }

    final a = parse(remote), b = parse(local);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}
