import 'package:adb_connector/models/log_window_arguments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves Android transport and executable path between windows', () {
    const args = LogWindowArguments(
      deviceName: '테스트 기기',
      identifier: '[fe80::1]:1234',
      isIos: false,
      adbPath: '/path with spaces/adb',
    );
    final decoded = LogWindowArguments.parse(args.encode());
    expect(decoded?.deviceName, args.deviceName);
    expect(decoded?.identifier, args.identifier);
    expect(decoded?.adbPath, args.adbPath);
    expect(decoded?.isIos, false);
  });
  test('rejects malformed and incomplete child window arguments', () {
    expect(LogWindowArguments.parse('not json'), isNull);
    expect(
      LogWindowArguments.parse(
        '{"type":"device-log","deviceName":"x","identifier":"serial","isIos":false}',
      ),
      isNull,
    );
    expect(
      LogWindowArguments.parse(
        '{"type":"other","deviceName":"x","identifier":"serial","isIos":true}',
      ),
      isNull,
    );
  });
}
