import 'package:adb_connector/models/saved_device.dart';
import 'package:adb_connector/services/adb_service.dart';
import 'package:adb_connector/services/release_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses IPv4, IPv6 and serial transports', () {
    final ipv4 = ConnectedDevice(
      identifier: '192.168.1.2:37123',
      state: 'device',
    );
    expect(ipv4.ip, '192.168.1.2');
    expect(ipv4.port, 37123);
    final ipv6 = ConnectedDevice(
      identifier: '[fe80::1234]:37123',
      state: 'device',
    );
    expect(ipv6.ip, 'fe80::1234');
    expect(ipv6.port, 37123);
    expect(
      ConnectedDevice(identifier: 'R123456', state: 'offline').isIpConnection,
      isFalse,
    );
    expect(
      ConnectedDevice(
        identifier: 'adb-serial-123._adb-tls-connect._tcp',
        state: 'device',
      ).isNetworkConnection,
      isTrue,
    );
    expect(AdbService.endpoint('fe80::1234', 1234), '[fe80::1234]:1234');
  });
  test('existing device data remains readable', () {
    final device = SavedDevice.fromJson({
      'id': '1',
      'nickname': 'Phone',
      'ip': '192.168.1.2',
    });
    expect(device.port, 5555);
    expect(device.platform, DevicePlatform.android);
  });
  test('compares stable release versions', () {
    expect(ReleaseCheckService.isNewer('v1.2.0', '1.1.9'), isTrue);
    expect(ReleaseCheckService.isNewer('v1.2.0', '1.2.0'), isFalse);
    expect(ReleaseCheckService.isNewer('v1.2.0-rc1', '1.1.0'), isFalse);
  });
}
