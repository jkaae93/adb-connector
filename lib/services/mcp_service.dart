import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:adb_connector/services/adb_service.dart';
import 'package:flutter/foundation.dart';

class McpActivity {
  const McpActivity(this.time, this.name, this.detail, this.status);
  final DateTime time;
  final String name;
  final String detail;
  final String status;
}

/// Local MCP endpoint. State-changing requests must be approved by the UI.
class McpService {
  McpService._();
  static final instance = McpService._();
  HttpServer? _server;
  String? _token;
  int _generation = 0;
  bool _pendingApproval = false;
  final Set<Process> _activeProcesses = {};
  final Map<String, Future<void>> _deviceTails = {};
  Future<bool> Function(String title, String detail)? approve;
  int? get port => _server?.port;
  String? get token => _token;
  bool get running => _server != null;
  final _adb = AdbService();
  final activity = ValueNotifier<List<McpActivity>>([]);

  void _record(String name, String detail, String status) {
    activity.value = [
      McpActivity(DateTime.now(), name, detail, status),
      ...activity.value,
    ].take(100).toList();
  }

  static const _tools = <Map<String, dynamic>>[
    {
      'name': 'adb_devices',
      'description': 'List connected Android devices and their states',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'adb_version',
      'description': 'Get the ADB version',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'adb_mdns',
      'description': 'List discovered wireless debugging services',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'adb_logs',
      'description': 'Read recent device logs',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'serial': {'type': 'string'},
          'lines': {'type': 'integer', 'minimum': 1, 'maximum': 5000},
        },
        'required': ['serial'],
      },
    },
    {
      'name': 'adb_connect',
      'description': 'Connect to a wireless device after user approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'host': {'type': 'string'},
          'port': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
        },
        'required': ['host', 'port'],
      },
    },
    {
      'name': 'adb_disconnect',
      'description': 'Disconnect a wireless device after user approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'host': {'type': 'string'},
          'port': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
        },
        'required': ['host', 'port'],
      },
    },
    {
      'name': 'adb_install',
      'description': 'Install an APK on a device after user approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'serial': {'type': 'string'},
          'path': {'type': 'string'},
        },
        'required': ['serial', 'path'],
      },
    },
    {
      'name': 'adb_transfer',
      'description': 'Upload or download a file after user approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'serial': {'type': 'string'},
          'direction': {
            'type': 'string',
            'enum': ['push', 'pull'],
          },
          'local_path': {'type': 'string'},
          'remote_path': {'type': 'string'},
        },
        'required': ['serial', 'direction', 'local_path', 'remote_path'],
      },
    },
    {
      'name': 'adb_port',
      'description':
          'Add or remove a TCP forward/reverse rule after user approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'serial': {'type': 'string'},
          'direction': {
            'type': 'string',
            'enum': ['forward', 'reverse'],
          },
          'action': {
            'type': 'string',
            'enum': ['add', 'remove'],
          },
          'source_port': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
          'destination_port': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 65535,
          },
        },
        'required': ['serial', 'direction', 'action', 'source_port'],
      },
    },
    {
      'name': 'adb_device_info',
      'description': 'Read device model',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'serial': {'type': 'string'},
        },
        'required': ['serial'],
      },
    },
    {
      'name': 'adb_list_files',
      'description': 'List files in a device directory',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'serial': {'type': 'string'},
          'path': {'type': 'string'},
        },
        'required': ['serial', 'path'],
      },
    },
    {
      'name': 'adb_pair',
      'description': 'Pair with a six digit code after approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'host': {'type': 'string'},
          'port': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
          'code': {'type': 'string', 'pattern': r'^\d{6}$'},
        },
        'required': ['host', 'port', 'code'],
      },
    },
    {
      'name': 'adb_reconnect',
      'description':
          'Reconnect offline devices or a selected device after approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'scope': {
            'type': 'string',
            'enum': ['offline', 'device'],
          },
          'serial': {'type': 'string'},
        },
        'required': ['scope'],
      },
    },
    {
      'name': 'adb_transport',
      'description': 'Switch a device between USB and TCP/IP after approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'serial': {'type': 'string'},
          'mode': {
            'type': 'string',
            'enum': ['usb', 'tcpip'],
          },
          'port': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
        },
        'required': ['serial', 'mode'],
      },
    },
    {
      'name': 'adb_server',
      'description':
          'Read, start or restart the ADB server; changes require approval',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['status', 'start', 'restart'],
          },
        },
        'required': ['action'],
      },
    },
  ];

  Future<void> start() async {
    if (running) return;
    _generation++;
    final random = Random.secure();
    _token = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    _generation++;
    for (final process in _activeProcesses.toList()) {
      process.kill();
    }
    await _server?.close(force: true);
    _server = null;
    _token = null;
  }

  Future<ProcessResult> _execute(
    List<String> args,
    int generation, {
    Duration? limit,
  }) async {
    Process? spawned;
    try {
      return await _adb.command(
        args,
        limit: limit,
        onStart: (process) {
          spawned = process;
          if (!running || generation != _generation) {
            process.kill();
          } else {
            _activeProcesses.add(process);
          }
        },
      );
    } finally {
      if (spawned != null) _activeProcesses.remove(spawned);
    }
  }

  Future<T> _serializeDevice<T>(String key, Future<T> Function() action) async {
    final previous = _deviceTails[key];
    final done = Completer<void>();
    _deviceTails[key] = done.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (identical(_deviceTails[key], done.future)) _deviceTails.remove(key);
      done.complete();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final host = request.headers.value(HttpHeaders.hostHeader) ?? '';
    final origin = request.headers.value('origin');
    if (host != '127.0.0.1:$port' ||
        origin != null ||
        request.headers.value(HttpHeaders.authorizationHeader) !=
            'Bearer $_token') {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (request.uri.path != '/mcp') {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    if (request.method != 'POST') {
      request.response.statusCode = 405;
      await request.response.close();
      return;
    }
    try {
      final body = await utf8.decoder.bind(request.cast<List<int>>()).join();
      if (body.length > 65536) throw const FormatException('Request too large');
      final message = jsonDecode(body) as Map<String, dynamic>;
      final method = message['method'];
      final id = message['id'];
      if (id == null) {
        request.response.statusCode = 202;
        await request.response.close();
        return;
      }
      dynamic result;
      switch (method) {
        case 'initialize':
          result = {
            'protocolVersion': '2025-03-26',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'adb-connector', 'version': '1.0.0'},
          };
        case 'ping':
          result = <String, dynamic>{};
        case 'tools/list':
          result = {'tools': _tools};
        case 'tools/call':
          final params = message['params'] as Map<String, dynamic>;
          result = await _call(
            params['name'] as String,
            (params['arguments'] as Map<String, dynamic>?) ?? {},
          );
        default:
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32601, 'message': 'Method not found'},
            }),
          );
          await request.response.close();
          return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
      );
    } catch (_) {
      request.response.statusCode = 400;
    }
    await request.response.close();
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> args,
  ) async {
    List<String> command;
    String? approvalDetail;
    var longRunning = false;
    var restartServer = false;
    switch (name) {
      case 'adb_devices':
        command = ['devices', '-l'];
      case 'adb_version':
        command = ['version'];
      case 'adb_mdns':
        command = ['mdns', 'services'];
      case 'adb_device_info':
        final serial = args['serial'];
        if (serial is! String || serial.isEmpty || serial.startsWith('-'))
          return _result('Invalid arguments', error: true);
        command = ['-s', serial, 'shell', 'getprop', 'ro.product.model'];
      case 'adb_list_files':
        final serial = args['serial'];
        final path = args['path'];
        if (serial is! String ||
            serial.isEmpty ||
            serial.startsWith('-') ||
            path is! String ||
            !path.startsWith('/') ||
            path.contains('\u0000'))
          return _result('Invalid arguments', error: true);
        final escaped = path.replaceAll("'", "'\\''");
        command = ['-s', serial, 'shell', "ls -la -- '$escaped'"];
      case 'adb_logs':
        final serial = args['serial'];
        final lines = args['lines'] ?? 200;
        if (serial is! String ||
            serial.isEmpty ||
            serial.startsWith('-') ||
            lines is! int ||
            lines < 1 ||
            lines > 5000)
          return _result('Invalid arguments', error: true);
        command = ['-s', serial, 'logcat', '-d', '-t', '$lines'];
      case 'adb_connect':
      case 'adb_disconnect':
        final host = args['host'];
        final port = args['port'];
        if (host is! String ||
            host.isEmpty ||
            host.startsWith('-') ||
            port is! int ||
            port < 1 ||
            port > 65535)
          return _result('Invalid arguments', error: true);
        final target = AdbService.endpoint(host, port);
        approvalDetail = target;
        command = [name == 'adb_connect' ? 'connect' : 'disconnect', target];
      case 'adb_pair':
        final host = args['host'];
        final port = args['port'];
        final code = args['code'];
        if (host is! String ||
            host.isEmpty ||
            host.startsWith('-') ||
            port is! int ||
            port < 1 ||
            port > 65535 ||
            code is! String ||
            !RegExp(r'^\d{6}$').hasMatch(code))
          return _result('Invalid arguments', error: true);
        final target = AdbService.endpoint(host, port);
        approvalDetail = '$target\n6자리 페어링 코드 제출';
        command = ['pair', target, code];
      case 'adb_reconnect':
        final scope = args['scope'];
        final serial = args['serial'];
        if (scope == 'offline') {
          approvalDetail = '오프라인 및 승인되지 않은 기기 재연결';
          command = ['reconnect', 'offline'];
        } else if (scope == 'device' &&
            serial is String &&
            serial.isNotEmpty &&
            !serial.startsWith('-')) {
          approvalDetail = 'Device: $serial';
          command = ['-s', serial, 'reconnect', 'device'];
        } else {
          return _result('Invalid arguments', error: true);
        }
      case 'adb_transport':
        final serial = args['serial'];
        final mode = args['mode'];
        final port = args['port'];
        if (serial is! String ||
            serial.isEmpty ||
            serial.startsWith('-') ||
            (mode != 'usb' && mode != 'tcpip') ||
            (mode == 'tcpip' && (port is! int || port < 1 || port > 65535)))
          return _result('Invalid arguments', error: true);
        approvalDetail =
            'Device: $serial\nMode: $mode${mode == 'tcpip' ? '\nPort: $port' : ''}';
        command = ['-s', serial, mode as String, if (mode == 'tcpip') '$port'];
      case 'adb_server':
        final action = args['action'];
        if (action == 'status') {
          command = ['server-status'];
        } else if (action == 'start') {
          approvalDetail = 'ADB 서버 시작';
          command = ['start-server'];
        } else if (action == 'restart') {
          approvalDetail = 'ADB 서버 재시작: 다른 ADB 연결도 일시 중단됩니다';
          command = ['kill-server'];
          restartServer = true;
        } else {
          return _result('Invalid arguments', error: true);
        }
      case 'adb_install':
        final serial = args['serial'];
        final path = args['path'];
        if (serial is! String ||
            serial.isEmpty ||
            serial.startsWith('-') ||
            path is! String ||
            !path.startsWith('/') ||
            !path.toLowerCase().endsWith('.apk'))
          return _result('Invalid arguments', error: true);
        approvalDetail = 'Device: $serial\nAPK: $path';
        command = ['-s', serial, 'install', path];
        longRunning = true;
      case 'adb_transfer':
        final serial = args['serial'];
        final direction = args['direction'];
        final local = args['local_path'];
        final remote = args['remote_path'];
        if (serial is! String ||
            serial.isEmpty ||
            serial.startsWith('-') ||
            (direction != 'push' && direction != 'pull') ||
            local is! String ||
            !local.startsWith('/') ||
            remote is! String ||
            !remote.startsWith('/'))
          return _result('Invalid arguments', error: true);
        approvalDetail =
            'Device: $serial\n$direction\nMac: $local\nDevice: $remote';
        command = [
          '-s',
          serial,
          direction as String,
          if (direction == 'push') ...[local, remote] else ...[remote, local],
        ];
        longRunning = true;
      case 'adb_port':
        final serial = args['serial'];
        final direction = args['direction'];
        final action = args['action'];
        final source = args['source_port'];
        final destination = args['destination_port'];
        bool validPort(Object? value) =>
            value is int && value > 0 && value <= 65535;
        if (serial is! String ||
            serial.isEmpty ||
            serial.startsWith('-') ||
            (direction != 'forward' && direction != 'reverse') ||
            (action != 'add' && action != 'remove') ||
            !validPort(source) ||
            (action == 'add' && !validPort(destination)))
          return _result('Invalid arguments', error: true);
        approvalDetail =
            'Device: $serial\n$direction $action\nSource: $source${action == 'add' ? '\nDestination: $destination' : ''}';
        command = [
          '-s',
          serial,
          direction as String,
          action == 'add' ? '--no-rebind' : '--remove',
          'tcp:$source',
          if (action == 'add') 'tcp:$destination',
        ];
      default:
        return _result('Unknown tool', error: true);
    }
    final generation = _generation;
    if (approvalDetail != null) {
      if (_pendingApproval)
        return _result('Another request is awaiting approval', error: true);
      _pendingApproval = true;
      _record(name, approvalDetail, '승인 대기');
      bool allowed;
      try {
        allowed =
            await (approve?.call(name, approvalDetail) ?? Future.value(false))
                .timeout(const Duration(seconds: 60), onTimeout: () => false);
      } finally {
        _pendingApproval = false;
      }
      if (!allowed || !running || generation != _generation) {
        _record(name, approvalDetail, '거절 또는 만료');
        return _result('Request denied or expired', error: true);
      }
      _record(name, approvalDetail, '승인됨');
    }
    Future<Map<String, dynamic>> execute() async {
      if (!running || generation != _generation)
        return _result('Request canceled', error: true);
      var result = await _execute(
        command,
        generation,
        limit: longRunning ? const Duration(minutes: 5) : null,
      );
      if (restartServer &&
          result.exitCode == 0 &&
          running &&
          generation == _generation)
        result = await _execute(['start-server'], generation);
      final output = '${result.stdout}${result.stderr}'.trim();
      final success =
          result.exitCode == 0 &&
          running &&
          generation == _generation &&
          (name != 'adb_connect' ||
              output.startsWith('connected to') ||
              output.startsWith('already connected')) &&
          (name != 'adb_pair' || output.contains('Successfully paired'));
      if (approvalDetail != null)
        _record(name, approvalDetail, success ? '완료' : '실패 또는 취소');
      return _result(output, error: !success);
    }

    if (approvalDetail == null) return execute();
    final key = (args['serial'] ?? args['host'] ?? 'server').toString();
    return _serializeDevice(key, execute);
  }

  Map<String, dynamic> _result(String text, {bool error = false}) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': error,
  };
}
