import 'package:flutter_test/flutter_test.dart';
import 'package:kabadiconnect/core/constants.dart';
import 'package:kabadiconnect/core/services/ml/ewaste_knowledge_service.dart';
import 'package:kabadiconnect/core/services/pricing_service.dart';
import 'package:kabadiconnect/core/services/tts_service.dart';
import 'package:kabadiconnect/core/services/voice_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PricingService pricingService;
  late EwasteKnowledgeService knowledgeService;
  late TtsService ttsService;
  late VoiceAiService voiceAiService;

  setUp(() async {
    pricingService = PricingService();
    knowledgeService = EwasteKnowledgeService();
    ttsService = TtsService();

    voiceAiService = VoiceAiService(
      pricingService: pricingService,
      knowledgeService: knowledgeService,
      ttsService: ttsService,
    );
  });

  group('VoiceAiService NLP Parsing Tests', () {
    test('Parses English lot addition with weight and condition', () async {
      final res = await voiceAiService.processInput(
        'Add 5 kg copper cable intact and 2 kg motherboard',
        locale: AppLocale.en,
        location: 'Mumbai',
      );

      expect(res.intent, VoiceIntent.addItem);
      expect(res.detectedItems.isNotEmpty, true);

      final categories = res.detectedItems.map((i) => i.category).toList();
      expect(categories.contains(MaterialCategory.cables), true);
      expect(categories.contains(MaterialCategory.pcb), true);

      final cableItem = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.cables);
      expect(cableItem.weightKg, 5.0);
      expect(cableItem.condition, 'intact');
    });

    test('Parses Hindi vernacular lot creation', () async {
      final res = await voiceAiService.processInput(
        '5 किलो कॉपर वायर और 2 किलो बैटरी',
        locale: AppLocale.hi,
        location: 'Delhi',
      );

      expect(res.intent, VoiceIntent.addItem);
      expect(res.detectedItems.length, 2);

      final cableItem = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.cables);
      expect(cableItem.weightKg, 5.0);

      final battItem = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.batteries);
      expect(battItem.weightKg, 2.0);
    });

    test('Parses Hinglish colloquial scrap phrasing', () async {
      final res = await voiceAiService.processInput(
        'taamba wire 8 kilo aur ek purani battery',
        locale: AppLocale.hi,
        location: 'Mumbai',
      );

      expect(res.intent, VoiceIntent.addItem);
      final categories = res.detectedItems.map((i) => i.category).toList();
      expect(categories.contains(MaterialCategory.cables), true);
      expect(categories.contains(MaterialCategory.batteries), true);
    });

    test('Parses scrap rate query', () async {
      final res = await voiceAiService.processInput(
        'battery ka kya bhav hai',
        locale: AppLocale.hi,
        location: 'Mumbai',
      );

      expect(res.intent, VoiceIntent.queryRate);
      expect(res.textReply.contains('भाव') || res.textReply.contains('बैटरी'), true);
    });

    test('Parses clear intent', () async {
      final res = await voiceAiService.processInput(
        'sab hatao',
        locale: AppLocale.hi,
        location: 'Mumbai',
      );

      expect(res.intent, VoiceIntent.clearAll);
    });

    test('Parses take photo command', () async {
      final res = await voiceAiService.processInput(
        'take photo',
        locale: AppLocale.en,
        location: 'Mumbai',
      );

      expect(res.intent, VoiceIntent.takePhoto);
    });

    test('Parses Marathi vernacular lot creation', () async {
      final res = await voiceAiService.processInput(
        '5 किलो कॉपर वायर आणि 2 बॅटरी',
        locale: AppLocale.mr,
        location: 'Pune',
      );

      expect(res.intent, VoiceIntent.addItem);
      expect(res.detectedItems.length, 2);

      final cableItem = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.cables);
      expect(cableItem.weightKg, 5.0);

      final battItem = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.batteries);
      expect(battItem.weightKg, 2.0);
    });

    test('Parses Hindi vernacular fractions (dedh, dhai)', () async {
      final res = await voiceAiService.processInput(
        'ढाई किलो बैटरी और डेढ़ किलो कॉपर वायर',
        locale: AppLocale.hi,
        location: 'Delhi',
      );

      expect(res.intent, VoiceIntent.addItem);
      final batt = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.batteries);
      expect(batt.weightKg, 2.5);

      final cable = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.cables);
      expect(cable.weightKg, 1.5);
    });

    test('Parses burnt/tampered condition', () async {
      final res = await voiceAiService.processInput(
        '4 kg burnt copper cable',
        locale: AppLocale.en,
        location: 'Mumbai',
      );

      expect(res.intent, VoiceIntent.addItem);
      final cable = res.detectedItems.firstWhere((i) => i.category == MaterialCategory.cables);
      expect(cable.condition, 'burnt/tampered');
    });

    test('Parses submit lot command', () async {
      final res = await voiceAiService.processInput(
        'submit lot',
        locale: AppLocale.en,
        location: 'Mumbai',
      );

      expect(res.intent, VoiceIntent.submitLot);
    });
  });
}
