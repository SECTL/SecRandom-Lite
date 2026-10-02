import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';

void main() {
  test('超过最大重试次数放弃后重置计数，后续失败仍有退避预算', () {
    fakeAsync((async) {
      final service = CloudSyncService();
      Future<bool> fail() async => false;

      service.scheduleRetry(fail);
      // 反复推进时间触发整条退避链，直到触发放弃
      for (var i = 0; i < 20 && service.retryCount > 0; i++) {
        async.elapse(const Duration(seconds: 120));
      }
      expect(service.retryCount, 0, reason: '放弃后应重置，避免本会话后续失败被立即跳过');
      expect(service.hasPendingRetry, isFalse);

      // 修复后：新的失败批次仍可正常调度
      service.scheduleRetry(fail);
      expect(service.retryCount, 1);
      expect(service.hasPendingRetry, isTrue);
      service.cancelRetries();
      expect(service.hasPendingRetry, isFalse);
      expect(service.retryCount, 0);
    });
  });
}
