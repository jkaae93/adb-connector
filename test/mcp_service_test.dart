import 'dart:convert';
import 'dart:io';
import 'package:adb_connector/services/mcp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MCP requires a token and never executes a rejected request', () async {
    final service = McpService.instance;
    await service.start();
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://127.0.0.1:${service.port}/mcp');
      final denied = await client.postUrl(uri);
      denied.write('{}');
      expect((await denied.close()).statusCode, HttpStatus.forbidden);

      service.approve = (_, _) async => false;
      final request = await client.postUrl(uri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${service.token}',
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'adb_connect',
            'arguments': {'host': '127.0.0.1', 'port': 5555},
          },
        }),
      );
      final response = await request.close();
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect((body['result'] as Map<String, dynamic>)['isError'], isTrue);
      expect(body.toString(), contains('denied'));
      final install = await client.postUrl(uri);
      install.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${service.token}',
      );
      install.headers.contentType = ContentType.json;
      install.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {
            'name': 'adb_install',
            'arguments': {'serial': 'test-device', 'path': '/tmp/example.apk'},
          },
        }),
      );
      final installResponse = await install.close();
      final installBody =
          jsonDecode(await installResponse.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(
        (installBody['result'] as Map<String, dynamic>)['isError'],
        isTrue,
      );
      expect(installBody.toString(), contains('denied'));

      final pair = await client.postUrl(uri);
      pair.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${service.token}',
      );
      pair.headers.contentType = ContentType.json;
      pair.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'adb_pair',
            'arguments': {'host': '127.0.0.1', 'port': 12345, 'code': '123456'},
          },
        }),
      );
      final pairResponse = await pair.close();
      final pairBody =
          jsonDecode(await pairResponse.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect((pairBody['result'] as Map<String, dynamic>)['isError'], isTrue);
      expect(
        service.activity.value
            .where((event) => event.name == 'adb_pair')
            .map((event) => event.detail)
            .join(),
        isNot(contains('123456')),
      );
    } finally {
      client.close(force: true);
      await service.stop();
      service.approve = null;
    }
  });
}
