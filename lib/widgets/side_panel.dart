     1|import 'package:flutter/material.dart';
     2|import '../app.dart';
     3|
     4|/// Sliding side panel matching LocalAIVtuber2's SidePanel component.
     5|/// Slides in from left or right, with a toggle button on the edge.
     6|/// Uses implicit AnimatedSlide — no manual AnimationController needed.
     7|class SidePanel extends StatefulWidget {
     8|  final Widget child;
     9|  final Side side;
    10|  final double width;
    11|  final bool initiallyOpen;
    12|  final String? openLabel;
    13|  final String? closeLabel;
    14|  final double toggleOffset;
    15|
    16|  const SidePanel({
    17|    super.key,
    18|    required this.child,
    19|    this.side = Side.right,
    20|    this.width = 256,
    21|    this.initiallyOpen = false,
    22|    this.openLabel,
    23|    this.closeLabel,
    24|    this.toggleOffset = 20,
    25|  });
    26|
    27|  @override
    28|  State<SidePanel> createState() => _SidePanelState();
    29|}
    30|
    31|class _SidePanelState extends State<SidePanel> {
    32|  bool _isOpen = false;
    33|
    34|  @override
    35|  void initState() {
    36|    super.initState();
    37|    _isOpen = widget.initiallyOpen;
    38|  }
    39|
    40|  void toggle() => setState(() => _isOpen = !_isOpen);
    41|
    42|  @override
    43|  Widget build(BuildContext context) {
    44|    final isRight = widget.side == Side.right;
    45|
    46|    // Stack requires bounded constraints from parent.
    47|    // Positioned(left, top, bottom) in ChatScreen gives bounded height
    48|    // but unbounded width → wrap in SizedBox to bound width.
    49|    return SizedBox(
    50|      width: widget.width,
    51|      child: Stack(
    52|        clipBehavior: Clip.none,
    53|        children: [
    54|          // Toggle button — sticks out from the panel edge
    55|          Positioned(
    56|            top: widget.toggleOffset,
    57|            left: isRight ? -20 : null,
    58|            right: isRight ? null : -20,
    59|            child: GestureDetector(
    60|              onTap: toggle,
    61|              child: Container(
    62|                width: 20,
    63|                padding: widget.openLabel != null
    64|                    ? const EdgeInsets.symmetric(vertical: 6, horizontal: 2)
    65|                    : EdgeInsets.zero,
    66|                decoration: BoxDecoration(
    67|                  color: ShadTheme.of(context).background,
    68|                  border: Border.all(color: ShadTheme.of(context).input),
    69|                  borderRadius: BorderRadius.horizontal(
    70|                    left: isRight ? const Radius.circular(4) : Radius.zero,
    71|                    right: isRight ? Radius.zero : const Radius.circular(4),
    72|                  ),
    73|                ),
    74|                child: Center(child: _buildToggleContent(isRight)),
    75|              ),
    76|            ),
    77|          ),
    78|          // The sliding panel — uses implicit AnimatedSlide
    79|          Positioned(
    80|            top: 0,
    81|            bottom: 0,
    82|            left: isRight ? null : 0,
    83|            right: isRight ? 0 : null,
    84|            child: AnimatedSlide(
    85|              duration: const Duration(milliseconds: 300),
    86|              curve: Curves.easeInOut,
    87|              offset: _isOpen
    88|                  ? Offset.zero
    89|                  : Offset(isRight ? 1.0 : -1.0, 0.0),
    90|              child: Container(
    91|                width: widget.width,
    92|                color: const Color(0xFF151515), // LAV2 side panel bg
    93|                child: widget.child,
    94|              ),
    95|            ),
    96|          ),
    97|        ],
    98|      ),
    99|    );
   100|  }
   101|
   102|  Widget _buildToggleContent(bool isRight) {
   103|    final label = _isOpen ? widget.openLabel : widget.closeLabel;
   104|
   105|    if (label != null) {
   106|      return RotatedBox(
   107|        quarterTurns: 1,
   108|        child: Text(
   109|          label,
   110|          style: const TextStyle(
   111|            fontSize: 10,
   112|            color: ShadTheme.of(context).mutedForeground,
   113|            letterSpacing: 1,
   114|          ),
   115|        ),
   116|      );
   117|    }
   118|
   119|    final icon = _isOpen
   120|        ? (isRight ? Icons.chevron_right : Icons.chevron_left)
   121|        : (isRight ? Icons.chevron_left : Icons.chevron_right);
   122|
   123|    return Icon(icon, size: 14, color: ShadTheme.of(context).mutedForeground);
   124|  }
   125|}
   126|
   127|/// Convenience enum for SidePanel
   128|enum Side { left, right }
   129|