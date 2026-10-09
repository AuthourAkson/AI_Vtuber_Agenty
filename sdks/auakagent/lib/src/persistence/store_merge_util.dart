/// 通用 Store Merge 工具方法
///
/// 提供跨设备数据同步时的 merge 逻辑，被 SpecStore、TodoStore、
/// DataSyncManager、HostRpcMethods 等复用。

/// 软删除合并结果
class MergeDeleteResult {
  /// 合并后的 deleteTime（null 表示未删除）
  final DateTime? mergedDeleteTime;

  /// 合并后的 deleted 标志（0=未删除, 1=已删除）
  final int mergedDeleted;

  const MergeDeleteResult({
    required this.mergedDeleteTime,
    required this.mergedDeleted,
  });
}

class StoreMergeUtil {
  /// 软删除合并逻辑
  ///
  /// 规则：
  /// - 双方都无 deleteTime → 未删除
  /// - 单侧有 deleteTime → 采用有 deleteTime 的一方
  /// - 双方都有 deleteTime → 取 deleteTime 更大的一方决定 deleted 状态
  /// - [新增] 远程明确复活（deleted=0, deleteTime=null）且 updateTime 更新 → 允许复活
  static MergeDeleteResult mergeDeleteState({
    required DateTime? localDeleteTime,
    required int localDeleted,
    required DateTime? remoteDeleteTime,
    required int remoteDeleted,
    DateTime? localUpdateTime,
    DateTime? remoteUpdateTime,
  }) {
    // 双方都未删除
    if (localDeleteTime == null && remoteDeleteTime == null) {
      return const MergeDeleteResult(mergedDeleteTime: null, mergedDeleted: 0);
    }

    // [新增] 远程明确复活（deleted=0, deleteTime=null）且远程数据更新
    // 当远程 updateTime > 本地 updateTime 时，远程的复活操作应该覆盖本地的删除
    if (remoteDeleteTime == null &&
        remoteDeleted == 0 &&
        localDeleteTime != null &&
        localDeleted == 1 &&
        localUpdateTime != null &&
        remoteUpdateTime != null &&
        remoteUpdateTime.isAfter(localUpdateTime)) {
      return const MergeDeleteResult(mergedDeleteTime: null, mergedDeleted: 0);
    }

    // [新增] 对称：本地明确复活且本地数据更新 → 保持本地复活
    if (localDeleteTime == null &&
        localDeleted == 0 &&
        remoteDeleteTime != null &&
        remoteDeleted == 1 &&
        localUpdateTime != null &&
        remoteUpdateTime != null &&
        localUpdateTime.isAfter(remoteUpdateTime)) {
      return const MergeDeleteResult(mergedDeleteTime: null, mergedDeleted: 0);
    }

    if (localDeleteTime == null) {
      return MergeDeleteResult(
          mergedDeleteTime: remoteDeleteTime, mergedDeleted: remoteDeleted);
    }
    if (remoteDeleteTime == null) {
      return MergeDeleteResult(
          mergedDeleteTime: localDeleteTime, mergedDeleted: localDeleted);
    }
    // 双方都有 deleteTime → 取更大的
    if (localDeleteTime.isAfter(remoteDeleteTime)) {
      return MergeDeleteResult(
          mergedDeleteTime: localDeleteTime, mergedDeleted: localDeleted);
    } else {
      return MergeDeleteResult(
          mergedDeleteTime: remoteDeleteTime, mergedDeleted: remoteDeleted);
    }
  }

  /// 判断数据是否需要更新（基于 updateTime）
  ///
  /// 远程 updateTime > 本地 updateTime → 需要更新
  static bool shouldUpdateData(
      DateTime? localUpdateTime, DateTime? remoteUpdateTime) {
    if (localUpdateTime == null || remoteUpdateTime == null) return true;
    return remoteUpdateTime.isAfter(localUpdateTime);
  }
}
