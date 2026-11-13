enum DevicePlatform { android, ios }

class SavedDevice {
  SavedDevice({
    required this.id,
    required this.nickname,
    this.ip = '',
    this.port = 5555,
    this.serialName,
    this.modelName,
    this.platform = DevicePlatform.android,
  });

  factory SavedDevice.fromJson(Map<String, dynamic> json) {
    return SavedDevice(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 5555,
      serialName: json['serialName'] as String?,
      modelName: json['modelName'] as String?,
      platform: json['platform'] == 'ios'
          ? DevicePlatform.ios
          : DevicePlatform.android,
    );
  }

  final String id;
  String nickname;
  String ip;
  int port;
  String? serialName;
  String? modelName;
  final DevicePlatform platform;

  bool get isIos => platform == DevicePlatform.ios;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'ip': ip,
      'port': port,
      'serialName': serialName,
      'modelName': modelName,
      'platform': platform.name,
    };
  }

  SavedDevice copyWith({
    String? nickname,
    String? ip,
    int? port,
    String? serialName,
    String? modelName,
  }) {
    return SavedDevice(
      id: id,
      nickname: nickname ?? this.nickname,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      serialName: serialName ?? this.serialName,
      modelName: modelName ?? this.modelName,
      platform: platform,
    );
  }
}

class ConnectedDevice {
  ConnectedDevice({
    required this.identifier,
    required this.state,
    this.modelName,
  });

  final String identifier;
  final String state;
  String? modelName;
  String? hardwareSerial;

  bool get isIpConnection => port != null;
  bool get isMdnsConnection => identifier.contains('_adb-tls-connect._tcp');
  bool get isNetworkConnection => isIpConnection || isMdnsConnection;

  String? get ip {
    if (!isIpConnection) return null;
    final host = identifier.substring(0, identifier.lastIndexOf(':'));
    return host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
  }

  int? get port {
    final index = identifier.lastIndexOf(':');
    if (index < 1) return null;
    return int.tryParse(identifier.substring(index + 1));
  }
}
