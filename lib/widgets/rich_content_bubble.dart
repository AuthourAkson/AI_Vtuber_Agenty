import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../app.dart';

/// Renders chat content with:
/// - Code blocks (native MarkdownBody dark theme styling)
/// - LaTeX math ($...$ inline, $$...$$ display)
/// - Chemical formulas (\ce{...} → auto-converted to subscripts/superscripts)
/// - Standard markdown (bold, italic, lists, links)
class RichContentBubble extends StatelessWidget {
final String content;
final bool isUser;

const RichContentBubble({
super.key,
required this.content,
required this.isUser,
});

// Match $$...$$ (display) and $...$ (inline)
static final _latexRe = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$');

@override
Widget build(BuildContext context) {
final segments = _splitLatex(content);

if (segments.length == 1 && segments.first is! _MathSeg) {
return _md(content);
}

return Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: segments.map((seg) {
if (seg is _MathSeg) {
return Padding(
padding: EdgeInsets.symmetric(vertical: seg.display ? 8 : 2),
child: Math.tex(
seg.expr,
textStyle: TextStyle(
fontSize: seg.display ? 15 : 13,
color: isUser
? ShadTheme.of(context).secondaryForeground.withAlpha(204)
: ShadTheme.of(context).secondaryForeground,
),
mathStyle: seg.display ? MathStyle.display : MathStyle.text,
),
);
}
return _md((seg as _TextSeg).text);
}).toList(),
);
}

Widget _md(String text) {
final textColor = isUser
? ShadTheme.of(context).secondaryForeground.withAlpha(204)
: ShadTheme.of(context).secondaryForeground;

return MarkdownBody(
data: text,
shrinkWrap: true,
styleSheet: MarkdownStyleSheet(
p: TextStyle(fontSize: 13, color: textColor, height: 1.5, fontWeight: FontWeight.w500),
code: const TextStyle(
fontSize: 12, fontFamily: 'monospace', color: Color(0xFFE6DB74),
),
codeblockDecoration: BoxDecoration(
color: const Color(0xFF111111),
borderRadius: BorderRadius.circular(6),
border: Border.all(color: ShadTheme.of(context).border),
),
codeblockPadding: const EdgeInsets.all(12),
h1: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ShadTheme.of(context).foreground),
h2: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: ShadTheme.of(context).foreground),
blockquoteDecoration: const BoxDecoration(
border: Border(left: BorderSide(color: ShadTheme.of(context).ring, width: 2)),
),
blockquotePadding: const EdgeInsets.only(left: 10),
listBullet: TextStyle(color: ShadTheme.of(context).mutedForeground),
),
);
}

List<dynamic> _splitLatex(String text) {
final parts = <dynamic>[];
int lastEnd = 0;

for (final match in _latexRe.allMatches(text)) {
if (match.start > lastEnd) {
parts.add(_TextSeg(text.substring(lastEnd, match.start)));
}
if (match.group(1) != null) {
// $$...$$ display math
parts.add(_MathSeg(_fixChem(match.group(1)!.trim()), display: true));
} else if (match.group(2) != null) {
// $...$ inline math
parts.add(_MathSeg(_fixChem(match.group(2)!.trim()), display: false));
}
lastEnd = match.end;
}
if (lastEnd < text.length) {
parts.add(_TextSeg(text.substring(lastEnd)));
}
return parts.isEmpty ? [_TextSeg(text)] : parts;
}

/// Convert \ce{...} to basic LaTeX subscripts/superscripts.
/// flutter_math_fork doesn't support mhchem, so we preprocess:
/// \ce{H2O} → H_{2}O, \ce{Na+} → Na^{+}, \ce{SO4^{2-}} → SO_{4}^{2-}
static final _ceRe = RegExp(r'\\ce\{([^}]+)\}');

static String _fixChem(String expr) {
return expr.replaceAllMapped(_ceRe, (m) {
var formula = m.group(1)!;
// Insert _ before numbers, ^ before +/-
// H2O → H_2O, Na+ → Na^+, SO42- → SO_4^{2-}
final sb = StringBuffer();
for (int i = 0; i < formula.length; i++) {
final ch = formula[i];
if (_isDigit(ch)) {
// Number → subscript
if (i == 0 || !_isDigit(formula[i - 1])) {
sb.write('_{');
}
sb.write(ch);
if (i == formula.length - 1 || !_isDigit(formula[i + 1])) {
sb.write('}');
}
} else if (ch == '+') {
sb.write('^{+}');
} else if (ch == '-') {
sb.write('^{-}');
} else {
sb.write(ch);
}
}
return sb.toString();
});
}

static bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
}

class _TextSeg { final String text; _TextSeg(this.text); }
class _MathSeg { final String expr; final bool display; _MathSeg(this.expr, {required this.display}); }
