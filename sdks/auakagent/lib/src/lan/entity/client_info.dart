/// LAN 客户端信息
class ClientInfo {
  final String id;
  final String? ip;
  final String? hostIp;
  final int hostPort;
  final bool isConnected;
  final String deviceId;
  final String? topic;
  final String? name;

  const ClientInfo({
    required this.id,
    this.ip,
    this.hostIp,
    required this.hostPort,
    required this.isConnected,
    required this.deviceId,
    this.topic,
    this.name,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ip': ip,
      'hostIp': hostIp,
      'hostPort': hostPort,
      'isConnected': isConnected,
      'deviceId': deviceId,
      'topic': topic,
      'name': name,
    };
  }

  @override
  String toString() =>
      'ClientInfo(id: $id, deviceId: $deviceId, ip: $ip, connected: $isConnected)';
}
