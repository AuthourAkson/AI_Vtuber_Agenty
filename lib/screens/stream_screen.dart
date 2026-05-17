import 'package:flutter/material.dart';
import '../app.dart';

class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stream & YouTube Chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),

          // YouTube stream ID
          const Text('YouTube Stream ID', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Enter YouTube live stream ID or URL',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Color(0xFF1E1E1E),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_circle, size: 18),
              label: const Text('Connect to Live Chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text('Live Chat Messages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          // Chat message area
          Container(
            height: 400,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: const Center(
              child: Text('Not connected to stream', style: TextStyle(color: Color(0xFF666666))),
            ),
          ),

          const SizedBox(height: 24),
          const Text('Setlist (Karaoke/DJ Mode)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: const Column(
              children: [
                Icon(Icons.queue_music, size: 48, color: Color(0xFF666666)),
                SizedBox(height: 8),
                Text('No items in setlist', style: TextStyle(color: Color(0xFF888888))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
