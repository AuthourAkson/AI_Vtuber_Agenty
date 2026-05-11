import 'package:flutter/material.dart';
import '../widgets/live2d_view.dart';

/// Full-screen transparent overlay for desktop pet mode.
class PetModeOverlay extends StatefulWidget {
  final String modelPath;
  final double positionX;
  final double positionY;
  final double scale;
  final VoidCallback onExit;

  const PetModeOverlay({
    super.key,
    required this.modelPath,
    this.positionX = 46,
    this.positionY = 51,
    this.scale = 0.16,
    required this.onExit,
  });

  @override
  State<PetModeOverlay> createState() => _PetModeOverlayState();
}

class _PetModeOverlayState extends State<PetModeOverlay> {
  final GlobalKey<Live2DViewState> _viewKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Live2DView(
              key: _viewKey,
              modelPath: widget.modelPath,
              positionX: widget.positionX,
              positionY: widget.positionY,
              scale: widget.scale,
              interactive: true,
              onEvent: (event) {
                if (event.type == 'modelLoaded') {
                  _viewKey.currentState?.setMouseTracking(true);
                }
              },
            ),

            Positioned(
              top: 12, right: 12,
              child: GestureDetector(
                onTap: widget.onExit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text('Exit Pet Mode',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
            ),

            const Positioned(
              bottom: 12, left: 0, right: 0,
              child: Center(
                child: Text('Drag to move  |  Right-click → chat  |  Eyes follow mouse',
                  style: TextStyle(color: Color(0x33FFFFFF), fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
