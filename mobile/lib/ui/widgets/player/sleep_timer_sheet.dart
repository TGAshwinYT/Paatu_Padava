import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/sleep_timer_service.dart';

class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({Key? key}) : super(key: key);

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const SleepTimerSheet(),
    );
  }

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> {
  Duration _selectedDuration = const Duration(minutes: 30);
  bool _isEndOfTrack = false;

  void _stepTime(int minutesDelta) {
    HapticFeedback.selectionClick();
    setState(() {
      _isEndOfTrack = false;
      final newMinutes = (_selectedDuration.inMinutes + minutesDelta).clamp(1, 12 * 60);
      _selectedDuration = Duration(minutes: newMinutes);
    });
  }

  void _selectPreset(Duration duration) {
    HapticFeedback.selectionClick();
    setState(() {
      _isEndOfTrack = false;
      _selectedDuration = duration;
    });
  }

  void _selectEndOfTrack() {
    HapticFeedback.selectionClick();
    setState(() {
      _isEndOfTrack = true;
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListenableBuilder(
          listenable: SleepTimerService.instance,
          builder: (context, _) {
            final timer = SleepTimerService.instance;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.bedtime_rounded, color: Color(0xFF818CF8), size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Sleep Timer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 16),

                if (timer.isActive)
                  _buildActiveTimerView(context, timer)
                else
                  _buildConfigTimerView(context),
              ],
            );
          },
        ),
      ),
    );
  }

  // ================= Active Timer View ================= //

  Widget _buildActiveTimerView(BuildContext context, SleepTimerService timer) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),

        // Glowing Countdown Ring Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.nightlight_round, color: Color(0xFF818CF8), size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                timer.formattedRemaining,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                timer.stopAtEndOfTrack
                    ? 'Playback will stop when the current track finishes'
                    : 'Music will fade out smoothly and stop',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Quick Steppers Row: +5m, +15m
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF818CF8),
                  side: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('+5 Min', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  timer.addTime(const Duration(minutes: 5));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF818CF8),
                  side: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('+15 Min', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  timer.addTime(const Duration(minutes: 15));
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Cancel Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
              foregroundColor: const Color(0xFFF87171),
              side: const BorderSide(color: Color(0xFFEF4444), width: 1),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: const Text('Cancel Sleep Timer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            onPressed: () {
              HapticFeedback.mediumImpact();
              timer.cancel();
            },
          ),
        ),
      ],
    );
  }

  // ================= Configuration View ================= //

  Widget _buildConfigTimerView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stepper Controls Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Text('-5m', style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold)),
                onPressed: () => _stepTime(-5),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: Text(
                  _isEndOfTrack ? 'End of Track' : _formatDurationTitle(_selectedDuration),
                  style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Text('+5m', style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold)),
                onPressed: () => _stepTime(5),
              ),
            ],
          ),
        ),

        // Cupertino Scroll Wheel Picker
        Container(
          height: 150,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.dark,
              textTheme: CupertinoTextThemeData(
                pickerTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hm,
              initialTimerDuration: _selectedDuration,
              onTimerDurationChanged: (newDuration) {
                setState(() {
                  _isEndOfTrack = false;
                  _selectedDuration = newDuration;
                });
              },
            ),
          ),
        ),

        // Quick-select preset chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              _buildPresetChip('10m', const Duration(minutes: 10)),
              _buildPresetChip('20m', const Duration(minutes: 20)),
              _buildPresetChip('30m', const Duration(minutes: 30)),
              _buildPresetChip('45m', const Duration(minutes: 45)),
              _buildPresetChip('60m', const Duration(minutes: 60)),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('End of Track', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  selected: _isEndOfTrack,
                  selectedColor: const Color(0xFF6366F1),
                  backgroundColor: const Color(0xFF1E293B),
                  labelStyle: TextStyle(color: _isEndOfTrack ? Colors.white : const Color(0xFF94A3B8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _isEndOfTrack ? const Color(0xFF6366F1) : Colors.white12,
                    ),
                  ),
                  onSelected: (_) => _selectEndOfTrack(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Prominent Start Timer Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                const Icon(Icons.play_arrow_rounded, size: 24),
                const SizedBox(width: 8),
                Text(
                  _isEndOfTrack
                      ? 'Start Timer (End of Track)'
                      : 'Start Timer (${_formatDurationTitle(_selectedDuration)})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, Duration duration) {
    final isSelected = !_isEndOfTrack && _selectedDuration.inMinutes == duration.inMinutes;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        selected: isSelected,
        selectedColor: const Color(0xFF6366F1),
        backgroundColor: const Color(0xFF1E293B),
        labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? const Color(0xFF6366F1) : Colors.white12,
          ),
        ),
        onSelected: (_) => _selectPreset(duration),
      ),
    );
  }
}
