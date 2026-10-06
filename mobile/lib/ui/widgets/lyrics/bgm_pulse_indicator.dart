import 'package:flutter/material.dart';

class BgmPulseIndicator extends StatefulWidget {
  final bool isActive;
  const BgmPulseIndicator({super.key, required this.isActive});

  @override
  State<BgmPulseIndicator> createState() => _BgmPulseIndicatorState();
}

class _BgmPulseIndicatorState extends State<BgmPulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final scale = widget.isActive ? (0.85 + _anim.value * 0.25) : 0.8;
        return Opacity(
          opacity: widget.isActive ? (0.6 + _anim.value * 0.4) : 0.25,
          child: Transform.scale(
            scale: scale,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(),
                const SizedBox(width: 6),
                _dot(),
                const SizedBox(width: 6),
                _dot(),
                const SizedBox(width: 8),
                Icon(
                  Icons.music_note_rounded,
                  size: 18,
                  color: widget.isActive ? const Color(0xFF06B6D4) : Colors.white38,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dot() {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isActive ? const Color(0xFF06B6D4) : Colors.white38,
      ),
    );
  }
}
