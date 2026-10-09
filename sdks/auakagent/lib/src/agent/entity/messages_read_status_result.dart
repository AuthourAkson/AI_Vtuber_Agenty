/// 消息已读状态查询结果
class MessagesReadStatusResult {
  final String employeeId;
  final String deviceId;
  /// messageId -> isRead
  final Map<String, bool> readStatus;

  const MessagesReadStatusResult({
    required this.employeeId,
    required this.deviceId,
    required this.readStatus,
  });

  factory MessagesReadStatusResult.fromMap(Map<String, dynamic> map) {
    final raw = map['readStatus'] as Map<String, dynamic>? ?? {};
    return MessagesReadStatusResult(
      employeeId: map['employeeId'] as String,
      deviceId: map['deviceId'] as String,
      readStatus: raw.map((k, v) => MapEntry(k, v as bool? ?? false)),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'deviceId': deviceId,
      'readStatus': readStatus,
    };
  }
}
