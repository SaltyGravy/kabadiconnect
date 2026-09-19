import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/services/voice_ai_service.dart';
import 'create_lot_screen.dart';

enum AssistantMode { voice, chat }

class ChatMessage {
  final bool isUser;
  final String text;
  final DateTime time;
  final List<VoiceLotDraftItem>? draftItems;
  final String? rateInfo;
  final bool isRejected;

  ChatMessage({
    required this.isUser,
    required this.text,
    required this.time,
    this.draftItems,
    this.rateInfo,
    this.isRejected = false,
  });
}

/// Full interactive Voice & Chat AI Assistant Modal Bottom Sheet
class AiVoiceAssistantSheet extends StatefulWidget {
  final void Function(List<VoiceLotDraftItem> items)? onApplyItems;
  final VoidCallback? onTriggerCamera;
  final AssistantMode initialMode;

  const AiVoiceAssistantSheet({
    super.key,
    this.onApplyItems,
    this.onTriggerCamera,
    this.initialMode = AssistantMode.voice,
  });

  static Future<void> show(
    BuildContext context, {
    void Function(List<VoiceLotDraftItem> items)? onApplyItems,
    VoidCallback? onTriggerCamera,
    AssistantMode initialMode = AssistantMode.voice,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiVoiceAssistantSheet(
        onApplyItems: onApplyItems,
        onTriggerCamera: onTriggerCamera,
        initialMode: initialMode,
      ),
    );
  }

  @override
  State<AiVoiceAssistantSheet> createState() => _AiVoiceAssistantSheetState();
}

class _AiVoiceAssistantSheetState extends State<AiVoiceAssistantSheet> with SingleTickerProviderStateMixin {
  late AssistantMode _mode;
  bool _ttsMuted = false;
  bool _isProcessing = false;

  // Voice tab state
  String _liveSpokenText = '';
  final List<VoiceLotDraftItem> _accumulatedItems = [];
  String _aiVoiceFeedback = '';

  // Chat tab state
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];

  // Animation for microphone pulsing ripple
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial welcome message in chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      _initWelcomeMessage(appState.locale);
      final voiceAi = context.read<VoiceAiService>();
      voiceAi.initSpeech();
    });
  }

  void _initWelcomeMessage(AppLocale locale) {
    String welcome;
    switch (locale) {
      case AppLocale.hi:
        welcome = 'नमस्ते! मैं आपका कबाड़ीकनेक्ट AI सहायक हूँ। आप बोलकर या लिखकर नया लॉट बना सकते हैं (उदा. "5 किलो कॉपर केबल"), भाव पूछ सकते हैं या सुरक्षा नियम जान सकते हैं।';
        break;
      case AppLocale.mr:
        welcome = 'नमस्कार! मी तुमचा कबाडीकनेक्ट AI सहाय्यक आहे. तुम्ही बोलून किंवा लिहून लॉट तयार करू शकता (उदा. "5 किलो कॉपर वायर"), दर विचारू शकता किंवा सुरक्षा नियम जाणून घेऊ शकता.';
        break;
      case AppLocale.en:
        welcome = 'Hello! I am your KabadiConnect AI Copilot. Speak or type to create lots (e.g. "Add 5 kg copper cables"), check live scrap prices, or get CPCB safety advice.';
        break;
    }
    setState(() {
      _messages.add(ChatMessage(
        isUser: false,
        text: welcome,
        time: DateTime.now(),
      ));
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _chatController.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  String _getLocation(AppState appState) {
    final c = appState.collector;
    if (c?.lat != null && c?.lng != null) return nearestServiceLocation(c!.lat!, c.lng!);
    return serviceLocations.first;
  }

  Future<void> _toggleListening() async {
    final voiceAi = context.read<VoiceAiService>();
    final appState = context.read<AppState>();

    if (voiceAi.isListening) {
      await voiceAi.stopListening();
      if (_liveSpokenText.trim().isNotEmpty) {
        await _handleInputSubmission(_liveSpokenText);
      }
    } else {
      setState(() {
        _liveSpokenText = '';
        _aiVoiceFeedback = '';
      });

      await voiceAi.startListening(
        locale: appState.locale,
        onResult: (text, isFinal) {
          setState(() => _liveSpokenText = text);
          if (isFinal && text.trim().isNotEmpty) {
            _handleInputSubmission(text);
          }
        },
      );
    }
  }

  Future<void> _handleInputSubmission(String input) async {
    if (input.trim().isEmpty) return;

    final voiceAi = context.read<VoiceAiService>();
    final appState = context.read<AppState>();
    final location = _getLocation(appState);

    setState(() => _isProcessing = true);

    try {
      final response = await voiceAi.processInput(
        input,
        locale: appState.locale,
        location: location,
      );

      // Handle items detected
      if (response.detectedItems.isNotEmpty) {
        setState(() {
          _accumulatedItems.addAll(response.detectedItems);
        });
      }

      // Handle clear intent
      if (response.intent == VoiceIntent.clearAll) {
        setState(() {
          _accumulatedItems.clear();
        });
      }

      // Handle photo intent
      if (response.intent == VoiceIntent.takePhoto) {
        if (widget.onTriggerCamera != null) {
          widget.onTriggerCamera!();
          if (!mounted) return;
          Navigator.pop(context);
          return;
        }
      }

      // Handle submit intent
      if (response.intent == VoiceIntent.submitLot) {
        _applyAndProceed();
        return;
      }

      setState(() {
        _aiVoiceFeedback = response.textReply;
        // Also add to chat history
        _messages.add(ChatMessage(isUser: true, text: input, time: DateTime.now()));
        _messages.add(ChatMessage(
          isUser: false,
          text: response.textReply,
          time: DateTime.now(),
          draftItems: response.detectedItems.isNotEmpty ? response.detectedItems : null,
          rateInfo: response.rateInfo,
          isRejected: response.isCollectibilityRejected,
        ));
      });

      // Spoken voice reply if not muted
      if (!_ttsMuted && response.spokenReply.isNotEmpty) {
        await voiceAi.speak(response.spokenReply, appState.locale);
      }

      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _applyAndProceed() {
    if (_accumulatedItems.isEmpty) return;

    if (widget.onApplyItems != null) {
      widget.onApplyItems!(_accumulatedItems);
      Navigator.pop(context);
    } else {
      // Navigate to CreateLotScreen with pre-populated items
      final lotItems = _accumulatedItems.map((i) => i.toLotItem()).toList();
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CreateLotScreen(initialItems: lotItems)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final voiceAi = context.watch<VoiceAiService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kBrandGreen.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: kBrandGreen, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appState.locale == AppLocale.hi
                            ? 'कबाड़ी AI सहायक'
                            : appState.locale == AppLocale.mr
                                ? 'कबाडी AI सहाय्यक'
                                : 'KabadiConnect AI Copilot',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      Text(
                        appState.locale == AppLocale.hi
                            ? 'वॉइस व चैट से लॉट बनाएं'
                            : appState.locale == AppLocale.mr
                                ? 'व्हॉइस व चॅटने लॉट बनवा'
                                : 'Voice & Chat Scrap Assistant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),

                // Mode Selector Toggle (Voice / Chat)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      _ModeTab(
                        icon: Icons.mic,
                        label: 'Voice',
                        isSelected: _mode == AssistantMode.voice,
                        onTap: () => setState(() => _mode = AssistantMode.voice),
                      ),
                      _ModeTab(
                        icon: Icons.chat_bubble_outline,
                        label: 'Chat',
                        isSelected: _mode == AssistantMode.chat,
                        onTap: () => setState(() => _mode = AssistantMode.chat),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 2),
                // Sound Mute/Unmute
                IconButton(
                  icon: Icon(_ttsMuted ? Icons.volume_off : Icons.volume_up, size: 20),
                  tooltip: _ttsMuted ? 'Unmute Audio' : 'Mute Audio',
                  color: _ttsMuted ? Colors.grey : kBrandGreen,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _ttsMuted = !_ttsMuted),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Main View (Voice or Chat)
          Expanded(
            child: _mode == AssistantMode.voice
                ? _buildVoiceView(context, voiceAi, appState)
                : _buildChatView(context, appState),
          ),

          // Bottom Applied Items Action Bar (if any items were recognized)
          if (_accumulatedItems.isNotEmpty)
            _buildAppliedItemsBar(context, appState),
        ],
      ),
    );
  }

  // ================= VOICE VIEW =================
  Widget _buildVoiceView(BuildContext context, VoiceAiService voiceAi, AppState appState) {
    final isListening = voiceAi.isListening;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Pulsing Microphone Action Button
          GestureDetector(
            onTap: _toggleListening,
            child: ScaleTransition(
              scale: isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isListening
                        ? [Colors.red.shade400, Colors.red.shade700]
                        : [kBrandGreen, kBrandGreenDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isListening
                          ? Colors.red.withValues(alpha: 0.45)
                          : kBrandGreen.withValues(alpha: 0.4),
                      blurRadius: isListening ? 26 : 14,
                      spreadRadius: isListening ? 6 : 2,
                    ),
                  ],
                ),
                child: Icon(
                  isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Listening status label
          Text(
            isListening
                ? (appState.locale == AppLocale.hi
                    ? 'सुन रहा हूँ... बोलिए'
                    : appState.locale == AppLocale.mr
                        ? 'ऐकत आहे... बोला'
                        : 'Listening... Speak now')
                : (appState.locale == AppLocale.hi
                    ? 'बोलने के लिए माइक दबाएं'
                    : appState.locale == AppLocale.mr
                        ? 'बोलण्यासाठी माइक दाबा'
                        : 'Tap Mic to Speak'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isListening ? Colors.red.shade700 : Colors.black87,
            ),
          ),

          const SizedBox(height: 12),

          // Live Recognized Transcript Container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(minHeight: 65),
            decoration: BoxDecoration(
              color: isListening
                  ? Colors.red.shade50.withValues(alpha: 0.6)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isListening ? Colors.red.shade200 : Colors.grey.shade300,
              ),
            ),
            child: _isProcessing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('AI analyzing spoken scrap...', style: TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  )
                : Text(
                    _liveSpokenText.isNotEmpty
                        ? '“$_liveSpokenText”'
                        : (appState.locale == AppLocale.hi
                            ? 'उदा: "5 किलो कॉपर वायर और 2 कंप्यूटर मदरबोर्ड"'
                            : appState.locale == AppLocale.mr
                                ? 'उदा: "5 किलो कॉपर वायर आणि 2 मदरबोर्ड"'
                                : 'e.g. "Add 5 kg copper cables and 2 motherboards"'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: _liveSpokenText.isEmpty ? FontStyle.italic : FontStyle.normal,
                      color: _liveSpokenText.isEmpty ? Colors.grey.shade600 : Colors.black87,
                      fontWeight: _liveSpokenText.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
          ),

          if (_aiVoiceFeedback.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kBrandGreen.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBrandGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over, color: kBrandGreenDark, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _aiVoiceFeedback,
                      style: const TextStyle(fontSize: 13, color: kBrandGreenDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Quick Suggestion Chips (Tap to run voice simulation)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              appState.locale == AppLocale.hi
                  ? 'तुरंत आज़माएँ (क्लिक करें):'
                  : appState.locale == AppLocale.mr
                      ? 'लगेच वापरून पहा:'
                      : 'Quick Prompts (Tap to test):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SuggestionChip(
                label: '🔌 5 kg Copper Cable',
                onTap: () => _handleInputSubmission('Add 5 kg copper cable intact'),
              ),
              _SuggestionChip(
                label: '💾 2 kg Motherboard PCB',
                onTap: () => _handleInputSubmission('Add 2 kg computer motherboard'),
              ),
              _SuggestionChip(
                label: '🔋 10 kg Battery',
                onTap: () => _handleInputSubmission('Add 10 kg battery intact'),
              ),
              _SuggestionChip(
                label: '💰 PCB Rate?',
                onTap: () => _handleInputSubmission('What is today rate of PCB?'),
              ),
              _SuggestionChip(
                label: '📸 Take Photo',
                onTap: () => _handleInputSubmission('take photo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= CHAT VIEW =================
  Widget _buildChatView(BuildContext context, AppState appState) {
    return Column(
      children: [
        // Quick prompts row in chat
        Container(
          height: 38,
          margin: const EdgeInsets.only(top: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              _ChatQuickChip(
                label: '5kg Cable + 2kg PCB',
                onTap: () => _handleInputSubmission('Create lot with 5kg copper cable and 2kg PCB'),
              ),
              _ChatQuickChip(
                label: 'Today Battery Rate',
                onTap: () => _handleInputSubmission('What is today rate of battery?'),
              ),
              _ChatQuickChip(
                label: 'Is CRT TV accepted?',
                onTap: () => _handleInputSubmission('Is CRT TV accepted?'),
              ),
              _ChatQuickChip(
                label: 'Lead Battery Safety',
                onTap: () => _handleInputSubmission('Safety advice for lead acid batteries'),
              ),
            ],
          ),
        ),

        // Message bubbles list
        Expanded(
          child: ListView.builder(
            controller: _chatScrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final msg = _messages[i];
              return _ChatBubble(
                message: msg,
                locale: appState.locale,
                onAddItems: (items) {
                  setState(() => _accumulatedItems.addAll(items));
                },
              );
            },
          ),
        ),

        if (_isProcessing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            alignment: Alignment.centerLeft,
            child: const Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('AI is typing...', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),

        // Input Field Bar
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      final txt = v.trim();
                      _chatController.clear();
                      _handleInputSubmission(txt);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: appState.locale == AppLocale.hi
                        ? 'यहाँ लिखें (उदा. 5 किलो केबल जोड़ें)...'
                        : appState.locale == AppLocale.mr
                            ? 'येथे लिहा (उदा. 5 किलो केबल जोडा)...'
                            : 'Type here (e.g. Add 5 kg cables)...',
                    hintStyle: const TextStyle(fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Mic button to toggle voice inside chat
              CircleAvatar(
                backgroundColor: kBrandGreen.withValues(alpha: 0.15),
                radius: 20,
                child: IconButton(
                  icon: const Icon(Icons.mic, color: kBrandGreen, size: 20),
                  onPressed: () {
                    setState(() => _mode = AssistantMode.voice);
                    _toggleListening();
                  },
                ),
              ),
              const SizedBox(width: 6),
              // Send button
              CircleAvatar(
                backgroundColor: kBrandGreen,
                radius: 20,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  onPressed: () {
                    final txt = _chatController.text.trim();
                    if (txt.isNotEmpty) {
                      _chatController.clear();
                      _handleInputSubmission(txt);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= APPLIED ITEMS BAR =================
  Widget _buildAppliedItemsBar(BuildContext context, AppState appState) {
    final totalVal = _accumulatedItems.fold<double>(0, (sum, item) => sum + item.estimatedValue);
    final totalWeight = _accumulatedItems.fold<double>(0, (sum, item) => sum + item.weightKg);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kBrandGreenDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${_accumulatedItems.length} items (${totalWeight.toStringAsFixed(1)} kg)',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '₹${totalVal.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => setState(() => _accumulatedItems.clear()),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kBrandGreenDark,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: _applyAndProceed,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(
                widget.onApplyItems != null ? 'Add to Lot' : 'Create Lot Now',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Mode toggle button (Voice / Chat)
class _ModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : null,
        ),
        // Label only shows for the selected tab -- keeps the toggle
        // compact (icon-only when inactive) so it doesn't crowd out the
        // header title on narrower screens.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? kBrandGreen : Colors.grey.shade700),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kBrandGreen),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Suggestion chip for quick testing
class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      backgroundColor: Colors.grey.shade100,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }
}

// Quick chip inside chat
class _ChatQuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChatQuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: kBrandGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBrandGreen.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: kBrandGreenDark, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// Chat Message Bubble
class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final AppLocale locale;
  final void Function(List<VoiceLotDraftItem> items) onAddItems;

  const _ChatBubble({
    required this.message,
    required this.locale,
    required this.onAddItems,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: kBrandGreen.withValues(alpha: 0.15),
                  child: const Icon(Icons.psychology, color: kBrandGreen, size: 16),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? kBrandGreen
                        : message.isRejected
                            ? Colors.red.shade50
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                      bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                    ),
                    border: message.isRejected ? Border.all(color: Colors.red.shade300) : null,
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Attached Lot Items card if AI recognized items in chat
          if (message.draftItems != null && message.draftItems!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory_2, color: kBrandGreenDark, size: 16),
                        const SizedBox(width: 6),
                        const Text('Detected Scrap Items:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kBrandGreenDark)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...message.draftItems!.map((it) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(it.category.icon, size: 14, color: it.category.color),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${it.category.key} (${it.condition})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text('${it.weightKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Text('₹${it.estimatedValue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kBrandGreenDark)),
                            ],
                          ),
                        )),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => onAddItems(message.draftItems!),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add to Draft'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
