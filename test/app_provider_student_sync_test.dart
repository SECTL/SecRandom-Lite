import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';
import 'package:secrandom_lite/services/cloud/sync_local_store.dart';
import 'package:secrandom_lite/services/cloud/sync_state.dart';
import 'package:secrandom_lite/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/isolated_data_dir.dart';
import 'helpers/test_students.dart';

class FakeCloudApi extends SectlCloudApi {
  final Map<String, dynamic> store = {};
  final Map<String, int> putCounts = {};

  T _deepCopy<T>(T value) => jsonDecode(jsonEncode(value)) as T;

  @override
  Future<dynamic> getKvValue(String key) async {
    if (!store.containsKey(key)) {
      throw const CloudApiException(statusCode: 404, error: 'not_found');
    }
    return _deepCopy(store[key]);
  }

  @override
  Future<CloudKvEntry> putKv({
    required String key,
    required dynamic value,
    int? ttl,
  }) async {
    putCounts[key] = (putCounts[key] ?? 0) + 1;
    store[key] = _deepCopy(value);
    return CloudKvEntry(key: key, value: store[key], size: 0, isJson: true);
  }

  @override
  Future<void> deleteKv(String key) async => store.remove(key);

  @override
  Future<CloudKvList> listKv({int limit = 100, int offset = 0}) async {
    final keys = store.keys.toList()..sort();
    final page = keys.skip(offset).take(limit).toList();
    return CloudKvList(
      entries: page
          .map(
            (key) => CloudKvEntry(
              key: key,
              value: _deepCopy(store[key]),
              size: 0,
              isJson: true,
            ),
          )
          .toList(),
      total: keys.length,
      hasMore: offset + page.length < keys.length,
    );
  }
}

class MemorySyncLocalStore implements SyncLocalStore {
  LocalSyncState state = LocalSyncState();
  SyncOutbox outbox = SyncOutbox();

  @override
  Future<LocalSyncState> loadState() async => state;
  @override
  Future<void> saveState(LocalSyncState s) async => state = s;
  @override
  Future<SyncOutbox> loadOutbox() async => outbox;
  @override
  Future<void> saveOutbox(SyncOutbox o) async => outbox = o;
}

HistoryRecord _record(String name, {String time = '2026-01-01 10:00:00'}) =>
    HistoryRecord(
      id: 1,
      uid: 'dev-a:h1',
      name: name,
      drawMethod: 1,
      drawTime: time,
      drawPeopleNumbers: 1,
      drawGroup: '1',
      drawGender: '所有性别',
      className: '1',
    );

Student _student(String uid, {String name = '云端学生'}) => Student(
  id: 1,
  uid: uid,
  name: name,
  gender: '男',
  group: '1',
  className: '1',
  exist: true,
  rev: 1,
  revBy: 'dev-b',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  isolateDataServiceDir();

  setUp(() async {
    clearTestDataDir();
    DataService.resetWorkspaceToGuest();
    SharedPreferences.setMockInitialValues({});
  });

  AppProvider providerFor(FakeCloudApi api, MemorySyncLocalStore store) =>
      AppProvider(
        cloudSyncService: CloudSyncService(
          api: api,
          store: store,
          deviceId: 'dev-a',
        ),
      );

  test('新增学生分配 uid/rev/revBy 并持久化脏标记', () async {
    final store = MemorySyncLocalStore();
    final provider = providerFor(FakeCloudApi(), store);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.addStudentToClass('1', name: '甲', gender: '男', group: '1');

    final student = provider.allStudents.single;
    expect(student.uid, startsWith('dev-a:s'));
    expect(student.rev, greaterThan(0));
    expect(student.revBy, 'dev-a');
    expect(store.state.studentsDirty, isTrue);
    expect(store.state.studentSeq, 1);
  });

  test('编辑递增 rev；删除写墓碑并移除学生', () async {
    final store = MemorySyncLocalStore();
    final provider = providerFor(FakeCloudApi(), store);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.addStudentToClass('1', name: '甲', gender: '男', group: '1');
    final added = provider.allStudents.single;
    final addedRev = added.rev;

    await provider.updateStudentInClass('1', added.id, name: '乙');
    final updated = provider.allStudents.single;
    expect(updated.uid, added.uid);
    expect(updated.rev, greaterThan(addedRev));

    await provider.deleteStudentFromClass('1', updated.id);
    expect(provider.allStudents, isEmpty);
    expect(store.state.studentTombstones[updated.uid]!.rev, updated.rev + 1);
    expect(store.state.studentTombstones[updated.uid]!.by, 'dev-a');
  });

  test('班级重命名保持 uid、递增 rev；删除班级写墓碑', () async {
    final store = MemorySyncLocalStore();
    final provider = providerFor(FakeCloudApi(), store);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.addStudentToClass('1', name: '甲', gender: '男', group: '1');
    await provider.addStudentToClass('1', name: '乙', gender: '女', group: '1');
    final before = {
      for (final student in provider.allStudents) student.uid: student.rev,
    };
    final uids = before.keys.toSet();

    await provider.renameClass('1', '2');
    expect(provider.allStudents.map((s) => s.className).toSet(), {'2'});
    expect(provider.allStudents.map((s) => s.uid).toSet(), uids);
    for (final student in provider.allStudents) {
      expect(student.rev, greaterThan(before[student.uid]!));
    }

    await provider.deleteClass('2');
    expect(provider.allStudents, isEmpty);
    expect(store.state.studentTombstones.keys.toSet(), uids);
  });

  test('pushToCloud 只在学生脏时写 srlite.students', () async {
    final api = FakeCloudApi();
    final store = MemorySyncLocalStore();
    final provider = providerFor(api, store);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.setAuthState(true);
    await provider.addStudentToClass('1', name: '甲', gender: '男', group: '1');
    expect(await provider.pushToCloud(), isTrue);
    expect(api.store['srlite.students'], hasLength(1));
    final writes = api.putCounts['srlite.students'] ?? 0;

    expect(await provider.pushToCloud(), isTrue);
    expect(api.putCounts['srlite.students'], writes, reason: '名单不脏时不应重复整包写入');
  });

  test('拉取云端学生时与本地并集合并，本地学生不被覆盖', () async {
    final api = FakeCloudApi();
    api.store['srlite.sync.v2.registry'] = {'devices': <String, dynamic>{}};
    api.store['srlite.students'] = [
      _student('dev-b:s1', name: '云端学生').toJson(),
    ];
    await DataService().saveStudents([
      Student(
        id: 1,
        uid: 'dev-a:s1',
        name: '本地学生',
        gender: '女',
        group: '1',
        className: '1',
        exist: true,
        rev: 1,
        revBy: 'dev-a',
      ),
    ]);

    final store = MemorySyncLocalStore();
    final provider = providerFor(api, store);
    addTearDown(provider.dispose);
    await provider.ready;
    await provider.setAuthState(true);

    expect(provider.allStudents.map((s) => s.uid).toSet(), {
      'dev-a:s1',
      'dev-b:s1',
    });
    expect(provider.allStudents.map((s) => s.name).toSet(), {'本地学生', '云端学生'});
    expect(api.store['srlite.students'], hasLength(2));
  });

  test('离线清空保留 clearsDirty，登录后补传清空文档', () async {
    final api = FakeCloudApi();
    final store = MemorySyncLocalStore();
    await DataService().addHistoryRecord(_record('旧记录'));

    final provider = providerFor(api, store);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.clearHistory();
    expect(provider.history, isEmpty);
    expect(store.state.clearsDirty, isTrue);
    expect(api.store.containsKey('srlite.clear.v2'), isFalse);

    await provider.setAuthState(true);
    final clear = api.store['srlite.clear.v2'] as Map<String, dynamic>;
    expect(clear['rollcall']['all'], isNotNull);
    expect(store.state.clearsDirty, isFalse);
  });

  test('拉取云端清空后删除本地旧记录并清理 outbox', () async {
    final api = FakeCloudApi();
    api.store['srlite.sync.v2.registry'] = {'devices': <String, dynamic>{}};
    api.store['srlite.clear.v2'] = {
      'rollcall': {
        'all': '2026-06-01T00:00:00.000',
        'classes': <String, dynamic>{},
      },
    };

    final store = MemorySyncLocalStore();
    final provider = providerFor(api, store);
    addTearDown(provider.dispose);
    await provider.ready;

    final old = _record('旧记录');
    await DataService().addHistoryRecord(old);
    await provider.cloudSyncService.enqueueRecord('rollcall', old.toJson());
    await provider.reloadData();
    expect(provider.history, hasLength(1));

    await provider.setAuthState(true);

    expect(provider.history, isEmpty);
    expect(store.outbox.rollcall, isEmpty);
  });
}
