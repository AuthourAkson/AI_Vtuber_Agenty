/// Represents a single chat history item
class HistoryItem {
  final String role; // "user" or "assistant"
  final String content;

  const HistoryItem({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory HistoryItem.fromJson(Map<String, dynamic> json) =>
      HistoryItem(role: json['role'] as String, content: json['content'] as String);
}

/// A chat session stored on the backend
class Session {
  final String id;
  final String title;
  final String createdAt;
  final List<HistoryItem> history;
  final bool? indexed;

  const Session({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.history,
    this.indexed,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: json['created_at'] as String,
    history: (json['history'] as List)
        .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    indexed: json['indexed'] as bool?,
  );
}
