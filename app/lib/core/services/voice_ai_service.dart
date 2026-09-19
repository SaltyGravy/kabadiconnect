import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/lot.dart';
import 'ml/ewaste_ai_service.dart';
import 'ml/ewaste_knowledge_service.dart';
import 'pricing_service.dart';
import 'tts_service.dart';

/// Intent identified from speech or chat input
enum VoiceIntent {
  addItem,
  updateWeight,
  queryRate,
  queryAccepted,
  takePhoto,
  submitLot,
  clearAll,
  generalHelp,
}

/// A parsed scrap item ready to be added to a lot draft
class VoiceLotDraftItem {
  final MaterialCategory category;
  final double weightKg;
  final String condition;
  final double estimatedValue;
  final double ratePerKg;

  VoiceLotDraftItem({
    required this.category,
    required this.weightKg,
    required this.condition,
    required this.estimatedValue,
    required this.ratePerKg,
  });

  LotItem toLotItem() => LotItem(
        category: category,
        condition: condition,
        weightKg: weightKg,
        estimatedValue: estimatedValue,
      );
}

/// Structured AI response for voice/chat interaction
class VoiceAssistantResponse {
  final String textReply;
  final String spokenReply;
  final VoiceIntent intent;
  final List<VoiceLotDraftItem> detectedItems;
  final String? safetyWarning;
  final bool isCollectibilityRejected;
  final String? rejectionReason;
  final String? rateInfo;

  VoiceAssistantResponse({
    required this.textReply,
    required this.spokenReply,
    required this.intent,
    this.detectedItems = const [],
    this.safetyWarning,
    this.isCollectibilityRejected = false,
    this.rejectionReason,
    this.rateInfo,
  });
}

/// Service handling Multilingual Speech-to-Text, Vernacular NLP Parsing,
/// Price & Knowledge lookups, and Spoken Audio generation (TTS).
class VoiceAiService extends ChangeNotifier {
  final PricingService pricingService;
  final EwasteKnowledgeService knowledgeService;
  final TtsService ttsService;
  final EwasteAiService? ewasteAiService;

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastSpokenWords = '';

  bool get speechEnabled => _speechEnabled;
  bool get isListening => _isListening;
  String get lastSpokenWords => _lastSpokenWords;

  VoiceAiService({
    required this.pricingService,
    required this.knowledgeService,
    required this.ttsService,
    this.ewasteAiService,
  });

  /// Initialize Speech to Text
  Future<bool> initSpeech() async {
    if (_speechEnabled) return true;
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          _isListening = false;
          notifyListeners();
        },
        onStatus: (status) {
          _isListening = status == 'listening';
          notifyListeners();
        },
      );
      notifyListeners();
      return _speechEnabled;
    } catch (_) {
      _speechEnabled = false;
      notifyListeners();
      return false;
    }
  }

  /// Start listening with locale support (hi_IN, mr_IN, en_IN)
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    AppLocale locale = AppLocale.en,
  }) async {
    if (!_speechEnabled) {
      final ok = await initSpeech();
      if (!ok) return;
    }

    String localeId = 'en_IN';
    if (locale == AppLocale.hi) localeId = 'hi_IN';
    if (locale == AppLocale.mr) localeId = 'mr_IN';

    _lastSpokenWords = '';
    _isListening = true;
    notifyListeners();

    await _speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        _lastSpokenWords = result.recognizedWords;
        onResult(result.recognizedWords, result.finalResult);
        notifyListeners();
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        localeId: localeId,
      ),
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  /// Speaks text using TTS in the user's active locale
  Future<void> speak(String text, AppLocale locale) async {
    await ttsService.speak(text, locale);
  }

  /// Main entry point: process voice transcript or chat input.
  /// Uses offline vernacular regex rule engine + optional online Gemini NLP.
  Future<VoiceAssistantResponse> processInput(
    String input, {
    required AppLocale locale,
    required String location,
  }) async {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) {
      return VoiceAssistantResponse(
        textReply: _emptyReply(locale),
        spokenReply: _emptyReply(locale),
        intent: VoiceIntent.generalHelp,
      );
    }

    // 1. If online AI is enabled and has API key, try deep contextual understanding
    if (ewasteAiService != null && ewasteAiService!.hasApiKey && ewasteAiService!.useOnlineAi) {
      try {
        final onlineResp = await _parseWithGemini(cleanInput, locale: locale, location: location);
        if (onlineResp != null) return onlineResp;
      } catch (_) {
        // Fall back gracefully to on-device engine
      }
    }

    // 2. Offline / On-Device Vernacular Engine (zero latency, works 100% offline)
    return _parseLocally(cleanInput, locale: locale, location: location);
  }

  /// Local Rule-based & Multilingual NLP Engine
  VoiceAssistantResponse _parseLocally(
    String text, {
    required AppLocale locale,
    required String location,
  }) {
    final lower = text.toLowerCase();

    // Check Clear intent
    if (_matchesKeywords(lower, ['clear', 'reset', 'delete all', 'remove all', 'sab hatao', 'hatao', 'हटाइए', 'रीसेट', 'सर्व काढा'])) {
      final msg = _tClear(locale);
      return VoiceAssistantResponse(
        textReply: msg,
        spokenReply: msg,
        intent: VoiceIntent.clearAll,
      );
    }

    // Check Take Photo intent
    if (_matchesKeywords(lower, ['photo', 'camera', 'snap', 'picture', 'photo khicho', 'tasveer', 'फोटो', 'कॅमेरा', 'तस्वीर'])) {
      final msg = _tPhoto(locale);
      return VoiceAssistantResponse(
        textReply: msg,
        spokenReply: msg,
        intent: VoiceIntent.takePhoto,
      );
    }

    // Check Submit/Checkout intent
    if (_matchesKeywords(lower, ['submit', 'create lot', 'checkout', 'finish', 'done', 'aage badho', 'lot banao', 'लॉट बनाओ', 'सबमिट', 'पूर्ण करा'])) {
      final msg = _tSubmit(locale);
      return VoiceAssistantResponse(
        textReply: msg,
        spokenReply: msg,
        intent: VoiceIntent.submitLot,
      );
    }

    // Check Rate / Price inquiry
    if (_matchesKeywords(lower, ['price', 'rate', 'cost', 'bhav', 'bhaav', 'rate kya', 'kitne ka', 'bhav kay', 'रेट', 'भाव', 'कीमत', 'दर'])) {
      return _handleRateQuery(lower, locale: locale, location: location);
    }

    // Check Prohibited / Collectibility query
    final collectibility = knowledgeService.checkCollectibility(lower);
    if (!collectibility.isCollectible) {
      final reason = collectibility.rejectionReason ?? 'This item is not accepted under India E-Waste Management Rules.';
      final reply = locale == AppLocale.hi
          ? 'माफ़ कीजिए, यह स्वीकार नहीं किया जाता है: $reason'
          : locale == AppLocale.mr
              ? 'क्षमस्व, हे स्वीकारले जात नाही: $reason'
              : 'Sorry, this item cannot be collected: $reason';
      return VoiceAssistantResponse(
        textReply: reply,
        spokenReply: reply,
        intent: VoiceIntent.queryAccepted,
        isCollectibilityRejected: true,
        rejectionReason: reason,
      );
    }

    // Parse scrap items to ADD or UPDATE
    final items = _extractItems(lower, location: location);
    if (items.isNotEmpty) {
      double totalVal = 0;
      final summaryNames = <String>[];
      for (final item in items) {
        totalVal += item.estimatedValue;
        summaryNames.add('${item.weightKg.toStringAsFixed(1)} kg ${_categoryDisplayName(item.category, locale)}');
      }

      String textReply;
      String spokenReply;
      if (locale == AppLocale.hi) {
        textReply = '✅ मैंने जोड़ दिया: ${summaryNames.join(", ")}। कुल अनुमानित मूल्य ₹${totalVal.toStringAsFixed(0)} है।';
        spokenReply = '${summaryNames.join(", ")} जोड़ दिया गया है। अनुमानित मूल्य ₹${totalVal.toStringAsFixed(0)} है।';
      } else if (locale == AppLocale.mr) {
        textReply = '✅ जोडले गेले: ${summaryNames.join(", ")}. एकूण अंदाजे मूल्य ₹${totalVal.toStringAsFixed(0)}.';
        spokenReply = '${summaryNames.join(", ")} जोडले गेले. अंदाजे किंमत ₹${totalVal.toStringAsFixed(0)}.';
      } else {
        textReply = '✅ Added: ${summaryNames.join(", ")}. Estimated value ₹${totalVal.toStringAsFixed(0)}.';
        spokenReply = 'Added ${summaryNames.join(", ")}. Total estimate is ₹${totalVal.toStringAsFixed(0)}.';
      }

      return VoiceAssistantResponse(
        textReply: textReply,
        spokenReply: spokenReply,
        intent: VoiceIntent.addItem,
        detectedItems: items,
      );
    }

    // Fallback general guidance
    final fallback = _tGeneralGuidance(locale);
    return VoiceAssistantResponse(
      textReply: fallback,
      spokenReply: fallback,
      intent: VoiceIntent.generalHelp,
    );
  }

  /// Handle Scrap Price / Rate Queries
  VoiceAssistantResponse _handleRateQuery(String lower, {required AppLocale locale, required String location}) {
    MaterialCategory? matchedCategory;
    for (final cat in MaterialCategory.values) {
      if (_categoryMatches(lower, cat)) {
        matchedCategory = cat;
        break;
      }
    }

    if (matchedCategory != null) {
      final rate = pricingService.currentRate(matchedCategory, location) ?? 50.0;
      final catName = _categoryDisplayName(matchedCategory, locale);
      String text;
      if (locale == AppLocale.hi) {
        text = '💰 $location में $catName का चालू भाव ₹${rate.toStringAsFixed(0)} प्रति किलो है।';
      } else if (locale == AppLocale.mr) {
        text = '💰 $location मध्ये $catName चा सध्याचा दर ₹${rate.toStringAsFixed(0)} प्रति किलो आहे.';
      } else {
        text = '💰 Current rate for $catName in $location is ₹${rate.toStringAsFixed(0)}/kg.';
      }
      return VoiceAssistantResponse(
        textReply: text,
        spokenReply: text,
        intent: VoiceIntent.queryRate,
        rateInfo: '₹${rate.toStringAsFixed(0)}/kg',
      );
    }

    // Broad rate list summary
    final cablesRate = pricingService.currentRate(MaterialCategory.cables, location) ?? 150.0;
    final pcbRate = pricingService.currentRate(MaterialCategory.pcb, location) ?? 220.0;
    final battRate = pricingService.currentRate(MaterialCategory.batteries, location) ?? 85.0;

    String summary;
    if (locale == AppLocale.hi) {
      summary = '📊 आज के मुख्य भाव ($location): कॉपर केबल ₹${cablesRate.toStringAsFixed(0)}/kg, मदरबोर्ड PCB ₹${pcbRate.toStringAsFixed(0)}/kg, बैटरी ₹${battRate.toStringAsFixed(0)}/kg।';
    } else if (locale == AppLocale.mr) {
      summary = '📊 आजचे मुख्य भाव ($location): कॉपर केबल ₹${cablesRate.toStringAsFixed(0)}/kg, मदरबोर्ड PCB ₹${pcbRate.toStringAsFixed(0)}/kg, बॅटरी ₹${battRate.toStringAsFixed(0)}/kg.';
    } else {
      summary = '📊 Today\'s rates ($location): Copper Cables ₹${cablesRate.toStringAsFixed(0)}/kg, PCB ₹${pcbRate.toStringAsFixed(0)}/kg, Batteries ₹${battRate.toStringAsFixed(0)}/kg.';
    }

    return VoiceAssistantResponse(
      textReply: summary,
      spokenReply: summary,
      intent: VoiceIntent.queryRate,
    );
  }

  /// Extract scrap items (category, weight, condition) from spoken text
  List<VoiceLotDraftItem> _extractItems(String text, {required String location}) {
    final results = <VoiceLotDraftItem>[];

    // Check each category
    for (final cat in MaterialCategory.values) {
      if (_categoryMatches(text, cat)) {
        final weight = _extractWeightForCategory(text, cat);
        final condition = _extractCondition(text);
        final rate = pricingService.currentRate(cat, location) ?? 50.0;
        final estimatedVal = pricingService.estimateValue(
          category: cat,
          location: location,
          weightKg: weight,
          condition: condition,
        );

        results.add(VoiceLotDraftItem(
          category: cat,
          weightKg: weight > 0 ? weight : 1.0, // default 1 kg if not specified
          condition: condition,
          estimatedValue: estimatedVal,
          ratePerKg: rate,
        ));
      }
    }

    return results;
  }

  /// Keywords for each material category
  List<String> _getKeywordsForCategory(MaterialCategory cat) {
    switch (cat) {
      case MaterialCategory.cables:
        return [
          'cable', 'cables', 'wire', 'wires', 'wiring', 'copper', 'taamba', 'tamba', 'taar', 'tar',
          'तार', 'केबल', 'तांबा', 'कॉपर', 'तांब्याची तार', 'वायर'
        ];
      case MaterialCategory.pcb:
        return [
          'pcb', 'motherboard', 'circuit', 'circuit board', 'board', 'plata', 'green board', 'chip',
          'मदरबोर्ड', 'सर्किट', 'पीसीबी', 'बोर्ड', 'मदर बोर्ड'
        ];
      case MaterialCategory.batteries:
        return [
          'battery', 'batteries', 'cell', 'lithium', 'inverter', 'lead acid', 'acid battery',
          'बैटरी', 'सेल', 'बॅटरी', 'इन्व्हर्टर'
        ];
      case MaterialCategory.crt:
        return [
          'crt', 'picture tube', 'box tv', 'old tv', 'heavy tv', 'cathode',
          'सीआरटी', 'डब्बा टीवी', 'कॅथोड', 'जुन्या टीव्ही'
        ];
      case MaterialCategory.lcdLed:
        return [
          'lcd', 'led', 'display', 'screen', 'monitor', 'flat tv', 'panel',
          'स्क्रीन', 'डिस्प्ले', 'मॉनिटर', 'पैनल', 'टीव्ही स्क्रीन'
        ];
      case MaterialCategory.motorsMagnets:
        return [
          'motor', 'motors', 'magnet', 'magnets', 'fan motor', 'pankha motor', 'compressor', 'stator',
          'मोटर', 'चुंबक', 'मॅग्नेट', 'पंखा मोटर', 'कंप्रेसर'
        ];
      case MaterialCategory.mixedPlastics:
        return [
          'plastic', 'plastics', 'casing', 'body', 'e-plastic', 'abs', 'fiber',
          'प्लास्टिक', 'बॉडी', 'केसिंग'
        ];
      case MaterialCategory.mixedOther:
        return [
          'mixed', 'other', 'metal', 'misc', 'electronics', 'kachra',
          'मिश्रित', 'अन्य', 'इतर'
        ];
    }
  }

  /// Category keyword matcher supporting English, Hindi, Marathi, and Hinglish
  bool _categoryMatches(String text, MaterialCategory cat) {
    return _matchesKeywords(text, _getKeywordsForCategory(cat));
  }

  /// Extract weight for a category from vernacular and numerical patterns
  /// using proximity to the category keyword in the text
  double _extractWeightForCategory(String text, MaterialCategory cat) {
    final keywords = _getKeywordsForCategory(cat);
    int catPos = -1;
    for (final kw in keywords) {
      final idx = text.indexOf(kw);
      if (idx != -1) {
        if (catPos == -1 || idx < catPos) {
          catPos = idx;
        }
      }
    }
    if (catPos == -1) catPos = 0;

    double? bestVal;
    int minDistance = 999999;

    int distanceToCategory(int numPos) {
      if (numPos <= catPos) {
        return catPos - numPos; // Preceding quantifier
      } else {
        return (numPos - catPos) + 150; // Succeeding number belongs to next item
      }
    }

    // 1. Match digits with optional unit: "5 kg", "2.5 kilos", "10kg", "5 किलो", "5 केजी"
    final digitPattern = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kg|kilo|kilos|किलो|केजी|के जी|g|grams|ग्राम)?', caseSensitive: false);
    final matches = digitPattern.allMatches(text);
    for (final m in matches) {
      final numStr = m.group(1);
      if (numStr != null) {
        final val = double.tryParse(numStr);
        if (val != null && val > 0 && val < 5000) {
          double weightKg = val;
          final fullMatch = m.group(0)?.toLowerCase() ?? '';
          if (fullMatch.contains('g') && !fullMatch.contains('kg') && !fullMatch.contains('kilo') && !fullMatch.contains('केजी')) {
            weightKg = val / 1000.0;
          }
          final dist = distanceToCategory(m.start);
          if (dist < minDistance) {
            minDistance = dist;
            bestVal = weightKg;
          }
        }
      }
    }

    // 2. Match vernacular words for numbers:
    final wordMap = {
      'aadha': 0.5, 'आधा': 0.5, 'निम्मा': 0.5,
      'dedh': 1.5, 'डेढ़': 1.5,
      'dhai': 2.5, 'ढाई': 2.5,
      'one': 1.0, 'ek': 1.0, 'एक': 1.0,
      'two': 2.0, 'do': 2.0, 'दोन': 2.0, 'दो': 2.0,
      'three': 3.0, 'teen': 3.0, 'तीन': 3.0,
      'four': 4.0, 'char': 4.0, 'chaar': 4.0, 'चार': 4.0,
      'five': 5.0, 'paanch': 5.0, 'panch': 5.0, 'पांच': 5.0, 'पाँच': 5.0,
      'six': 6.0, 'chhe': 6.0, 'सहा': 6.0, 'छह': 6.0,
      'seven': 7.0, 'saat': 7.0, 'सात': 7.0,
      'eight': 8.0, 'aath': 8.0, 'आठ': 8.0,
      'nine': 9.0, 'nau': 9.0, 'नऊ': 9.0, 'नौ': 9.0,
      'ten': 10.0, 'das': 10.0, 'दहा': 10.0, 'दस': 10.0,
      'fifteen': 15.0, 'pandrah': 15.0, 'पंधरा': 15.0, 'पंद्रह': 15.0,
      'twenty': 20.0, 'bees': 20.0, 'वीस': 20.0, 'बीस': 20.0,
      'twenty five': 25.0, 'pachees': 25.0, 'पंचवीस': 25.0, 'पच्चीस': 25.0,
      'fifty': 50.0, 'pachas': 50.0, 'पन्नास': 50.0, 'पचास': 50.0,
      'hundred': 100.0, 'sau': 100.0, 'शंभर': 100.0, 'सौ': 100.0,
    };

    for (final entry in wordMap.entries) {
      final idx = text.indexOf(entry.key);
      if (idx != -1) {
        final dist = distanceToCategory(idx);
        if (dist < minDistance) {
          minDistance = dist;
          bestVal = entry.value;
        }
      }
    }

    return bestVal ?? 1.0;
  }

  /// Extract condition
  String _extractCondition(String text) {
    if (_matchesKeywords(text, ['burnt', 'burn', 'fire', 'opened', 'tampered', 'khula', 'jala', 'जला', 'जळालेला', 'उघडलेला'])) {
      return 'burnt/tampered';
    }
    if (_matchesKeywords(text, ['damaged', 'broken', 'cracked', 'toota', 'kharab', 'bhanga', 'खराब', 'टूटा', 'फुटलेला'])) {
      return 'partially_damaged';
    }
    if (_matchesKeywords(text, ['mixed', 'kachra', 'mishrit', 'मिश्रित', 'एकत्र'])) {
      return 'mixed_lot';
    }
    return 'intact';
  }

  bool _matchesKeywords(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  String _categoryDisplayName(MaterialCategory cat, AppLocale locale) {
    switch (locale) {
      case AppLocale.hi:
        switch (cat) {
          case MaterialCategory.crt: return 'सीआरटी टीवी';
          case MaterialCategory.lcdLed: return 'एलसीडी/एलईडी स्क्रीन';
          case MaterialCategory.pcb: return 'सर्किट बोर्ड / मदरबोर्ड';
          case MaterialCategory.cables: return 'कॉपर केबल्स / तार';
          case MaterialCategory.batteries: return 'बैटरी';
          case MaterialCategory.motorsMagnets: return 'मोटर / मैग्नेट';
          case MaterialCategory.mixedPlastics: return 'ई-प्लास्टिक';
          case MaterialCategory.mixedOther: return 'मिश्रित ई-कचरा';
        }
      case AppLocale.mr:
        switch (cat) {
          case MaterialCategory.crt: return 'सीआरटी टीव्ही';
          case MaterialCategory.lcdLed: return 'एलसीडी/एलईडी स्क्रीन';
          case MaterialCategory.pcb: return 'सर्किट बोर्ड / मदरबोर्ड';
          case MaterialCategory.cables: return 'कॉपर केबल / वायर';
          case MaterialCategory.batteries: return 'बॅटरी';
          case MaterialCategory.motorsMagnets: return 'मोटर / मॅग्नेट';
          case MaterialCategory.mixedPlastics: return 'ई-प्लॅस्टिक';
          case MaterialCategory.mixedOther: return 'मिश्र ई-कचरा';
        }
      case AppLocale.en:
        switch (cat) {
          case MaterialCategory.crt: return 'CRT Monitors/TV';
          case MaterialCategory.lcdLed: return 'LCD/LED Screens';
          case MaterialCategory.pcb: return 'Circuit Boards / PCB';
          case MaterialCategory.cables: return 'Copper Cables & Wires';
          case MaterialCategory.batteries: return 'Batteries';
          case MaterialCategory.motorsMagnets: return 'Motors & Magnets';
          case MaterialCategory.mixedPlastics: return 'E-Waste Plastics';
          case MaterialCategory.mixedOther: return 'Mixed E-Waste';
        }
    }
  }

  /// Cloud Gemini Multimodal NLP Parser (when online with API key)
  Future<VoiceAssistantResponse?> _parseWithGemini(
    String text, {
    required AppLocale locale,
    required String location,
  }) async {
    if (ewasteAiService == null || !ewasteAiService!.hasApiKey || ewasteAiService!.apiKey == null) {
      return null;
    }

    final endpoint =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${ewasteAiService!.apiKey}';

    final prompt = '''
You are an intelligent Voice Copilot in KabadiConnect, assisting an Indian scrap collector (kabadiwala) in creating an e-waste lot or checking prices.
The user speaks or types in English, Hindi, Marathi, or Hinglish.

User Query: "$text"
User Location: "$location"
Language: ${locale.name}

8 Accepted Categories:
- CABLES (Copper wire, cables, cord, taamba)
- PCB (Motherboards, green circuit boards, computer boards)
- BATTERIES (Lithium, lead-acid, phone battery, inverter battery)
- CRT (Cathode ray tube, heavy box TV)
- LCD_LED (Flat screen, monitor, laptop panel)
- MOTORS_MAGNETS (Fan motors, electric motors, neodymium magnets)
- MIXED_PLASTICS (Electronics ABS casing, body)
- MIXED_OTHER (Unsorted e-waste scrap)

Instructions:
1. Determine intent: "add_item", "query_price", "query_accepted", "take_photo", "submit_lot", "clear_all", or "general".
2. If the user mentions scrap items they want to sell/add, extract a list of items: category, weight_kg (number), and condition ("intact", "partially_damaged", "burnt/tampered", "mixed_lot").
3. Provide a friendly conversational vernacular reply in the user's language (${locale.name}).

Respond ONLY in valid JSON matching this schema:
{
  "intent": "add_item" | "query_price" | "query_accepted" | "take_photo" | "submit_lot" | "clear_all" | "general",
  "reply_text": "text for the chat bubble",
  "spoken_text": "concise version for audio TTS",
  "items": [
    {
      "category": "CABLES" | "PCB" | "BATTERIES" | "CRT" | "LCD_LED" | "MOTORS_MAGNETS" | "MIXED_PLASTICS" | "MIXED_OTHER",
      "weight_kg": 5.0,
      "condition": "intact"
    }
  ]
}
''';

    final resp = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [{'text': prompt}]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'responseMimeType': 'application/json',
        }
      }),
    );

    if (resp.statusCode != 200) return null;
    final jsonResp = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = jsonResp['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final rawText = candidates[0]['content']['parts'][0]['text'] as String;
    final parsed = jsonDecode(rawText) as Map<String, dynamic>;

    final intentStr = parsed['intent'] as String? ?? 'general';
    VoiceIntent intent;
    switch (intentStr) {
      case 'add_item': intent = VoiceIntent.addItem; break;
      case 'query_price': intent = VoiceIntent.queryRate; break;
      case 'query_accepted': intent = VoiceIntent.queryAccepted; break;
      case 'take_photo': intent = VoiceIntent.takePhoto; break;
      case 'submit_lot': intent = VoiceIntent.submitLot; break;
      case 'clear_all': intent = VoiceIntent.clearAll; break;
      default: intent = VoiceIntent.generalHelp;
    }

    final detectedItems = <VoiceLotDraftItem>[];
    final itemsList = parsed['items'] as List<dynamic>? ?? [];
    for (final item in itemsList) {
      final m = item as Map<String, dynamic>;
      final cat = MaterialCategoryX.fromKey(m['category'] as String? ?? 'MIXED_OTHER');
      final weight = (m['weight_kg'] as num?)?.toDouble() ?? 1.0;
      final cond = m['condition'] as String? ?? 'intact';
      final rate = pricingService.currentRate(cat, location) ?? 50.0;
      final est = pricingService.estimateValue(category: cat, location: location, weightKg: weight, condition: cond);
      detectedItems.add(VoiceLotDraftItem(category: cat, weightKg: weight, condition: cond, estimatedValue: est, ratePerKg: rate));
    }

    return VoiceAssistantResponse(
      textReply: parsed['reply_text'] as String? ?? 'I have processed your request.',
      spokenReply: parsed['spoken_text'] as String? ?? 'Processed your request.',
      intent: intent,
      detectedItems: detectedItems,
    );
  }

  // Localized strings
  String _emptyReply(AppLocale l) {
    switch (l) {
      case AppLocale.hi: return 'नमस्ते! आप बोलकर लॉट बना सकते हैं, जैसे: "5 किलो कॉपर वायर जोड़ें"';
      case AppLocale.mr: return 'नमस्कार! तुम्ही बोलून लॉट तयार करू शकता, उदा: "5 किलो कॉपर केबल जोडा"';
      case AppLocale.en: return 'Hi! You can speak to create a lot, e.g. "Add 5 kg copper wire"';
    }
  }

  String _tClear(AppLocale l) {
    switch (l) {
      case AppLocale.hi: return 'सभी सामग्री हटा दी गई है।';
      case AppLocale.mr: return 'सर्व साहित्य काढून टाकले आहे.';
      case AppLocale.en: return 'Cleared all materials from lot.';
    }
  }

  String _tPhoto(AppLocale l) {
    switch (l) {
      case AppLocale.hi: return 'कैमरा खोला जा रहा है।';
      case AppLocale.mr: return 'कॅमेरा उघडत आहे.';
      case AppLocale.en: return 'Opening camera to take photo.';
    }
  }

  String _tSubmit(AppLocale l) {
    switch (l) {
      case AppLocale.hi: return 'लॉट तैयार है, चेकआउट स्क्रीन पर ले जाया जा रहा है।';
      case AppLocale.mr: return 'लॉट तयार आहे, चेकआउट स्क्रीनवर जात आहोत.';
      case AppLocale.en: return 'Lot ready! Moving to checkout.';
    }
  }

  String _tGeneralGuidance(AppLocale l) {
    switch (l) {
      case AppLocale.hi:
        return 'नमस्ते! मैं आपका वॉइस AI सहायक हूँ। आप कह सकते हैं:\n• "5 किलो कॉपर केबल और 2 किलो बैटरी जोड़ें"\n• "बैटरी का क्या भाव है?"\n• "फोटो खींचो" या "लॉट सबमिट करो"';
      case AppLocale.mr:
        return 'नमस्कार! मी तुमचा व्हॉइस AI सहाय्यक आहे. तुम्ही म्हणू शकता:\n• "5 किलो कॉपर वायर आणि 2 किलो बॅटरी जोडा"\n• "बॅटरीचा दर काय आहे?"\n• "फोटो घ्या" किंवा "लॉट सबमिट करा"';
      case AppLocale.en:
        return 'Hi! I am your Voice AI Assistant. You can say:\n• "Add 5 kg copper wire and 2 kg batteries"\n• "What is today\'s price of PCB?"\n• "Take photo" or "Submit lot"';
    }
  }
}
