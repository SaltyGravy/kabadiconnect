import 'dart:async';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/services/voice_ai_service.dart';
import '../features/collector/lot/ai_voice_assistant_sheet.dart';

class GreetingEntry {
  final String text;
  final String languageName;
  final String langCode;

  const GreetingEntry({
    required this.text,
    required this.languageName,
    required this.langCode,
  });
}

/// Floating Action Button on the bottom side that displays an animated greeting
/// "Hi, can I help you?" cycling through languages with a smooth
/// disappearing and appearing transition effect. When tapped, opens the
/// AI Assistant modal with Voice & Chat options.
class FloatingAiAssistantButton extends StatefulWidget {
  final void Function(List<VoiceLotDraftItem> items)? onApplyItems;
  final VoidCallback? onTriggerCamera;
  final double bottomOffset;
  final double rightOffset;

  const FloatingAiAssistantButton({
    super.key,
    this.onApplyItems,
    this.onTriggerCamera,
    this.bottomOffset = 88.0,
    this.rightOffset = 16.0,
  });

  @override
  State<FloatingAiAssistantButton> createState() => _FloatingAiAssistantButtonState();
}

class _FloatingAiAssistantButtonState extends State<FloatingAiAssistantButton>
    with SingleTickerProviderStateMixin {
  static const List<GreetingEntry> _greetings = [
    GreetingEntry(text: 'Hi, can I help you? 👋', languageName: 'English', langCode: 'EN'),
    GreetingEntry(text: 'नमस्ते, क्या मैं मदद करूँ? 👋', languageName: 'Hindi', langCode: 'HI'),
    GreetingEntry(text: 'नमस्कार, मी मदत करू का? 👋', languageName: 'Marathi', langCode: 'MR'),
    GreetingEntry(text: 'வணக்கம், நான் உதவலாமா? 👋', languageName: 'Tamil', langCode: 'TA'),
    GreetingEntry(text: 'నమస్కారం, నేను సహాయం చేయవచ్చా? 👋', languageName: 'Telugu', langCode: 'TE'),
    GreetingEntry(text: 'ಹಲೋ, ನಾನು ಸಹಾಯ ಮಾಡಬಹುದೇ? 👋', languageName: 'Kannada', langCode: 'KN'),
    GreetingEntry(text: 'নমস্কার, আমি কি সাহায্য করতে পারি? 👋', languageName: 'Bengali', langCode: 'BN'),
    GreetingEntry(text: 'કેમ છો, હું મદદ કરી શકું? 👋', languageName: 'Gujarati', langCode: 'GU'),
  ];

  int _currentIndex = 0;
  Timer? _cycleTimer;

  late AnimationController _fadeSlideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _fadeSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeSlideController,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeSlideController,
      curve: Curves.easeOutBack,
    ));

    // Start with fully appeared text
    _fadeSlideController.value = 1.0;

    // Start the periodic language cycling animation
    _startLanguageCycle();
  }

  void _startLanguageCycle() {
    _cycleTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;

      // 1. Disappearing effect: fade & slide out
      _fadeSlideController.reverse().then((_) {
        if (!mounted) return;

        // 2. Switch to next language while invisible
        setState(() {
          _currentIndex = (_currentIndex + 1) % _greetings.length;
        });

        // 3. Appearing effect: fade & slide in
        _fadeSlideController.forward();
      });
    });
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _fadeSlideController.dispose();
    super.dispose();
  }

  void _openAssistant(BuildContext context) {
    AiVoiceAssistantSheet.show(
      context,
      onApplyItems: widget.onApplyItems,
      onTriggerCamera: widget.onTriggerCamera,
    );
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _greetings[_currentIndex];

    return Positioned(
      bottom: widget.bottomOffset,
      right: widget.rightOffset,
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Speech Greeting Pill with Appearing & Disappearing effect
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: GestureDetector(
                  onTap: () => _openAssistant(context),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    constraints: const BoxConstraints(maxWidth: 220),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                      border: Border.all(
                        color: kBrandGreen.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Language Code Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: kBrandGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            greeting.langCode,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: kBrandGreenDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Greeting Text
                        Flexible(
                          child: Text(
                            greeting.text,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Floating Action Button with Glowing Gradient and Badge
            GestureDetector(
              onTap: () => _openAssistant(context),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [kBrandGreen, kBrandGreenDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandGreen.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
                    // Small Mic / Chat badge on bottom right of button
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mic, color: kBrandGreenDark, size: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
