import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/database_manager.dart';
import 'package:auakagent/src/persistence/entities/device_config_entity.dart';
import 'package:auakagent/src/persistence/stores/device_config_store.dart';

int _testCounter = 0;

/// DeviceConfigStore 单元测试
///
/// 验证：
/// - CRUD 全流程（find、getOrCreate、save、delete）
/// - 环境变量操作（updateEnvironmentVariables、setEnvironmentVariable、deleteEnvironmentVariable）
/// - updateDeviceInfo
/// - findAll、count
/// - 空数据库查询返回 null/0
void main() {
  late String testDbPath;
  late String deviceId;
  late DeviceConfigStore store;

  setUp(() async {
    _testCounter++;
    testDbPath =
        '${Directory.systemTemp.path}/wenzagent_devconf_test_$_testCounter';
    await Directory(testDbPath).create(recursive: true);

    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';

    await DatabaseManager.getInstance(deviceId).initialize(
      storagePath: testDbPath,
    );

    store = DeviceConfigStore(deviceId: deviceId);
  });

  tearDown(() async {
    await DatabaseManager.getInstance(deviceId).close();
    DatabaseManager.removeInstance(deviceId);
    try {
      await Directory(testDbPath).delete(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════

  DeviceConfigEntity createConfig({
    String? id,
    DeviceInfoConfig? deviceInfo,
    Map<String, String>? envVars,
  }) {
    final now = DateTime.now();
    return DeviceConfigEntity(
      deviceId: id ?? 'test-device-${const Uuid().v4().substring(0, 8)}',
      deviceInfo: deviceInfo,
      environmentVariables: envVars,
      createTime: now,
      updateTime: now,
    );
  }

  DeviceInfoConfig createDeviceInfo({
    String? name,
    String? type,
    String? os,
    String? appVersion,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    return DeviceInfoConfig(
      name: name ?? '测试设备',
      type: type ?? 'desktop',
      os: os ?? 'Windows 11',
      appVersion: appVersion ?? '1.0.0',
      tags: tags ?? ['test'],
      metadata: metadata ?? {'key': 'value'},
    );
  }

  // ═══════════════════════════════════════════════════
  // 1. save + find 基本读写
  // ═══════════════════════════════════════════════════

  group('save + find', () {
    test('save 后 find 返回相同数据', () async {
      final config = createConfig(id: 'dev-1');
      await store.save(config);

      final found = await store.find('dev-1');
      expect(found, isNotNull);
      expect(found!.deviceId, equals('dev-1'));
      expect(found.environmentVariables, isEmpty);
    });

    test('find 不存在的 deviceId 返回 null', () async {
      final found = await store.find('non-existent');
      expect(found, isNull);
    });

    test('save 保存 deviceInfo 完整字段', () async {
      final deviceInfo = createDeviceInfo(
        name: '我的电脑',
        type: 'desktop',
        os: 'macOS',
        appVersion: '2.0.0',
        tags: ['prod', 'mac'],
        metadata: {'region': 'cn'},
      );

      final config = createConfig(id: 'dev-info', deviceInfo: deviceInfo);
      await store.save(config);

      final found = await store.find('dev-info');
      expect(found, isNotNull);
      expect(found!.deviceInfo.name, equals('我的电脑'));
      expect(found.deviceInfo.type, equals('desktop'));
      expect(found.deviceInfo.os, equals('macOS'));
      expect(found.deviceInfo.appVersion, equals('2.0.0'));
      expect(found.deviceInfo.tags, equals(['prod', 'mac']));
      expect(found.deviceInfo.metadata, equals({'region': 'cn'}));
    });

    test('save 保存环境变量', () async {
      final config = createConfig(
        id: 'dev-env',
        envVars: {'API_KEY': '123', 'DEBUG': 'true'},
      );
      await store.save(config);

      final found = await store.find('dev-env');
      expect(found, isNotNull);
      expect(found!.environmentVariables['API_KEY'], equals('123'));
      expect(found.environmentVariables['DEBUG'], equals('true'));
    });

    test('save 保留时间戳精度', () async {
      final ct = DateTime(2025, 6, 1, 10, 0, 0);
      final ut = DateTime(2025, 6, 2, 15, 30, 0);
      final config = DeviceConfigEntity(
        deviceId: 'dev-time',
        createTime: ct,
        updateTime: ut,
      );
      await store.save(config);

      final found = await store.find('dev-time');
      expect(found!.createTime.millisecondsSinceEpoch,
          equals(ct.millisecondsSinceEpoch));
      expect(found.updateTime.millisecondsSinceEpoch,
          equals(ut.millisecondsSinceEpoch));
    });

    test('save 覆盖更新（同 deviceId）', () async {
      final config = createConfig(id: 'dev-overwrite');
      await store.save(config);

      final updated = config.copyWith(
        environmentVariables: {'NEW': 'value'},
        updateTime: DateTime.now(),
      );
      await store.save(updated);

      final found = await store.find('dev-overwrite');
      expect(found!.environmentVariables['NEW'], equals('value'));
    });
  });

  // ═══════════════════════════════════════════════════
  // 2. getOrCreate 幂等性
  // ═══════════════════════════════════════════════════

  group('getOrCreate', () {
    test('不存在时自动创建', () async {
      final config = await store.getOrCreate('dev-new');

      expect(config.deviceId, equals('dev-new'));
      expect(config.environmentVariables, isEmpty);
      expect(config.deviceInfo.name, isNull);
    });

    test('已存在时返回已有数据', () async {
      final original = createConfig(
        id: 'dev-exist',
        envVars: {'KEY': 'VALUE'},
      );
      await store.save(original);

      final fetched = await store.getOrCreate('dev-exist');
      expect(fetched.environmentVariables['KEY'], equals('VALUE'));
    });

    test('多次调用返回相同数据（幂等）', () async {
      final c1 = await store.getOrCreate('dev-idem');
      final c2 = await store.getOrCreate('dev-idem');

      expect(c1.deviceId, equals(c2.deviceId));
      expect(c1.createTime.millisecondsSinceEpoch,
          equals(c2.createTime.millisecondsSinceEpoch));
    });

    test('自动创建后 find 可查到', () async {
      await store.getOrCreate('dev-auto');

      final found = await store.find('dev-auto');
      expect(found, isNotNull);
      expect(found!.deviceId, equals('dev-auto'));
    });
  });

  // ═══════════════════════════════════════════════════
  // 3. updateDeviceInfo
  // ═══════════════════════════════════════════════════

  group('updateDeviceInfo', () {
    test('更新已存在设备的 deviceInfo', () async {
      final config = createConfig(id: 'dev-udi');
      await store.save(config);

      final newInfo = createDeviceInfo(name: '新设备名', os: 'Linux');
      await store.updateDeviceInfo('dev-udi', newInfo);

      final found = await store.find('dev-udi');
      expect(found!.deviceInfo.name, equals('新设备名'));
      expect(found.deviceInfo.os, equals('Linux'));
    });

    test('不存在时自动创建后更新', () async {
      final newInfo = createDeviceInfo(name: '自动创建');
      await store.updateDeviceInfo('dev-auto-udi', newInfo);

      final found = await store.find('dev-auto-udi');
      expect(found, isNotNull);
      expect(found!.deviceInfo.name, equals('自动创建'));
    });

    test('更新 deviceInfo 不影响环境变量', () async {
      final config = createConfig(
        id: 'dev-udi-env',
        envVars: {'KEEP': 'me'},
      );
      await store.save(config);

      await store.updateDeviceInfo('dev-udi-env', createDeviceInfo());

      final found = await store.find('dev-udi-env');
      expect(found!.environmentVariables['KEEP'], equals('me'));
    });
  });

  // ═══════════════════════════════════════════════════
  // 4. 环境变量操作
  // ═══════════════════════════════════════════════════

  group('环境变量操作', () {
    test('updateEnvironmentVariables 整体替换', () async {
      final config = createConfig(
        id: 'dev-env-replace',
        envVars: {'OLD': 'value'},
      );
      await store.save(config);

      await store.updateEnvironmentVariables('dev-env-replace', {
        'NEW1': 'val1',
        'NEW2': 'val2',
      });

      final found = await store.find('dev-env-replace');
      expect(found!.environmentVariables.length, equals(2));
      expect(found.environmentVariables['NEW1'], equals('val1'));
      expect(found.environmentVariables['NEW2'], equals('val2'));
      expect(found.environmentVariables.containsKey('OLD'), isFalse);
    });

    test('setEnvironmentVariable 添加新变量', () async {
      final config = createConfig(id: 'dev-env-set');
      await store.save(config);

      await store.setEnvironmentVariable('dev-env-set', 'API_KEY', 'abc123');

      final found = await store.find('dev-env-set');
      expect(found!.environmentVariables['API_KEY'], equals('abc123'));
    });

    test('setEnvironmentVariable 更新已有变量', () async {
      final config = createConfig(
        id: 'dev-env-update',
        envVars: {'KEY': 'old'},
      );
      await store.save(config);

      await store.setEnvironmentVariable('dev-env-update', 'KEY', 'new');

      final found = await store.find('dev-env-update');
      expect(found!.environmentVariables['KEY'], equals('new'));
    });

    test('setEnvironmentVariable 不影响其他变量', () async {
      final config = createConfig(
        id: 'dev-env-isolate',
        envVars: {'KEEP': 'me', 'CHANGE': 'old'},
      );
      await store.save(config);

      await store.setEnvironmentVariable('dev-env-isolate', 'CHANGE', 'new');

      final found = await store.find('dev-env-isolate');
      expect(found!.environmentVariables['KEEP'], equals('me'));
      expect(found.environmentVariables['CHANGE'], equals('new'));
    });

    test('setEnvironmentVariable 不存在时自动创建', () async {
      await store.setEnvironmentVariable('dev-env-auto', 'KEY', 'val');

      final found = await store.find('dev-env-auto');
      expect(found, isNotNull);
      expect(found!.environmentVariables['KEY'], equals('val'));
    });

    test('deleteEnvironmentVariable 删除指定变量', () async {
      final config = createConfig(
        id: 'dev-env-del',
        envVars: {'A': '1', 'B': '2', 'C': '3'},
      );
      await store.save(config);

      await store.deleteEnvironmentVariable('dev-env-del', 'B');

      final found = await store.find('dev-env-del');
      expect(found!.environmentVariables.length, equals(2));
      expect(found.environmentVariables.containsKey('B'), isFalse);
      expect(found.environmentVariables['A'], equals('1'));
      expect(found.environmentVariables['C'], equals('3'));
    });

    test('deleteEnvironmentVariable 不存在的 key 不报错', () async {
      final config = createConfig(
        id: 'dev-env-del-noop',
        envVars: {'A': '1'},
      );
      await store.save(config);

      await store.deleteEnvironmentVariable('dev-env-del-noop', 'NON_EXISTENT');

      final found = await store.find('dev-env-del-noop');
      expect(found!.environmentVariables.length, equals(1));
    });

    test('deleteEnvironmentVariable 设备不存在时不报错', () async {
      // 不应抛异常
      await store.deleteEnvironmentVariable('non-existent', 'KEY');
    });

    test('连续 set/delete 操作序列', () async {
      final config = createConfig(id: 'dev-env-seq');
      await store.save(config);

      await store.setEnvironmentVariable('dev-env-seq', 'A', '1');
      await store.setEnvironmentVariable('dev-env-seq', 'B', '2');
      await store.setEnvironmentVariable('dev-env-seq', 'C', '3');
      await store.deleteEnvironmentVariable('dev-env-seq', 'B');
      await store.setEnvironmentVariable('dev-env-seq', 'A', 'updated');

      final found = await store.find('dev-env-seq');
      expect(found!.environmentVariables.length, equals(2));
      expect(found.environmentVariables['A'], equals('updated'));
      expect(found.environmentVariables['C'], equals('3'));
    });
  });

  // ═══════════════════════════════════════════════════
  // 5. delete 删除
  // ═══════════════════════════════════════════════════

  group('delete', () {
    test('delete 后 find 返回 null', () async {
      final config = createConfig(id: 'dev-del');
      await store.save(config);

      await store.delete('dev-del');

      expect(await store.find('dev-del'), isNull);
    });

    test('delete 不存在的 deviceId 不报错', () async {
      await store.delete('non-existent');
    });
  });

  // ═══════════════════════════════════════════════════
  // 6. findAll / count
  // ═══════════════════════════════════════════════════

  group('findAll / count', () {
    test('count 空数据库返回 0', () async {
      expect(await store.count(), equals(0));
    });

    test('findAll 空数据库返回空列表', () async {
      expect(await store.findAll(), isEmpty);
    });

    test('count 返回正确数量', () async {
      await store.save(createConfig(id: 'dev-c1'));
      await store.save(createConfig(id: 'dev-c2'));
      await store.save(createConfig(id: 'dev-c3'));

      expect(await store.count(), equals(3));
    });

    test('findAll 返回所有配置', () async {
      await store.save(createConfig(id: 'dev-f1'));
      await store.save(createConfig(id: 'dev-f2'));

      final all = await store.findAll();
      expect(all.length, equals(2));
      final ids = all.map((c) => c.deviceId).toSet();
      expect(ids, containsAll(['dev-f1', 'dev-f2']));
    });

    test('delete 后 count 减少', () async {
      await store.save(createConfig(id: 'dev-cd1'));
      await store.save(createConfig(id: 'dev-cd2'));
      expect(await store.count(), equals(2));

      await store.delete('dev-cd1');
      expect(await store.count(), equals(1));
    });
  });

  // ═══════════════════════════════════════════════════
  // 7. DeviceInfoConfig 边界值
  // ═══════════════════════════════════════════════════

  group('DeviceInfoConfig 边界值', () {
    test('空 tags 和 metadata', () async {
      final config = createConfig(
        id: 'dev-empty-info',
        deviceInfo: DeviceInfoConfig(),
      );
      await store.save(config);

      final found = await store.find('dev-empty-info');
      expect(found!.deviceInfo.tags, isEmpty);
      expect(found.deviceInfo.metadata, isEmpty);
    });

    test('所有字段为 null 的 DeviceInfoConfig', () async {
      final config = createConfig(
        id: 'dev-null-info',
        deviceInfo: DeviceInfoConfig(),
      );
      await store.save(config);

      final found = await store.find('dev-null-info');
      expect(found!.deviceInfo.name, isNull);
      expect(found.deviceInfo.type, isNull);
      expect(found.deviceInfo.os, isNull);
    });
  });
}
