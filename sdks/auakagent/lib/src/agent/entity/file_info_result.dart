/// 文件/目录信息结果
class FileInfoResult {
  final bool exists;
  final String? name;
  final String? path;
  final bool isDirectory;
  final int? size;
  final String? modified;
  final String? error;

  const FileInfoResult({
    required this.exists,
    this.name,
    this.path,
    this.isDirectory = false,
    this.size,
    this.modified,
    this.error,
  });

  factory FileInfoResult.fromMap(Map<String, dynamic> map) {
    return FileInfoResult(
      exists: map['exists'] as bool? ?? false,
      name: map['name'] as String?,
      path: map['path'] as String?,
      isDirectory: map['isDirectory'] as bool? ?? false,
      size: map['size'] as int?,
      modified: map['modified'] as String?,
      error: map['error'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'exists': exists,
      if (name != null) 'name': name,
      if (path != null) 'path': path,
      'isDirectory': isDirectory,
      if (size != null) 'size': size,
      if (modified != null) 'modified': modified,
      if (error != null) 'error': error,
    };
  }

  @override
  String toString() =>
      'FileInfoResult(exists: $exists, isDirectory: $isDirectory, name: $name)';
}
