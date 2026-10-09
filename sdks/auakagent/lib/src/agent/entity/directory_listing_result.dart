/// 目录项信息
class DirectoryItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final String? modified;

  const DirectoryItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  factory DirectoryItem.fromMap(Map<String, dynamic> map) {
    return DirectoryItem(
      name: map['name'] as String,
      path: map['path'] as String,
      isDirectory: map['isDirectory'] as bool,
      size: map['size'] as int?,
      modified: map['modified'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      if (size != null) 'size': size,
      if (modified != null) 'modified': modified,
    };
  }
}

/// 目录列表结果
class DirectoryListingResult {
  final List<DirectoryItem> items;
  final String? error;

  const DirectoryListingResult({
    required this.items,
    this.error,
  });

  factory DirectoryListingResult.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    return DirectoryListingResult(
      items: rawItems
          .map((e) => DirectoryItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      error: map['error'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'items': items.map((e) => e.toMap()).toList(),
      if (error != null) 'error': error,
    };
  }

  @override
  String toString() =>
      'DirectoryListingResult(items: ${items.length}, error: $error)';
}
