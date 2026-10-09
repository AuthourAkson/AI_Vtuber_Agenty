/// 路径存在检查结果
class PathExistsResult {
  final bool exists;
  final bool isDirectory;
  final String? error;

  const PathExistsResult({
    required this.exists,
    required this.isDirectory,
    this.error,
  });

  factory PathExistsResult.fromMap(Map<String, dynamic> map) {
    return PathExistsResult(
      exists: map['exists'] as bool? ?? false,
      isDirectory: map['isDirectory'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'exists': exists,
      'isDirectory': isDirectory,
      if (error != null) 'error': error,
    };
  }

  @override
  String toString() =>
      'PathExistsResult(exists: $exists, isDirectory: $isDirectory)';
}
