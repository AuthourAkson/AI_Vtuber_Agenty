import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'storage_service.dart';
import '../models/message.dart';

/// Simple local keyword-based memory search.
/// Scans all session files for relevant context.
class MemoryService {
  final StorageService _storage;

  MemoryService(this._storage);

  /// Search session histories for relevant context.
  /// Returns up to [limit] matching document strings.
  Future<List<String>> query(String text, {int limit = 3}) async {
    if (text.trim().isEmpty) return [];

    final keywords = _extractKeywords(text);
    if (keywords.isEmpty) return [];

    final results = <_ScoredDoc>[];
    final sessions = _storage.listSessions();

    for (final session in sessions) {
      final id = session['id'] as String;
      final full = _storage.getSessionFull(id);
      if (full == null) continue;

      final history = full['history'] as List? ?? [];
      int messageIndex = 0;
      for (final msg in history) {
        if (msg is! Map<String, dynamic>) continue;
        final role = msg['role'] as String? ?? '';
        final content = msg['content'] as String? ?? '';
        if (content.isEmpty) continue;

        final score = _scoreDocument(content, keywords);
        if (score > 0) {
          // Include surrounding context (previous + next message)
          final contexts = <String>[];
          if (messageIndex > 0 && history[messageIndex - 1] is Map<String, dynamic>) {
            final prev = history[messageIndex - 1] as Map<String, dynamic>;
            final pc = prev['content'] as String? ?? '';
            if (pc.isNotEmpty) contexts.add('[${prev['role']}]: $pc');
          }
          contexts.add('[$role]: $content');
          if (messageIndex < history.length - 1 && history[messageIndex + 1] is Map<String, dynamic>) {
            final next = history[messageIndex + 1] as Map<String, dynamic>;
            final nc = next['content'] as String? ?? '';
            if (nc.isNotEmpty) contexts.add('[${next['role']}]: $nc');
          }

          results.add(_ScoredDoc(contexts.join('\n'), score));
        }
        messageIndex++;
      }
    }

    // Sort by score descending, take top N
    results.sort((a, b) => b.score.compareTo(a.score));
    final top = results.take(limit).toList();
    final maxScore = top.isNotEmpty ? top.first.score : 1.0;

    // Normalize scores and return
    return top.map((d) {
      final relevance = (d.score / maxScore * 100).round();
      return '[Relevance: $relevance%]\n${d.content}';
    }).toList();
  }

  List<String> _extractKeywords(String text) {
    // Split into words, filter short/common words
    final stopWords = {
      'the', 'is', 'at', 'which', 'on', 'a', 'an', 'and', 'or', 'but',
      'in', 'with', 'to', 'for', 'of', 'that', 'this', 'was', 'are',
      'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did',
      'will', 'would', 'could', 'should', 'may', 'might', 'shall', 'can',
      'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her',
      'us', 'them', 'my', 'your', 'his', 'its', 'our', 'their',
      '嗯', '啊', '哦', '吧', '吗', '呢', '了', '的', '是', '在', '有',
      '不', '也', '就', '都', '和', '与', '或', '但', '很', '要', '会',
      '能', '可以', '如果', '因为', '所以', '虽然', '但是', '而且',
    };
    final words = text
        .split(RegExp(r'[\s,，.。!！?？;；:：\'\"\(\)\[\]【】《》\n\r\t]+'))
        .where((w) => w.length > 1 && !stopWords.contains(w.toLowerCase()))
        .toSet()
        .toList();
    return words;
  }

  double _scoreDocument(String content, List<String> keywords) {
    final lowerContent = content.toLowerCase();
    double score = 0;
    for (final kw in keywords) {
      final lowerKw = kw.toLowerCase();
      int count = 0;
      int idx = 0;
      while ((idx = lowerContent.indexOf(lowerKw, idx)) != -1) {
        count++;
        idx += lowerKw.length;
      }
      score += count * kw.length; // Weight by keyword length
    }
    return score;
  }
}

class _ScoredDoc {
  final String content;
  final double score;
  _ScoredDoc(this.content, this.score);
}
