import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';

class FakeFileApi extends SectlCloudApi {
  final Map<String, Map<String, dynamic>> files = {};
  int _seq = 0;

  @override
  Future<Map<String, dynamic>> uploadFile({
    required List<int> bytes,
    required String filename,
    String mimeType = 'application/json',
  }) async {
    final id = 'file-${_seq++}';
    files[id] = {'filename': filename, 'bytes': bytes};
    return {'file_id': id, 'filename': filename};
  }

  @override
  Future<List<Map<String, dynamic>>> listFiles() async => files.entries
      .map((e) => {'file_id': e.key, 'filename': e.value['filename']})
      .toList();

  @override
  Future<void> deleteFile(String fileId) async {
    files.remove(fileId);
  }

  @override
  Future<String> getFileDownloadUrl(String fileId) async => 'fake://$fileId';

  @override
  Future<List<int>> downloadFileBytes(String downloadUrl) async =>
      (files[downloadUrl.substring('fake://'.length)]!['bytes'] as List)
          .cast<int>();
}

void main() {
  test('上传备份后只有一份，下载可解析回原内容', () async {
    final api = FakeFileApi();
    final service = CloudSyncService(api: api, deviceId: 'dev-a');

    expect(await service.uploadBackup({'history': [1, 2]}), isTrue);
    expect(api.files, hasLength(1));

    final downloaded = await service.downloadLatestBackup();
    expect(downloaded, isNotNull);
    expect(downloaded!['history'], [1, 2]);
  });

  test('再次上传会先删旧备份，只保留最新', () async {
    final api = FakeFileApi();
    final service = CloudSyncService(api: api, deviceId: 'dev-a');

    await service.uploadBackup({'v': 1});
    await service.uploadBackup({'v': 2});
    expect(api.files, hasLength(1));

    final downloaded = await service.downloadLatestBackup();
    expect(downloaded!['v'], 2);
  });

  test('无备份时返回 null', () async {
    final api = FakeFileApi();
    final service = CloudSyncService(api: api, deviceId: 'dev-a');
    expect(await service.downloadLatestBackup(), isNull);
  });
}
