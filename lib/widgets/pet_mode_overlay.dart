import 'package:flutter/material.dart';
import '../widgets/live2d_view.dart';

/// Full-screen transparent overlay for desktop pet mode.
/// Hides all app UI, shows only the Live2D character.
class PetModeOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Live2D character — full screen, transparent background
          Live2DView(
            modelPath: modelPath,
            positionX: positionX,
            positionY: positionY,
            scale: scale,
            interactive: true,
          ),

          // Exit button — top right, subtle
          Positioned(
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: onExit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 14, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('Exit Pet Mode',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),

          // Hint text
          const Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Right-click character → chat dialog  |  Move mouse → eye tracking',
                style: TextStyle(color: Color(0x44FFFFFF), fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
