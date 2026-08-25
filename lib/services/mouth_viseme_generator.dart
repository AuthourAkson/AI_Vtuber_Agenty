import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;

/// TTS-agnostic A/I/U/E/O mouth viseme timeline generator.
///
/// The algorithm is a compact port of MMD-Mouth-BlenderScript's core ideas:
///   - text -> phonemes (Chinese via bundled pinyin initial/final map;
///     English/Japanese use lightweight fallbacks)
///   - phonemes -> consonant-aware viseme events (bilabial p/b/m closes mouth,
///     consonants suppress vowels)
///   - events -> 30 fps A/I/U/E/O channel samples with attack/release envelopes.
///
/// Every TTS provider (Edge-TTS, GPT-SoVITS, ...) only needs to supply:
///   - the exact text that was spoken
///   - audio duration in seconds
///   - optional word-level timings when available (Edge-TTS subtitles etc.)
class MouthVisemeGenerator {
  MouthVisemeGenerator._();
  static final MouthVisemeGenerator instance = MouthVisemeGenerator._();

  Map<String, List<String>>? _pinyinMap;

  static const double _attackMs = 70.0;
  static const double _releaseMs = 90.0;

  Future<Map<String, List<String>>> _loadPinyinMap() async {
    final cached = _pinyinMap;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString('assets/data/pinyin_map.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = decoded.map(
        (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
      );
      _pinyinMap = map;
      return map;
    } catch (_) {
      _pinyinMap = {};
      return _pinyinMap!;
    }
  }

  /// Generate sampled viseme frames at 30 fps.
  /// [words] optional: [{text, startSec, endSec}]. When absent, timing is
  /// estimated from text length / audio duration.
  Future<List<MouthVisemeFrame>> generate({
    required String text,
    required double durationSec,
    String language = 'zh-CN',
    List<Map<String, dynamic>>? words,
  }) async {
    if (text.trim().isEmpty || durationSec <= 0) return [];

    final phonemes = await _phonemize(text, language, durationSec, words);
    final events = _buildEvents(phonemes);
    final frames = _sample(events, durationSec, 30);
    return frames;
  }

  // ── 1. Text -> phoneme segments with timings ──────────────────

  Future<List<_PhoneSeg>> _phonemize(
    String text,
    String language,
    double durationSec,
    List<Map<String, dynamic>>? words,
  ) async {
    final family = language.toLowerCase().split('-').first;
    final pinyinMap = await _loadPinyinMap();

    final wordSegs = words != null && words.isNotEmpty
        ? _wordsFromInput(words)
        : _estimateWords(text, family, durationSec);

    if (wordSegs.isEmpty) return [];

    final segments = <_PhoneSeg>[];
    for (final w in wordSegs) {
      final tokens = family == 'zh'
          ? _chineseTokens(w.text, pinyinMap)
          : _latinTokens(w.text);
      if (tokens.isEmpty) continue;
      final weights = tokens.map(_phoneWeight).toList();
      final totalWeight = weights.fold<double>(0, (a, b) => a + b);
      final duration = math.max(0.001, w.endSec - w.startSec);
      var cursor = w.startSec;
      for (var i = 0; i < tokens.length; i++) {
        final end = i == tokens.length - 1
            ? w.endSec
            : cursor + duration * weights[i] / totalWeight;
        final phone = tokens[i];
        segments.add(
          _PhoneSeg(
            ipa: phone.ipa,
            source: phone.source,
            startSec: cursor,
            endSec: math.max(cursor, end),
            viseme: _visemeForIpa(phone.ipa),
            closeStrength: _closeStrength(phone.ipa),
            vowelSuppression: _vowelSuppression(phone.ipa),
          ),
        );
        cursor = end;
      }
    }
    return segments;
  }

  List<_WordSeg> _wordsFromInput(List<Map<String, dynamic>> words) {
    final out = <_WordSeg>[];
    for (final w in words) {
      final text = w['text']?.toString() ?? '';
      final start =
          (w['startSec'] as num?)?.toDouble() ??
          (w['start'] as num?)?.toDouble() ??
          0.0;
      final end =
          (w['endSec'] as num?)?.toDouble() ??
          (w['end'] as num?)?.toDouble() ??
          start;
      if (text.isNotEmpty && end > start) out.add(_WordSeg(text, start, end));
    }
    return out;
  }

  List<_WordSeg> _estimateWords(
    String text,
    String family,
    double durationSec,
  ) {
    // Chinese: every CJK char is its own timing unit; non-CJK runs group
    // together. Japanese: one kana/kanji per unit. Others: whitespace words.
    final units = <String>[];
    if (family == 'zh') {
      final buffer = StringBuffer();
      for (final ch in text.split('')) {
        if (_isCjk(ch)) {
          if (buffer.isNotEmpty) {
            units.add(buffer.toString());
            buffer.clear();
          }
          units.add(ch);
        } else if (ch.trim().isNotEmpty) {
          buffer.write(ch);
        } else if (buffer.isNotEmpty) {
          units.add(buffer.toString());
          buffer.clear();
        }
      }
      if (buffer.isNotEmpty) units.add(buffer.toString());
    } else if (family == 'ja') {
      for (final ch in text.split('')) {
        if (ch.trim().isNotEmpty) units.add(ch);
      }
    } else {
      units.addAll(text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty));
    }
    if (units.isEmpty) return [];

    // Weighted by phone weight; CJK each char gets similar timing, Latin
    // words get weight proportional to char count + 1.
    final weights = units.map((u) {
      if (_isCjk(u)) return 1.0;
      return 0.7 + u.length * 0.3;
    }).toList();
    final total = weights.fold<double>(0, (a, b) => a + b);
    var cursor = 0.0;
    final out = <_WordSeg>[];
    for (var i = 0; i < units.length; i++) {
      final w = total <= 0
          ? durationSec / units.length
          : durationSec * weights[i] / total;
      final end = i == units.length - 1 ? durationSec : cursor + w;
      out.add(_WordSeg(units[i], cursor, math.max(cursor, end)));
      cursor = end;
    }
    return out;
  }

  // ── 2. Language-specific tokenization ─────────────────────────

  bool _isCjk(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FA5) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }

  List<_PhoneTok> _chineseTokens(
    String text,
    Map<String, List<String>> pinyinMap,
  ) {
    final out = <_PhoneTok>[];
    final chars = text.split('');
    for (final ch in chars) {
      if (_isCjk(ch)) {
        final pinyin = pinyinMap[ch];
        if (pinyin != null && pinyin.length >= 2) {
          final initial = pinyin[0];
          final finalPart = pinyin[1];
          final ipa = initial.isNotEmpty ? _initialIpa[initial] : null;
          if (ipa != null) out.add(_PhoneTok(ch, ipa));
          final finals =
              _finalIpa[finalPart] ?? (finalPart.isEmpty ? null : [finalPart]);
          if (finals != null) {
            for (final f in finals) {
              out.add(_PhoneTok(ch, f));
            }
          }
        } else {
          // Fallback: treat unknown CJK char as an open A-ish vowel.
          out.add(_PhoneTok(ch, 'a'));
        }
      } else {
        out.addAll(_latinTokens(ch));
      }
    }
    return out;
  }

  List<_PhoneTok> _latinTokens(String text) {
    final out = <_PhoneTok>[];
    final lower = text.toLowerCase();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      if (RegExp(r'[a-z]').hasMatch(ch)) {
        out.add(_PhoneTok(ch, _englishFallbackIpa(ch)));
      }
    }
    return out;
  }

  // ── 3. IPA -> viseme features ─────────────────────────────────

  static const Map<String, String> _initialIpa = {
    'b': 'p',
    'p': 'pʰ',
    'm': 'm',
    'f': 'f',
    'd': 't',
    't': 'tʰ',
    'n': 'n',
    'l': 'l',
    'g': 'k',
    'k': 'kʰ',
    'h': 'x',
    'j': 'tɕ',
    'q': 'tɕʰ',
    'x': 'ɕ',
    'zh': 'tʃ',
    'ch': 'tʃʰ',
    'sh': 'ʂ',
    'r': 'ɻ',
    'z': 'ts',
    'c': 'tsʰ',
    's': 's',
  };

  static const Map<String, List<String>> _finalIpa = {
    'a': ['a'],
    'o': ['o'],
    'e': ['ɤ'],
    'i': ['i'],
    'u': ['u'],
    'v': ['y'],
    'ei': ['e', 'i'],
    'ao': ['a', 'o'],
    'ou': ['o', 'u'],
    'an': ['a', 'n'],
    'en': ['ə', 'n'],
    'ang': ['a', 'ŋ'],
    'eng': ['ə', 'ŋ'],
    'ong': ['o', 'ŋ'],
    'ia': ['j', 'a'],
    'ie': ['j', 'e'],
    'iao': ['j', 'a', 'o'],
    'iu': ['j', 'o', 'u'],
    'ian': ['j', 'e', 'n'],
    'in': ['i', 'n'],
    'iang': ['j', 'a', 'ŋ'],
    'ing': ['i', 'ŋ'],
    'iong': ['j', 'o', 'ŋ'],
    'ua': ['w', 'a'],
    'uo': ['w', 'o'],
    'uai': ['w', 'a', 'i'],
    'ui': ['w', 'e', 'i'],
    'uan': ['w', 'a', 'n'],
    'un': ['w', 'ə', 'n'],
    'uang': ['w', 'a', 'ŋ'],
    'ueng': ['w', 'ə', 'ŋ'],
    've': ['y', 'e'],
    'van': ['y', 'e', 'n'],
    'vn': ['y', 'n'],
    'er': ['ə', 'r'],
  };

  String _visemeForIpa(String ipa) {
    if ('aɑɐæʌ'.contains(ipa)) return 'A';
    if ('eɛəɜɘ'.contains(ipa)) return 'E';
    if ('iɪ'.contains(ipa)) return 'I';
    if ('oɔɒøœ'.contains(ipa)) return 'O';
    if ('uʊɯɤyʏ'.contains(ipa)) return 'U';
    if ('pbmɸβfv'.contains(ipa)) return 'CLOSED';
    return 'REST';
  }

  double _closeStrength(String ipa) {
    if ('pbm'.contains(ipa)) return 1.0;
    if ('ɸβ'.contains(ipa)) return 0.55;
    if ('fv'.contains(ipa)) return 0.35;
    return 0.0;
  }

  double _vowelSuppression(String ipa) {
    if ('pbm'.contains(ipa)) return 1.0;
    if ('ɸβ'.contains(ipa)) return 0.7;
    if ('fv'.contains(ipa)) return 0.55;
    if ('tdnl'.contains(ipa)) return 0.35;
    if ('sθð'.contains(ipa)) return 0.15;
    return 0.0;
  }

  String _englishFallbackIpa(String ch) {
    const map = {
      'a': 'æ',
      'e': 'e',
      'i': 'ɪ',
      'o': 'o',
      'u': 'ʌ',
      'b': 'b',
      'c': 'k',
      'd': 'd',
      'f': 'f',
      'g': 'g',
      'h': 'h',
      'j': 'dʒ',
      'k': 'k',
      'l': 'l',
      'm': 'm',
      'n': 'n',
      'p': 'p',
      'q': 'k',
      'r': 'ɹ',
      's': 's',
      't': 't',
      'v': 'v',
      'w': 'w',
      'x': 'k',
      'y': 'j',
      'z': 'z',
    };
    return map[ch] ?? '';
  }

  double _phoneWeight(_PhoneTok token) {
    final vis = _visemeForIpa(token.ipa);
    if (vis == 'A' || vis == 'E' || vis == 'I' || vis == 'O' || vis == 'U') {
      return 1.6;
    }
    if (token.ipa == 'p' || token.ipa == 'b' || token.ipa == 'm') {
      return 0.55;
    }
    return 0.75;
  }

  // ── 4. Events + envelope sampling (port of timeline.py) ──────

  List<_VisemeEvent> _buildEvents(List<_PhoneSeg> phonemes) {
    final events = <_VisemeEvent>[];
    for (var i = 0; i < phonemes.length; i++) {
      final p = phonemes[i];
      if (p.viseme == 'CLOSED' && p.closeStrength > 0) {
        events.add(
          _VisemeEvent('CLOSED', p.startSec, p.endSec, p.closeStrength, 100),
        );
        continue;
      }
      if (p.viseme == 'A' ||
          p.viseme == 'E' ||
          p.viseme == 'I' ||
          p.viseme == 'O' ||
          p.viseme == 'U') {
        final weight = _isVowelIpa(p.ipa) ? 1.0 : 0.65;
        events.add(_VisemeEvent(p.viseme, p.startSec, p.endSec, weight, 50));
      }
      if (p.vowelSuppression > 0) {
        events.add(
          _VisemeEvent('REST', p.startSec, p.endSec, p.vowelSuppression, 80),
        );
      }
    }
    events.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return b.priority.compareTo(a.priority);
    });
    return events;
  }

  bool _isVowelIpa(String ipa) {
    return 'aɑɐæʌeɛəɜɘiɪoɔɒøœuʊɯɤyʏ'.contains(ipa);
  }

  List<MouthVisemeFrame> _sample(
    List<_VisemeEvent> events,
    double durationSec,
    int fps,
  ) {
    final attackSec = _attackMs / 1000.0;
    final releaseSec = _releaseMs / 1000.0;
    final frameCount = math.max(1, (durationSec * fps).ceil());
    final frames = <MouthVisemeFrame>[];
    for (var f = 0; f <= frameCount; f++) {
      final t = f / fps;
      final values = _evaluate(events, t, attackSec, releaseSec);
      frames.add(
        MouthVisemeFrame(
          t: t,
          a: values['A'] ?? 0,
          i: values['I'] ?? 0,
          u: values['U'] ?? 0,
          e: values['E'] ?? 0,
          o: values['O'] ?? 0,
        ),
      );
    }
    return frames;
  }

  Map<String, double> _evaluate(
    List<_VisemeEvent> events,
    double t,
    double attackSec,
    double releaseSec,
  ) {
    final values = <String, double>{
      'A': 0,
      'I': 0,
      'U': 0,
      'E': 0,
      'O': 0,
      'REST': 0,
      'CLOSED': 0,
    };
    for (final e in events) {
      final v = _envelope(e, t, attackSec, releaseSec);
      values[e.viseme] = math.max(values[e.viseme] ?? 0, v);
    }
    final suppression = math.max(values['REST'] ?? 0, values['CLOSED'] ?? 0);
    for (final ch in ['A', 'I', 'U', 'E', 'O']) {
      values[ch] = (values[ch] ?? 0) * (1.0 - suppression);
    }
    final active = [
      'A',
      'I',
      'U',
      'E',
      'O',
    ].where((c) => (values[c] ?? 0) > 0).toList();
    final total = active.fold<double>(0, (a, c) => a + (values[c] ?? 0));
    if (active.length > 1 && total > 0) {
      for (final c in active) {
        values[c] = (values[c] ?? 0) / total;
      }
    }
    return values;
  }

  double _envelope(
    _VisemeEvent e,
    double t,
    double attackSec,
    double releaseSec,
  ) {
    final duration = e.end - e.start;
    if (duration <= 0) return t == e.start ? e.weight : 0.0;

    // Smoothstep attack/release that may extend outside the event.
    final activeStart = e.start - attackSec;
    final activeEnd = e.end + releaseSec;
    if (t < activeStart || t > activeEnd) return 0.0;
    if (attackSec > 0 && t < e.start) {
      final x = (t - activeStart) / attackSec;
      return e.weight * x * x * (3 - 2 * x);
    }
    if (releaseSec > 0 && t > e.end) {
      final x = (t - e.end) / releaseSec;
      return e.weight * (1 - x * x * (3 - 2 * x));
    }
    return e.weight;
  }
}

class MouthVisemeFrame {
  final double t;
  final double a;
  final double i;
  final double u;
  final double e;
  final double o;

  const MouthVisemeFrame({
    required this.t,
    required this.a,
    required this.i,
    required this.u,
    required this.e,
    required this.o,
  });

  Map<String, dynamic> toJson() => {
    't': t,
    'a': a,
    'i': i,
    'u': u,
    'e': e,
    'o': o,
  };
}

class _PhoneTok {
  final String source;
  final String ipa;
  const _PhoneTok(this.source, this.ipa);
}

class _WordSeg {
  final String text;
  final double startSec;
  final double endSec;
  const _WordSeg(this.text, this.startSec, this.endSec);
}

class _PhoneSeg {
  final String ipa;
  final String source;
  final double startSec;
  final double endSec;
  final String viseme;
  final double closeStrength;
  final double vowelSuppression;
  const _PhoneSeg({
    required this.ipa,
    required this.source,
    required this.startSec,
    required this.endSec,
    required this.viseme,
    required this.closeStrength,
    required this.vowelSuppression,
  });
}

class _VisemeEvent {
  final String viseme;
  final double start;
  final double end;
  final double weight;
  final int priority;
  const _VisemeEvent(
    this.viseme,
    this.start,
    this.end,
    this.weight,
    this.priority,
  );
}
