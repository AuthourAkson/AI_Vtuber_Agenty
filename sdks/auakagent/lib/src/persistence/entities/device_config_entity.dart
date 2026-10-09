/// 设备配置实体
///
/// 存储设备级别的配置信息，包括设备信息和环境变量
class DeviceConfigEntity {
  /// 设备ID（主键）
  final String deviceId;

  /// 设备信息配置
  DeviceInfoConfig deviceInfo;

  /// 设备环境变量配置
  Map<String, String> environmentVariables;

  /// 创建时间
  DateTime createTime;

  /// 更新时间
  DateTime updateTime;

  DeviceConfigEntity({
    required this.deviceId,
    DeviceInfoConfig? deviceInfo,
    Map<String, String>? environmentVariables,
    required this.createTime,
    required this.updateTime,
  })  : deviceInfo = deviceInfo ?? DeviceInfoConfig(),
        environmentVariables = environmentVariables ?? {};

  /// 从Map创建
  factory DeviceConfigEntity.fromMap(Map<String, dynamic> map) {
    return DeviceConfigEntity(
      deviceId: map['deviceId'] as String,
      deviceInfo: map['deviceInfo'] != null
          ? DeviceInfoConfig.fromMap(map['deviceInfo'] as Map<String, dynamic>)
          : DeviceInfoConfig(),
      environmentVariables: map['environmentVariables'] != null
          ? Map<String, String>.from(map['environmentVariables'] as Map)
          : {},
      createTime: map['createTime'] is DateTime
          ? map['createTime'] as DateTime
          : DateTime.fromMillisecondsSinceEpoch(map['createTime'] as int? ?? 0),
      updateTime: map['updateTime'] is DateTime
          ? map['updateTime'] as DateTime
          : DateTime.fromMillisecondsSinceEpoch(map['updateTime'] as int? ?? 0),
    );
  }

  /// 转换为Map
  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceInfo': deviceInfo.toMap(),
      'environmentVariables': environmentVariables,
      'createTime': createTime.millisecondsSinceEpoch,
      'updateTime': updateTime.millisecondsSinceEpoch,
    };
  }

  /// 复制并修改
  DeviceConfigEntity copyWith({
    String? deviceId,
    DeviceInfoConfig? deviceInfo,
    Map<String, String>? environmentVariables,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    return DeviceConfigEntity(
      deviceId: deviceId ?? this.deviceId,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      environmentVariables: environmentVariables ?? this.environmentVariables,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
    );
  }

  @override
  String toString() {
    return 'DeviceConfigEntity(deviceId: $deviceId, deviceInfo: $deviceInfo, environmentVariables: $environmentVariables)';
  }
}

/// 设备信息配置
class DeviceInfoConfig {
  /// 设备名称
  String? name;

  /// 设备类型（如：desktop, mobile, web, server等）
  String? type;

  /// 设备描述
  String? description;

  /// 设备图标（图标名称或URL）
  String? icon;

  /// 操作系统
  String? os;

  /// 操作系统版本
  String? osVersion;

  /// 应用版本
  String? appVersion;

  /// 设备型号
  String? model;

  /// 制造商
  String? manufacturer;

  /// 自定义标签（用于分类或筛选）
  List<String> tags;

  /// 自定义元数据（JSON格式）
  Map<String, dynamic> metadata;

  DeviceInfoConfig({
    this.name,
    this.type,
    this.description,
    this.icon,
    this.os,
    this.osVersion,
    this.appVersion,
    this.model,
    this.manufacturer,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  })  : tags = tags ?? [],
        metadata = metadata ?? {};

  /// 从Map创建
  factory DeviceInfoConfig.fromMap(Map<String, dynamic> map) {
    return DeviceInfoConfig(
      name: map['name'] as String?,
      type: map['type'] as String?,
      description: map['description'] as String?,
      icon: map['icon'] as String?,
      os: map['os'] as String?,
      osVersion: map['osVersion'] as String?,
      appVersion: map['appVersion'] as String?,
      model: map['model'] as String?,
      manufacturer: map['manufacturer'] as String?,
      tags: map['tags'] != null ? List<String>.from(map['tags'] as List) : [],
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : {},
    );
  }

  /// 转换为Map
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'description': description,
      'icon': icon,
      'os': os,
      'osVersion': osVersion,
      'appVersion': appVersion,
      'model': model,
      'manufacturer': manufacturer,
      'tags': tags,
      'metadata': metadata,
    };
  }

  /// 复制并修改
  DeviceInfoConfig copyWith({
    String? name,
    String? type,
    String? description,
    String? icon,
    String? os,
    String? osVersion,
    String? appVersion,
    String? model,
    String? manufacturer,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    return DeviceInfoConfig(
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      os: os ?? this.os,
      osVersion: osVersion ?? this.osVersion,
      appVersion: appVersion ?? this.appVersion,
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'DeviceInfoConfig(name: $name, type: $type, description: $description)';
  }
}
