/// 通用文件操作结果（创建目录、删除、重命名等）
class FileOpResult {
  final bool success;
  final String? error;

  const FileOpResult({required this.success, this.error});

  factory FileOpResult.fromMap(Map<String, dynamic> map) {
    return FileOpResult(
      success: map['success'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      if (error != null) 'error': error,
    };
  }

  @override
  String toString() => 'FileOpResult(success: $success, error: $error)';
}
