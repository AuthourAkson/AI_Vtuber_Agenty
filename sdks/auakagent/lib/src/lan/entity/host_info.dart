/// LAN 服务端信息
class HostInfo {
  final bool isRunning;
  final String? ip;
  final int port;
  final List<Map<String, dynamic>> clients;

  const HostInfo({
    required this.isRunning,
    this.ip,
    required this.port,
    required this.clients,
  });

  Map<String, dynamic> toMap() {
    return {
      'isRunning': isRunning,
      'ip': ip,
      'port': port,
      'clients': clients,
    };
  }

  @override
  String toString() =>
      'HostInfo(isRunning: $isRunning, ip: $ip, port: $port)';
}
