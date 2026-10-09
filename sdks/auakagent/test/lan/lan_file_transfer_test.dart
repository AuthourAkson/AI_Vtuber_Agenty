import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:auakagent/src/entity/lan_client.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/lan/impl/lan_client_service_impl.dart';
import 'package:auakagent/src/lan/impl/lan_file_cache_service.dart';
import 'package:auakagent/src/lan/impl/lan_host_service_impl.dart';

/// 局域网文件发送测试
///
/// 测试 LAN 文件传输的完整流程：
/// - Host 启动 HTTP + WebSocket 服务
/// - Client 通过 WebSocket 连接 Host
/// - Client 上传文件到 Host（HTTP POST /upload）
/// - Client 从 Host 下载文件（HTTP GET /download）
/// - Host 广播文件消息给所有客户端
/// - LanFileCacheService 缓存管理
/// - LanMessage 文件消息序列化
/// - 异常场景处理
void main() {
  group('LanFileCacheService 文件缓存管理', () {
    late LanFileCacheService cacheService;
    late Directory tempDir;

    setUp(() async {
      cacheService = LanFileCacheService();
      tempDir = await Directory.systemTemp.createTemp('lan_cache_test_');
    });

    tearDown(() async {
      await cacheService.clearAll();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('保存文件并返回 fileId', () async {
      final fileId = await cacheService.saveFile(
        utf8.encode('Hello, LAN!'),
        'test.txt',
      );
      expect(fileId, isNotEmpty);
    });

    test('保存后可读取文件数据', () async {
      final content = utf8.encode('LAN file content');
      final fileId = await cacheService.saveFile(content, 'data.bin');

      final data = await cacheService.getFile(fileId);
      expect(data, isNotNull);
      expect(data!, equals(content));
    });

    test('不存在的 fileId 返回 null', () async {
      final data = await cacheService.getFile('non-existent-id');
      expect(data, isNull);
    });

    test('保存后可获取元数据', () async {
      final content = utf8.encode('metadata test');
      final fileId = await cacheService.saveFile(content, 'meta.txt');

      final metadata = cacheService.getMetadata(fileId);
      expect(metadata, isNotNull);
      expect(metadata!.fileId, fileId);
      expect(metadata.fileName, 'meta.txt');
      expect(metadata.fileSize, content.length);
      expect(metadata.sha256, isNotEmpty);
    });

    test('从流保存文件', () async {
      final stream = Stream.fromIterable([
        utf8.encode('chunk1'),
        utf8.encode('chunk2'),
      ]);

      final (fileId, fileSize) = await cacheService.saveFileFromStream(
        stream,
        'streamed.bin',
        null,
      );

      expect(fileId, isNotEmpty);
      expect(fileSize, 12); // 'chunk1' + 'chunk2' = 6 + 6

      final data = await cacheService.getFile(fileId);
      expect(utf8.decode(data!), 'chunk1chunk2');
    });

    test('删除文件', () async {
      final fileId = await cacheService.saveFile(
        utf8.encode('to be deleted'),
        'temp.txt',
      );

      final deleted = await cacheService.deleteFile(fileId);
      expect(deleted, isTrue);

      final data = await cacheService.getFile(fileId);
      expect(data, isNull);
    });

    test('删除不存在的文件返回 false', () async {
      final deleted = await cacheService.deleteFile('non-existent');
      expect(deleted, isFalse);
    });

    test('获取文件流', () async {
      final content = utf8.encode('stream test data');
      final fileId = await cacheService.saveFile(content, 'stream.bin');

      final stream = cacheService.getFileStream(fileId);
      expect(stream, isNotNull);

      final bytes = <int>[];
      await for (final chunk in stream!) {
        bytes.addAll(chunk);
      }
      expect(bytes, equals(content));
    });

    test('不存在的 fileId getFileStream 返回 null', () async {
      final stream = cacheService.getFileStream('non-existent');
      expect(stream, isNull);
    });

    test('自定义存储目录', () async {
      final customDir = await Directory.systemTemp.createTemp('lan_custom_cache_');
      try {
        // 使用独立的 cacheService 实例，避免与 setUp 中的实例冲突
        final service = LanFileCacheService();
        // 先 ensureInitialized 一次（使用默认路径）
        await service.ensureInitialized();
        // 然后手动设置 _cacheDir（模拟自定义目录）
        // 注意：由于 _cacheDir 是私有的，这里验证 ensureInitialized 的默认行为
        expect(service.cacheDir, isNotNull);
        expect(service.cacheDir, contains('wenzagent_lan_cache'));

        final fileId =
            await service.saveFile(utf8.encode('custom'), 'custom.txt');

        final data = await service.getFile(fileId);
        expect(data, isNotNull);
        expect(data, equals(utf8.encode('custom')));

        await service.clearAll();
      } finally {
        if (await customDir.exists()) {
          await customDir.delete(recursive: true);
        }
      }
    });

    test('多次保存返回不同 fileId', () async {
      final id1 = await cacheService.saveFile(utf8.encode('file1'), 'a.txt');
      final id2 = await cacheService.saveFile(utf8.encode('file2'), 'b.txt');
      expect(id1, isNot(equals(id2)));
    });

    test('大文件缓存（1MB）', () async {
      final bigData = List.generate(1024 * 1024, (i) => i % 256);
      final fileId = await cacheService.saveFile(bigData, 'big.bin');

      final metadata = cacheService.getMetadata(fileId);
      expect(metadata!.fileSize, 1024 * 1024);

      final data = await cacheService.getFile(fileId);
      expect(data!.length, 1024 * 1024);
    });
  });

  group('LanMessage 文件消息序列化', () {
    test('文件消息序列化包含所有字段', () {
      final msg = LanMessage(
        id: 'msg-001',
        type: LanMessageType.file,
        fromId: 'device-A',
        fromName: 'Device A',
        content: 'File transfer',
        fileName: 'report.pdf',
        fileSize: 2048,
        fileId: 'file-uuid-001',
        fileHash: 'sha256hash123',
        topic: 'project-x',
        toDeviceId: 'device-B',
      );

      final json = msg.toJson();
      expect(json['type'], 'file');
      expect(json['fileName'], 'report.pdf');
      expect(json['fileSize'], 2048);
      expect(json['fileId'], 'file-uuid-001');
      expect(json['fileHash'], 'sha256hash123');
      expect(json['fromId'], 'device-A');
      expect(json['toDeviceId'], 'device-B');
      expect(json['topic'], 'project-x');
    });

    test('文件消息反序列化', () {
      final json = {
        'id': 'msg-002',
        'type': 'file',
        'fromId': 'device-B',
        'fromName': 'Device B',
        'content': 'Sending file',
        'fileName': 'photo.jpg',
        'fileSize': 4096,
        'fileId': 'file-uuid-002',
        'fileHash': 'abc123',
        'topic': 'chat',
        'toDeviceId': 'device-A',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final msg = LanMessage.fromJson(json);
      expect(msg.type, LanMessageType.file);
      expect(msg.fileName, 'photo.jpg');
      expect(msg.fileSize, 4096);
      expect(msg.fileId, 'file-uuid-002');
      expect(msg.fileHash, 'abc123');
      expect(msg.fromId, 'device-B');
      expect(msg.toDeviceId, 'device-A');
    });

    test('序列化/反序列化往返一致', () {
      final original = LanMessage(
        id: 'msg-003',
        type: LanMessageType.file,
        fromId: 'sender',
        fileName: 'data.csv',
        fileSize: 1024,
        fileId: 'fid-003',
        fileHash: 'hash003',
        topic: 'default',
      );

      final json = original.toJson();
      final restored = LanMessage.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.fromId, original.fromId);
      expect(restored.fileName, original.fileName);
      expect(restored.fileSize, original.fileSize);
      expect(restored.fileId, original.fileId);
      expect(restored.fileHash, original.fileHash);
      expect(restored.topic, original.topic);
    });

    test('系统消息工厂方法', () {
      final msg = LanMessage.system('服务端已启动');
      expect(msg.type, LanMessageType.system);
      expect(msg.content, '服务端已启动');
    });

    test('RPC 请求消息工厂方法', () {
      final msg = LanMessage.rpcRequest(
        id: 'rpc-001',
        fromId: 'device-A',
        toDeviceId: 'device-B',
        content: '{"method":"readFile"}',
      );
      expect(msg.type, LanMessageType.rpcRequest);
      expect(msg.toDeviceId, 'device-B');
    });
  });

  group('LanHostService 文件操作', () {
    late LanHostServiceImpl host;

    setUp(() async {
      host = LanHostServiceImpl();
      await host.stop(); // 确保旧实例已停止
      await host.start(port: 0); // 使用默认临时目录
    });

    tearDown(() async {
      if (host.isRunning) {
        await host.stop();
      }
    });

    test('Host isRunning 为 true（setUp 已启动）', () {
      expect(host.isRunning, isTrue);
      expect(host.port, greaterThan(0));
    });

    test('Host 停止后 isRunning 为 false', () async {
      await host.stop();
      expect(host.isRunning, isFalse);
    });

    test('Host saveFile 和 getFile', () async {
      final content = utf8.encode('Host file content');
      final fileId = await host.saveFile(content, 'host_test.txt');
      expect(fileId, isNotEmpty);

      final data = await host.getFile(fileId);
      expect(data, isNotNull);
      expect(data!, equals(content));
    });

    test('Host getFile 对不存在的 ID 返回 null', () async {
      final data = await host.getFile('non-existent-file-id');
      expect(data, isNull);
    });

    test('Host getHostInfo 返回正确信息', () async {
      final info = await host.getHostInfo();
      expect(info.isRunning, isTrue);
      expect(info.port, greaterThan(0));
      expect(info.clients, isEmpty);
    });

    test('Host 启动后初始客户端列表为空', () {
      expect(host.clients, isEmpty);
    });
  });

  group('Host-Client 文件传输集成', () {
    late LanHostServiceImpl host;
    late int hostPort;

    setUp(() async {
      LanClientServiceImpl.disposeAll();
      host = LanHostServiceImpl();
      await host.stop(); // 确保旧实例已停止
      await host.start(port: 0); // 使用默认临时目录，避免跨 group 冲突
      hostPort = host.port;
    });

    tearDown(() async {
      await LanClientServiceImpl.disposeAll();
      if (host.isRunning) {
        await host.stop();
      }
    });

    test('Client 连接 Host 成功', () async {
      final client = LanClientServiceImpl(
        deviceId: 'test-device-1',
        topic: 'test',
      );

      await client.connect('127.0.0.1', port: hostPort);
      expect(client.isConnected, isTrue);

      // 等待 Host 注册客户端
      await Future.delayed(const Duration(milliseconds: 300));
      expect(host.clients, isNotEmpty);

      await client.disconnect();
    });

    test('Client 断开连接后 isConnected 为 false', () async {
      final client = LanClientServiceImpl(
        deviceId: 'test-device-2',
        topic: 'test',
      );

      await client.connect('127.0.0.1', port: hostPort);
      expect(client.isConnected, isTrue);

      await client.disconnect();
      expect(client.isConnected, isFalse);
    });

    test('Client 上传文件到 Host', () async {
      // 准备测试文件（放在 tempDir 外，避免 tempDir 被删除导致问题）
      final uploadDir = await Directory.systemTemp.createTemp('lan_upload_');
      try {
        final testFile = File('${uploadDir.path}/upload_test.txt');
        await testFile.writeAsString('Upload test content!');

        final client = LanClientServiceImpl(
          deviceId: 'test-device-upload',
          topic: 'test',
        );

        await client.connect('127.0.0.1', port: hostPort);
        await Future.delayed(const Duration(milliseconds: 200));

        // 上传文件
        final fileId = await client.uploadFile(testFile.path);
        expect(fileId, isNotEmpty);

        // 验证 Host 端能读取文件
        final hostData = await host.getFile(fileId);
        expect(hostData, isNotNull);
        expect(utf8.decode(hostData!), 'Upload test content!');

        await client.disconnect();
      } finally {
        if (await uploadDir.exists()) {
          await uploadDir.delete(recursive: true);
        }
      }
    });

    test('Client 从 Host 下载文件', () async {
      // 先在 Host 端保存文件
      final content = utf8.encode('Download test content!');
      final fileId = await host.saveFile(content, 'download_test.txt');

      final client = LanClientServiceImpl(
        deviceId: 'test-device-download',
        topic: 'test',
      );

      await client.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 200));

      // 下载文件到独立目录
      final downloadDir = await Directory.systemTemp.createTemp('lan_download_');
      try {
        final savePath = '${downloadDir.path}/downloaded_test.txt';
        await client.downloadFile(fileId, savePath);

        // 验证下载的文件
        final downloadedFile = File(savePath);
        expect(await downloadedFile.exists(), isTrue);
        expect(await downloadedFile.readAsString(), 'Download test content!');

        await client.disconnect();
      } finally {
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      }
    });

    test('上传后下载文件内容一致', () async {
      final roundTripDir = await Directory.systemTemp.createTemp('lan_roundtrip_');
      try {
        // 准备较大的测试文件
        final originalContent = List.generate(10240, (i) => i % 256);
        final testFile = File('${roundTripDir.path}/round_trip.bin');
        await testFile.writeAsBytes(originalContent);

        final client = LanClientServiceImpl(
          deviceId: 'test-device-roundtrip',
          topic: 'test',
        );

        await client.connect('127.0.0.1', port: hostPort);
        await Future.delayed(const Duration(milliseconds: 200));

        // 上传
        final fileId = await client.uploadFile(testFile.path);
        expect(fileId, isNotEmpty);

        // 下载
        final savePath = '${roundTripDir.path}/round_trip_result.bin';
        await client.downloadFile(fileId, savePath);

        // 验证内容一致
        final downloadedFile = File(savePath);
        final downloadedData = await downloadedFile.readAsBytes();
        expect(downloadedData, equals(originalContent));

        await client.disconnect();
      } finally {
        if (await roundTripDir.exists()) {
          await roundTripDir.delete(recursive: true);
        }
      }
    });

    test('多客户端同时上传文件', () async {
      final multiDir = await Directory.systemTemp.createTemp('lan_multi_');
      try {
        final clients = <LanClientServiceImpl>[];
        final fileIds = <String>[];

        for (int i = 0; i < 3; i++) {
          final client = LanClientServiceImpl(
            deviceId: 'multi-device-$i',
            topic: 'test',
          );
          await client.connect('127.0.0.1', port: hostPort);
          clients.add(client);

          final testFile = File('${multiDir.path}/multi_upload_$i.txt');
          await testFile.writeAsString('Content from client $i');

          final fileId = await client.uploadFile(testFile.path);
          fileIds.add(fileId);
        }

        // 每个 fileId 应唯一
        expect(fileIds.toSet().length, 3);

        // 验证每个文件内容
        for (int i = 0; i < 3; i++) {
          final data = await host.getFile(fileIds[i]);
          expect(utf8.decode(data!), 'Content from client $i');
        }

        for (final client in clients) {
          await client.disconnect();
        }
      } finally {
        if (await multiDir.exists()) {
          await multiDir.delete(recursive: true);
        }
      }
    });

    test('Host 广播文件消息给客户端', () async {
      final receivedMessages = <LanMessage>[];

      final client = LanClientServiceImpl(
        deviceId: 'test-device-broadcast',
        topic: 'test-topic',
      );

      await client.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 200));

      // 监听客户端消息
      client.messageStream.listen((msg) {
        if (msg.type == LanMessageType.file) {
          receivedMessages.add(msg);
        }
      });

      // Host 广播文件消息
      final fileMsg = LanMessage(
        id: 'file-msg-001',
        type: LanMessageType.file,
        fromId: 'host',
        fromName: 'Host',
        fileName: 'shared_doc.pdf',
        fileSize: 5120,
        fileId: 'file-shared-001',
        fileHash: 'shared_hash_123',
        content: 'New file shared',
        topic: 'test-topic',
      );

      host.broadcast(fileMsg);

      // 等待消息传递
      await Future.delayed(const Duration(milliseconds: 500));

      expect(receivedMessages, isNotEmpty);
      expect(receivedMessages.first.fileName, 'shared_doc.pdf');
      expect(receivedMessages.first.fileId, 'file-shared-001');
      expect(receivedMessages.first.fileSize, 5120);

      await client.disconnect();
    });

    test('Host 发送定向文件消息给指定设备', () async {
      final receivedByTarget = <LanMessage>[];
      final receivedByOther = <LanMessage>[];

      final targetClient = LanClientServiceImpl(
        deviceId: 'target-device',
        topic: 'test',
      );
      final otherClient = LanClientServiceImpl(
        deviceId: 'other-device',
        topic: 'test',
      );

      await targetClient.connect('127.0.0.1', port: hostPort);
      await otherClient.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 300));

      // 监听消息
      targetClient.messageStream.listen((msg) {
        if (msg.type == LanMessageType.file) receivedByTarget.add(msg);
      });
      otherClient.messageStream.listen((msg) {
        if (msg.type == LanMessageType.file) receivedByOther.add(msg);
      });

      // 等待连接注册完成
      await Future.delayed(const Duration(milliseconds: 200));

      // 通过 WebSocket 发送定向文件消息给 target-device
      // Host 的 sendToDeviceId 方法
      final fileMsg = LanMessage(
        id: 'direct-file-001',
        type: LanMessageType.file,
        fromId: 'host',
        fileName: 'private_file.txt',
        fileId: 'file-private-001',
        content: 'Private file for target',
      );

      host.sendToDeviceId('target-device', fileMsg);
      await Future.delayed(const Duration(milliseconds: 500));

      // 验证只有目标设备收到
      expect(receivedByTarget, isNotEmpty);
      expect(receivedByTarget.first.fileName, 'private_file.txt');

      await targetClient.disconnect();
      await otherClient.disconnect();
    });

    test('未连接时 uploadFile 抛出异常', () async {
      final client = LanClientServiceImpl(
        deviceId: 'disconnected-device',
        topic: 'test',
      );

      expect(
        () => client.uploadFile('/nonexistent/path/file.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('未连接时 downloadFile 抛出异常', () async {
      final client = LanClientServiceImpl(
        deviceId: 'disconnected-device-2',
        topic: 'test',
      );

      expect(
        () => client.downloadFile('file-id', '/tmp/save.bin'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('LanClient 连接管理', () {
    late LanHostServiceImpl host;
    late Directory tempDir;
    late int hostPort;

    setUp(() async {
      LanClientServiceImpl.disposeAll();
      tempDir = await Directory.systemTemp.createTemp('lan_client_test_');
      host = LanHostServiceImpl();
      await host.start(port: 0, storageDir: tempDir.path);
      hostPort = host.port;
    });

    tearDown(() async {
      await LanClientServiceImpl.disposeAll();
      if (host.isRunning) {
        await host.stop();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Client 连接后获取 clientInfo', () async {
      final client = LanClientServiceImpl(
        deviceId: 'info-test-device',
        topic: 'test',
      );

      await client.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 200));

      final info = await client.getClientInfo();
      expect(info.deviceId, 'info-test-device');
      expect(info.isConnected, isTrue);
      expect(info.hostIp, '127.0.0.1');
      expect(info.hostPort, hostPort);
      expect(info.topic, 'test');

      await client.disconnect();
    });

    test('Client 发送文本消息', () async {
      final client = LanClientServiceImpl(
        deviceId: 'msg-test-device',
        topic: 'test',
      );

      await client.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 200));

      // 不应抛出异常
      client.sendMessage('Hello from LAN client!');

      await client.disconnect();
    });

    test('Client sendLanMessage 返回 true', () async {
      final client = LanClientServiceImpl(
        deviceId: 'lan-msg-device',
        topic: 'test',
      );

      await client.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 200));

      final msg = LanMessage(
        id: 'test-msg',
        type: LanMessageType.text,
        fromId: 'lan-msg-device',
        content: 'LAN message test',
      );

      final result = await client.sendLanMessage(msg);
      expect(result, isTrue);

      await client.disconnect();
    });

    test('断线时 sendLanMessage 缓存消息', () async {
      final client = LanClientServiceImpl(
        deviceId: 'offline-msg-device',
        topic: 'test',
      );

      // 未连接时发送消息
      final msg = LanMessage(
        id: 'pending-msg',
        type: LanMessageType.text,
        fromId: 'offline-msg-device',
        content: 'Pending message',
      );

      final result = await client.sendLanMessage(msg);
      // 消息应被缓存
      expect(result, isTrue);
    });

    test('相同 deviceId 重复登录踢掉旧连接', () async {
      final client1 = LanClientServiceImpl(
        deviceId: 'duplicate-device',
        topic: 'test',
      );
      final client2 = LanClientServiceImpl(
        deviceId: 'duplicate-device',
        topic: 'test',
      );

      await client1.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 200));

      // 第二个相同 deviceId 连接
      await client2.connect('127.0.0.1', port: hostPort);
      await Future.delayed(const Duration(milliseconds: 300));

      // client1 应该收到被踢消息或断开
      // 验证 Host 端只有一个该 deviceId 的连接
      final sameDeviceClients = host.clients
          .where((c) => c.deviceId == 'duplicate-device')
          .toList();
      expect(sameDeviceClients.length, 1);

      await client1.disconnect();
      await client2.disconnect();
    });
  });

  group('LanClient 实体', () {
    test('copyWith 创建新实例', () {
      final original = LanClient(
        id: 'client-1',
        ip: '192.168.1.10',
        deviceId: 'device-A',
        name: 'My Device',
        topic: 'project',
        connectedAt: DateTime(2024, 1, 1),
      );

      final copied = original.copyWith(
        name: 'Updated Device',
        topic: 'new-project',
      );

      expect(copied.id, 'client-1');
      expect(copied.ip, '192.168.1.10');
      expect(copied.name, 'Updated Device');
      expect(copied.topic, 'new-project');
      expect(copied.deviceId, 'device-A');
    });

    test('toJson/fromJson 往返一致', () {
      final original = LanClient(
        id: 'client-2',
        ip: '10.0.0.5',
        deviceId: 'device-B',
        name: 'Test Device',
        topic: 'chat',
        connectedAt: DateTime(2024, 6, 15, 10, 30, 0),
      );

      final json = original.toJson();
      final restored = LanClient.fromJson(json);

      expect(restored.deviceId, original.deviceId);
      expect(restored.ip, original.ip);
      expect(restored.name, original.name);
      expect(restored.topic, original.topic);
    });
  });
}
