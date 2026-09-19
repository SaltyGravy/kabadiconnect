import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants.dart';
import 'classifier_service.dart';
import 'detector_service.dart';
import 'ewaste_knowledge_service.dart';

class AiAnalysisComponent {
  final MaterialCategory category;
  final double estimatedWeightKg;
  final String condition;
  final double confidence;
  final String description;

  AiAnalysisComponent({
    required this.category,
    required this.estimatedWeightKg,
    required this.condition,
    required this.confidence,
    required this.description,
  });
}

class AiAnalysisResult {
  final bool isCollectible;
  final String itemName;
  final String? rejectionReason;
  final List<AiAnalysisComponent> components;
  final String? safetyHazardWarning;
  final bool isOnlineModel;

  AiAnalysisResult({
    required this.isCollectible,
    required this.itemName,
    this.rejectionReason,
    this.components = const [],
    this.safetyHazardWarning,
    required this.isOnlineModel,
  });
}

class EwasteAiService {
  static const String _prefApiKey = 'gemini_api_key';
  static const String _prefUseOnlineAi = 'use_online_ai';

  // Bundled fallback key, injected only at build time via
  // `--dart-define=GEMINI_API_KEY=...` -- never hardcoded in source, so it
  // never lands in git. Empty string when not provided at build time (e.g.
  // local `flutter run` during development). A collector's own key, pasted
  // via Settings, always takes priority over this default.
  static const String _buildTimeApiKey = String.fromEnvironment('GEMINI_API_KEY');

  final ClassifierService localClassifier;
  final DetectorService localDetector;
  final EwasteKnowledgeService knowledgeService;

  String? _apiKey;
  bool _useOnlineAi = true;

  EwasteAiService({
    required this.localClassifier,
    required this.localDetector,
    required this.knowledgeService,
  });

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = prefs.getString(_prefApiKey);
    _apiKey = (userKey != null && userKey.trim().isNotEmpty)
        ? userKey
        : (_buildTimeApiKey.trim().isNotEmpty ? _buildTimeApiKey : null);
    _useOnlineAi = prefs.getBool(_prefUseOnlineAi) ?? true;
  }

  bool get hasApiKey => _apiKey != null && _apiKey!.trim().isNotEmpty;
  String? get apiKey => _apiKey;
  bool get useOnlineAi => _useOnlineAi;

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiKey, _apiKey!);
  }

  Future<void> setUseOnlineAi(bool enable) async {
    _useOnlineAi = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefUseOnlineAi, enable);
  }

  Future<AiAnalysisResult> analyzeImage(Uint8List imageBytes) async {
    // 1. If online AI enabled & key present, attempt Multimodal AI analysis
    if (_useOnlineAi && hasApiKey) {
      try {
        final onlineResult = await _analyzeWithGemini(imageBytes);
        if (onlineResult != null) return onlineResult;
      } catch (_) {
        // Fall back gracefully to offline processing
      }
    }

    // 2. Offline / Local fallback: Multi-Item Detector + Classifier + Knowledge Service
    return await _analyzeLocally(imageBytes);
  }

  Future<AiAnalysisResult?> _analyzeWithGemini(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);
    // gemini-flash-latest is a Google-maintained alias that always points
    // at their current recommended fast multimodal model -- avoids the
    // request silently 404ing again when a pinned version (like the old
    // gemini-1.5-flash) gets deprecated out from under us.
    final endpoint =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=$_apiKey';

    const promptText = '''
You are an expert e-waste recycling auditor in India operating under the E-Waste (Management) Rules, 2022.
Analyze this photo taken by a scrap collector or recycler.

Target Recyclable Categories (ONLY these 8 are collected):
- BATTERIES: Lithium-ion, lead-acid, 18650 cells, phone/laptop batteries
- CABLES: Insulated copper wiring, power cords, harnesses
- CRT: Cathode ray tube TVs, CRT computer monitors, picture tubes
- LCD_LED: Flat LCD/LED television panels, laptop screens, monitors
- PCB: Computer motherboards, phone PCBs, green/blue circuit boards
- MOTORS_MAGNETS: Electric motors, copper stators, transformers, HDD neodymium magnets
- MIXED_PLASTICS: Rigid engineering ABS/HIPS plastic casings from electronics
- MIXED_OTHER: Unsorted e-waste scrap

Instructions:
1. Identify the item in the image.
2. Determine if it is collectible e-waste. If it is NOT e-waste (e.g. food waste, regular plastic bottle/packaging, clothing, furniture, bio-medical waste, animal, ordinary trash), set "is_collectible": false and give a clear "rejection_reason".
3. If it IS collectible e-waste, identify which components are visible or can be harvested, mapping each to one of the 8 category keys above. For each component, provide "estimated_weight_kg", "condition" ("intact", "partially_damaged", "burnt/tampered", "mixed_lot"), and "confidence" (0.0 to 1.0).
4. If there are hazardous constituents (mercury, lead, toxic electrolyte, high voltage charge), note them in "safety_hazard_warning".

Respond ONLY with valid JSON in this exact structure:
{
  "item_name": "Device or item name",
  "is_collectible": true,
  "rejection_reason": null,
  "components": [
    {
      "category": "BATTERIES",
      "estimated_weight_kg": 0.25,
      "condition": "intact",
      "confidence": 0.95,
      "description": "Lithium-ion battery pack"
    }
  ],
  "safety_hazard_warning": "Warning text if applicable"
}
''';

    final body = json.encode({
      'contents': [
        {
          'parts': [
            {'text': promptText},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'response_mime_type': 'application/json',
        'temperature': 0.2,
      }
    });

    final resp = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode != 200) return null;

    final data = json.decode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) return null;

    final rawJson = parts[0]['text'] as String?;
    if (rawJson == null) return null;

    final parsed = json.decode(rawJson) as Map<String, dynamic>;
    final isCollectible = parsed['is_collectible'] as bool? ?? true;
    final itemName = parsed['item_name'] as String? ?? 'Electronic Item';
    final rejectionReason = parsed['rejection_reason'] as String?;
    final safetyWarning = parsed['safety_hazard_warning'] as String?;

    final componentsList = <AiAnalysisComponent>[];
    if (parsed['components'] is List) {
      for (final c in parsed['components'] as List) {
        final m = c as Map<String, dynamic>;
        final catKey = m['category'] as String? ?? 'MIXED_OTHER';
        componentsList.add(AiAnalysisComponent(
          category: MaterialCategoryX.fromKey(catKey),
          estimatedWeightKg: (m['estimated_weight_kg'] as num?)?.toDouble() ?? 1.0,
          condition: m['condition'] as String? ?? 'intact',
          confidence: (m['confidence'] as num?)?.toDouble() ?? 0.9,
          description: m['description'] as String? ?? '',
        ));
      }
    }

    return AiAnalysisResult(
      isCollectible: isCollectible,
      itemName: itemName,
      rejectionReason: rejectionReason,
      components: componentsList,
      safetyHazardWarning: safetyWarning,
      isOnlineModel: true,
    );
  }

  Future<AiAnalysisResult> _analyzeLocally(Uint8List imageBytes) async {
    // 1. Run classifier first to verify collectibility and reject non-e-waste garbage
    final classResult = await localClassifier.classify(imageBytes);

    // If classifier detects NON_COLLECTIBLE or low confidence, reject immediately
    if (!classResult.isCollectible) {
      return AiAnalysisResult(
        isCollectible: false,
        itemName: 'Non-E-Waste Item',
        rejectionReason: classResult.rejectionReason ??
            'The AI recognized this item as non-collectible municipal waste (e.g. plastic bottles, cardboard packaging, food scraps). Only authorized e-waste categories are collected.',
        isOnlineModel: false,
      );
    }

    // 2. Run detector to localize individual items / components
    final detections = await localDetector.detect(imageBytes);
    if (detections.isNotEmpty) {
      final components = detections
          .map((d) => AiAnalysisComponent(
                category: d.category,
                estimatedWeightKg: 1.5,
                condition: 'intact',
                confidence: d.confidence,
                description: '${d.category.key} detected',
              ))
          .toList();

      final firstCat = detections.first.category;
      final guide = knowledgeService.getGuideForCategory(firstCat);

      return AiAnalysisResult(
        isCollectible: true,
        itemName: guide?.name ?? firstCat.key,
        components: components,
        safetyHazardWarning: guide?.hazards.isNotEmpty == true ? guide!.hazards.first : null,
        isOnlineModel: false,
      );
    }

    // 3. Fallback to whole-photo classifier if detector found no localized boxes
    if (classResult.confidence < 0.20) {
      return AiAnalysisResult(
        isCollectible: false,
        itemName: 'Unrecognized Item',
        rejectionReason:
            'The AI could not confidently identify this item as an accepted e-waste category. Only authorized electronics, circuit boards, batteries, displays, cables, and e-plastics are collected.',
        isOnlineModel: false,
      );
    }

    final cat = classResult.category;
    final guide = knowledgeService.getGuideForCategory(cat);

    return AiAnalysisResult(
      isCollectible: true,
      itemName: guide?.name ?? cat.key,
      components: [
        AiAnalysisComponent(
          category: cat,
          estimatedWeightKg: 2.0,
          condition: 'mixed_lot',
          confidence: classResult.confidence,
          description: 'Classified as ${cat.key}',
        )
      ],
      safetyHazardWarning: guide?.hazards.isNotEmpty == true ? guide!.hazards.first : null,
      isOnlineModel: false,
    );
  }
}
