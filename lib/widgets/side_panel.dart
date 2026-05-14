import 'package:flutter/material.dart';
import '../app.dart';

/// Sliding side panel matching LocalAIVtuber2's SidePanel component.
/// Slides in from left or right, with a toggle button on the edge.
/// Uses implicit AnimatedSlide — no manual AnimationController needed.
class SidePanel extends StatefulWidget {
  final Widget child;
  final Side side;
  final double width;
  final bool initiallyOpen;
  final String? openLabel;
  final String? closeLabel;
  final double toggleOffset;

  const SidePanel({
    super.key,
    required this.child,
    this.side = Side.right,
    this.width = 256,
    this.initiallyOpen = false,
    this.openLabel,
    this.closeLabel,
    this.toggleOffset = 20,
  });

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.initiallyOpen;
  }

  void toggle() => setState(() => _isOpen = !_isOpen);

  @override
  Widget build(BuildContext context) {
    final isRight = widget.side == Side.right;

    // Stack requires bounded constraints from parent.
    // Positioned(left, top, bottom) in ChatScreen gives bounded height
    // but unbounded width → wrap in SizedBox to bound width.
    return SizedBox(
      width: widget.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Toggle button — sticks out from the panel edge
          Positioned(
            top: widget.toggleOffset,
            left: isRight ? -20 : null,
            right: isRight ? null : -20,
            child: GestureDetector(
              onTap: toggle,
              child: Container(
                width: 20,
                padding: widget.openLabel != null
                    ? const EdgeInsets.symmetric(vertical: 6, horizontal: 2)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: ShadColors.background,
                  border: Border.all(color: ShadColors.input),
                  borderRadius: BorderRadius.horizontal(
                    left: isRight ? const Radius.circular(4) : Radius.zero,
                    right: isRight ? Radius.zero : const Radius.circular(4),
                  ),
                ),
                child: Center(child: _buildToggleContent(isRight)),
              ),
            ),
          ),
          // The sliding panel — uses implicit AnimatedSlide
          Positioned(
            top: 0,
            bottom: 0,
            left: isRight ? null : 0,
            right: isRight ? 0 : null,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              offset: _isOpen
                  ? Offset.zero
                  : Offset(isRight ? 1.0 : -1.0, 0.0),
              child: Container(
                width: widget.width,
                color: const Color(0xFF151515), // LAV2 side panel bg
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleContent(bool isRight) {
    final label = _isOpen ? widget.openLabel : widget.closeLabel;

    if (label != null) {
      return RotatedBox(
        quarterTurns: 1,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: ShadColors.mutedForeground,
            letterSpacing: 1,
          ),
        ),
      );
    }

    final icon = _isOpen
        ? (isRight ? Icons.chevron_right : Icons.chevron_left)
        : (isRight ? Icons.chevron_left : Icons.chevron_right);

    return Icon(icon, size: 14, color: ShadColors.mutedForeground);
  }
}

/// Convenience enum for SidePanel
enum Side { left, right }
