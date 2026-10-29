import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/sleep_timer_service.dart';

class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({Key? key}) : super(key: key);

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SleepTimerSheet(),
    );
  }

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> with SingleTickerProviderStateMixin {
  Duration _selectedDuration = const Duration(minutes: 30);
  bool _isEndOfTrack = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<_SleepPreset> _presets = const [
    _SleepPreset(minutes: 15, title: '15 Min', subtitle: 'Quick Power Nap', icon: Icons.bolt_rounded),
    _SleepPreset(minutes: 30, title: '30 Min', subtitle: 'Recommended', icon: Icons.bedtime_rounded),
    _SleepPreset(minutes: 45, title: '45 Min', subtitle: 'Deep Rest', icon: Icons.nights_stay_rounded),
    _SleepPreset(minutes: 60, title: '1 Hour', subtitle: 'Full Album', icon: Icons.hourglass_top_rounded),
    _SleepPreset(minutes: 90, title: '1.5 Hours', subtitle: 'Extended Session', icon: Icons.snooze_rounded),
    _SleepPreset(minutes: 0, title: 'End of Track', subtitle: 'Finish current song', icon: Icons.music_note_rounded, isEndOfTrack: true),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _selectPreset(_SleepPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      if (preset.isEndOfTrack) {
        _isEndOfTrack = true;
      } else {
        _isEndOfTrack = false;
        _selectedDuration = Duration(minutes: preset.minutes);
      }
    });
  }

  void _adjustSlider(double minutes) {
    HapticFeedback.selectionClick();
    setState(() {
      _isEndOfTrack = false;
      _selectedDuration = Duration(minutes: minutes.round());
    });
  }

  void _stepTime(int minutesDelta) {
    HapticFeedback.selectionClick();
    setState(() {
      _isEndOfTrack = false;
      final newMin = (_selectedDuration.inMinutes + minutesDelta).clamp(5, 120);
      _selectedDuration = Duration(minutes: newMin);
    });
  }

  String _formatDurationTitle(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F19).withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: SleepTimerService.instance,
              builder: (context, _) {
                final timer = SleepTimerService.instance;
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.bedtime_rounded, color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Sleep Timer',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      Text(
                                        timer.isActive
                                            ? 'Music will fade out smoothly'
                                            : 'Fade out and stop when you sleep',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(8),
                            ),
                            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                      const SizedBox(height: 20),

                      if (timer.isActive)
                        _buildActiveTimerView(context, timer)
                      else
                        _buildConfigTimerView(context),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ================= Active Timer View ================= //

  Widget _buildActiveTimerView(BuildContext context, SleepTimerService timer) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Glowing Circular Countdown Ring
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 200,
            height: 200,
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ambient Glow backdrop
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.22),
                        blurRadius: 36,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),
                // Circular Progress Arc
                CustomPaint(
                  size: const Size(190, 190),
                  painter: _TimerProgressPainter(
                    progress: timer.progressFraction,
                    trackColor: Colors.white.withValues(alpha: 0.07),
                    progressColor: const Color(0xFF818CF8),
                    gradientEnd: const Color(0xFFC084FC),
                  ),
                ),
                // Inner Content
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        timer.stopAtEndOfTrack ? Icons.music_note_rounded : Icons.nightlight_round,
                        color: const Color(0xFF818CF8),
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timer.formattedRemaining,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timer.stopAtEndOfTrack ? 'TRACK END' : 'REMAINING',
                        style: TextStyle(
                          color: const Color(0xFF94A3B8).withValues(alpha: 0.8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Status Card Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: timer.isFadingOut
                ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                : const Color(0xFF6366F1).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: timer.isFadingOut
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                  : const Color(0xFF6366F1).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                timer.isFadingOut ? Icons.volume_down_rounded : Icons.info_outline_rounded,
                size: 15,
                color: timer.isFadingOut ? const Color(0xFFFBBF24) : const Color(0xFF818CF8),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  timer.isFadingOut
                      ? 'Gently fading out volume now... 🌙'
                      : (timer.stopAtEndOfTrack
                          ? 'Playback halts when the song finishes'
                          : 'Audio will smoothly fade and stop'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: timer.isFadingOut ? const Color(0xFFFDE68A) : const Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Quick Steppers Row: +5m, +15m, +30m
        Row(
          children: [
            Expanded(child: _buildAddTimePill(context, timer, 5)),
            const SizedBox(width: 8),
            Expanded(child: _buildAddTimePill(context, timer, 15)),
            const SizedBox(width: 8),
            Expanded(child: _buildAddTimePill(context, timer, 30)),
          ],
        ),

        const SizedBox(height: 14),

        // Cancel Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
              foregroundColor: const Color(0xFFF87171),
              elevation: 0,
              side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.35), width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.timer_off_outlined, size: 20),
            label: const Text(
              'Turn Off Sleep Timer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              timer.cancel();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddTimePill(BuildContext context, SleepTimerService timer, int minutes) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        timer.addTime(Duration(minutes: minutes));
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: Color(0xFF818CF8)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$minutes min',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= Configuration View ================= //

  Widget _buildConfigTimerView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Presets Section Header
        const Text(
          'POPULAR PRESETS',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),

        // 2-Column Preset Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _presets.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: MediaQuery.textScalerOf(context).scale(1.0) > 1.2 ? 1.7 : 2.2,
          ),
          itemBuilder: (context, index) {
            final preset = _presets[index];
            final isSelected = preset.isEndOfTrack
                ? _isEndOfTrack
                : (!_isEndOfTrack && _selectedDuration.inMinutes == preset.minutes);

            return InkWell(
              onTap: () => _selectPreset(preset),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF6366F1).withValues(alpha: 0.18)
                      : const Color(0xFF131B2E).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF6366F1)
                        : Colors.white.withValues(alpha: 0.07),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        preset.icon,
                        size: 18,
                        color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            preset.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF818CF8)
                                  : const Color(0xFF64748B),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF818CF8)),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 20),

        // Custom Slider Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Custom Duration',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isEndOfTrack
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isEndOfTrack
                            ? Colors.white12
                            : const Color(0xFF6366F1).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _isEndOfTrack ? 'End of Track' : _formatDurationTitle(_selectedDuration),
                      style: TextStyle(
                        color: _isEndOfTrack ? const Color(0xFF94A3B8) : const Color(0xFF818CF8),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.remove_rounded, color: Colors.white70, size: 18),
                    onPressed: () => _stepTime(-5),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF6366F1),
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                        thumbColor: const Color(0xFF818CF8),
                        overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _isEndOfTrack ? 30.0 : _selectedDuration.inMinutes.toDouble().clamp(5.0, 120.0),
                        min: 5.0,
                        max: 120.0,
                        divisions: 23, // 5 minute steps from 5 to 120
                        onChanged: _adjustSlider,
                      ),
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.add_rounded, color: Colors.white70, size: 18),
                    onPressed: () => _stepTime(5),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('5m', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    Text('30m', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    Text('60m', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    Text('90m', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    Text('120m', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // Primary Start Timer Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                SleepTimerService.instance.setTimer(
                  _selectedDuration,
                  stopAtEnd: _isEndOfTrack,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bedtime_rounded, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _isEndOfTrack
                          ? 'Start Timer (End of Track)'
                          : 'Start Sleep Timer (${_formatDurationTitle(_selectedDuration)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SleepPreset {
  final int minutes;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isEndOfTrack;

  const _SleepPreset({
    required this.minutes,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isEndOfTrack = false,
  });
}

class _TimerProgressPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final Color gradientEnd;

  _TimerProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.gradientEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 16) / 2;
    const strokeWidth = 9.0;

    // 1. Background full track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // 2. Active Progress Arc
    if (progress > 0.0) {
      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      final rect = Rect.fromCircle(center: center, radius: radius);

      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [progressColor, gradientEnd],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimerProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
