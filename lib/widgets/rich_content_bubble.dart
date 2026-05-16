     1|     1|import 'package:flutter/material.dart';
     2|     2|import 'package:flutter_markdown/flutter_markdown.dart';
     3|     3|import 'package:flutter_math_fork/flutter_math.dart';
     4|     4|import '../app.dart';
     5|     5|
     6|     6|/// Renders chat content with:
     7|     7|/// - Code blocks (native MarkdownBody dark theme styling)
     8|     8|/// - LaTeX math ($...$ inline, $$...$$ display)
     9|     9|/// - Chemical formulas (\ce{...} → auto-converted to subscripts/superscripts)
    10|    10|/// - Standard markdown (bold, italic, lists, links)
    11|    11|class RichContentBubble extends StatelessWidget {
    12|    12|  final String content;
    13|    13|  final bool isUser;
    14|    14|
    15|    15|  const RichContentBubble({
    16|    16|    super.key,
    17|    17|    required this.content,
    18|    18|    required this.isUser,
    19|    19|  });
    20|    20|
    21|    21|  // Match $$...$$ (display) and $...$ (inline)
    22|    22|  static final _latexRe = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$');
    23|    23|
    24|    24|  @override
    25|    25|  Widget build(BuildContext context) {
    26|    26|    final segments = _splitLatex(content);
    27|    27|
    28|    28|    if (segments.length == 1 && segments.first is! _MathSeg) {
    29|    29|      return _md(content);
    30|    30|    }
    31|    31|
    32|    32|    return Column(
    33|    33|      crossAxisAlignment: CrossAxisAlignment.start,
    34|    34|      mainAxisSize: MainAxisSize.min,
    35|    35|      children: segments.map((seg) {
    36|    36|        if (seg is _MathSeg) {
    37|    37|          return Padding(
    38|    38|            padding: EdgeInsets.symmetric(vertical: seg.display ? 8 : 2),
    39|    39|            child: Math.tex(
    40|    40|              seg.expr,
    41|    41|              textStyle: TextStyle(
    42|    42|                fontSize: seg.display ? 15 : 13,
    43|    43|                color: isUser
    44|    44|                    ? ShadTheme.of(context).secondaryForeground.withAlpha(204)
    45|    45|                    : ShadTheme.of(context).secondaryForeground,
    46|    46|              ),
    47|    47|              mathStyle: seg.display ? MathStyle.display : MathStyle.text,
    48|    48|            ),
    49|    49|          );
    50|    50|        }
    51|    51|        return _md((seg as _TextSeg).text);
    52|    52|      }).toList(),
    53|    53|    );
    54|    54|  }
    55|    55|
    56|    56|  Widget _md(String text) {
    57|    57|    final textColor = isUser
    58|    58|        ? ShadTheme.of(context).secondaryForeground.withAlpha(204)
    59|    59|        : ShadTheme.of(context).secondaryForeground;
    60|    60|
    61|    61|    return MarkdownBody(
    62|    62|      data: text,
    63|    63|      shrinkWrap: true,
    64|    64|      styleSheet: MarkdownStyleSheet(
    65|    65|        p: TextStyle(fontSize: 13, color: textColor, height: 1.5, fontWeight: FontWeight.w500),
    66|    66|        code: const TextStyle(
    67|    67|          fontSize: 12, fontFamily: 'monospace', color: Color(0xFFE6DB74),
    68|    68|        ),
    69|    69|        codeblockDecoration: BoxDecoration(
    70|    70|          color: const Color(0xFF111111),
    71|    71|          borderRadius: BorderRadius.circular(6),
    72|    72|          border: Border.all(color: ShadTheme.of(context).border),
    73|    73|        ),
    74|    74|        codeblockPadding: const EdgeInsets.all(12),
    75|    75|        h1: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ShadTheme.of(context).foreground),
    76|    76|        h2: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: ShadTheme.of(context).foreground),
    77|    77|        blockquoteDecoration: const BoxDecoration(
    78|    78|          border: Border(left: BorderSide(color: ShadTheme.of(context).ring, width: 2)),
    79|    79|        ),
    80|    80|        blockquotePadding: const EdgeInsets.only(left: 10),
    81|    81|        listBullet: TextStyle(color: ShadTheme.of(context).mutedForeground),
    82|    82|      ),
    83|    83|    );
    84|    84|  }
    85|    85|
    86|    86|  List<dynamic> _splitLatex(String text) {
    87|    87|    final parts = <dynamic>[];
    88|    88|    int lastEnd = 0;
    89|    89|
    90|    90|    for (final match in _latexRe.allMatches(text)) {
    91|    91|      if (match.start > lastEnd) {
    92|    92|        parts.add(_TextSeg(text.substring(lastEnd, match.start)));
    93|    93|      }
    94|    94|      if (match.group(1) != null) {
    95|    95|        // $$...$$ display math
    96|    96|        parts.add(_MathSeg(_fixChem(match.group(1)!.trim()), display: true));
    97|    97|      } else if (match.group(2) != null) {
    98|    98|        // $...$ inline math
    99|    99|        parts.add(_MathSeg(_fixChem(match.group(2)!.trim()), display: false));
   100|   100|      }
   101|   101|      lastEnd = match.end;
   102|   102|    }
   103|   103|    if (lastEnd < text.length) {
   104|   104|      parts.add(_TextSeg(text.substring(lastEnd)));
   105|   105|    }
   106|   106|    return parts.isEmpty ? [_TextSeg(text)] : parts;
   107|   107|  }
   108|   108|
   109|   109|  /// Convert \ce{...} to basic LaTeX subscripts/superscripts.
   110|   110|  /// flutter_math_fork doesn't support mhchem, so we preprocess:
   111|   111|  /// \ce{H2O} → H_{2}O, \ce{Na+} → Na^{+}, \ce{SO4^{2-}} → SO_{4}^{2-}
   112|   112|  static final _ceRe = RegExp(r'\\ce\{([^}]+)\}');
   113|   113|
   114|   114|  static String _fixChem(String expr) {
   115|   115|    return expr.replaceAllMapped(_ceRe, (m) {
   116|   116|      var formula = m.group(1)!;
   117|   117|      // Insert _ before numbers, ^ before +/-
   118|   118|      // H2O → H_2O, Na+ → Na^+, SO42- → SO_4^{2-}
   119|   119|      final sb = StringBuffer();
   120|   120|      for (int i = 0; i < formula.length; i++) {
   121|   121|        final ch = formula[i];
   122|   122|        if (_isDigit(ch)) {
   123|   123|          // Number → subscript
   124|   124|          if (i == 0 || !_isDigit(formula[i - 1])) {
   125|   125|            sb.write('_{');
   126|   126|          }
   127|   127|          sb.write(ch);
   128|   128|          if (i == formula.length - 1 || !_isDigit(formula[i + 1])) {
   129|   129|            sb.write('}');
   130|   130|          }
   131|   131|        } else if (ch == '+') {
   132|   132|          sb.write('^{+}');
   133|   133|        } else if (ch == '-') {
   134|   134|          sb.write('^{-}');
   135|   135|        } else {
   136|   136|          sb.write(ch);
   137|   137|        }
   138|   138|      }
   139|   139|      return sb.toString();
   140|   140|    });
   141|   141|  }
   142|   142|
   143|   143|  static bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
   144|   144|}
   145|   145|
   146|   146|class _TextSeg { final String text; _TextSeg(this.text); }
   147|   147|class _MathSeg { final String expr; final bool display; _MathSeg(this.expr, {required this.display}); }
   148|   148|