import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/constants.dart';
import 'core/services/anomaly_detection_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/carbon_credit_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/geo_service.dart';
import 'core/services/places_service.dart';
import 'core/services/pricing_service.dart';
import 'core/services/recycler_matching_service.dart';
import 'core/services/seed_data_service.dart';
import 'core/services/tts_service.dart';
import 'core/services/voice_ai_service.dart';
import 'core/services/ml/classifier_service.dart';
import 'core/services/ml/detector_service.dart';
import 'core/services/ml/ewaste_knowledge_service.dart';
import 'core/services/ml/ewaste_ai_service.dart';
import 'features/onboarding/root_router.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  }

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  final pricingService = PricingService();
  await pricingService.load();

  final firestoreService = FirestoreService();
  // Live, area-wise scrap rates (see ml/sync_metalmandi_prices.py) layer
  // over the bundled static table as they arrive -- no app release needed
  // to pick up a price change.
  firestoreService.watchLiveScrapPrices().listen(pricingService.applyLiveUpdates);

  final carbonCreditService = CarbonCreditService();
  await carbonCreditService.load();

  final classifierService = ClassifierService();
  await classifierService.load();

  final detectorService = DetectorService();
  await detectorService.load();

  final knowledgeService = EwasteKnowledgeService();
  await knowledgeService.load();

  final ewasteAiService = EwasteAiService(
    localClassifier: classifierService,
    localDetector: detectorService,
    knowledgeService: knowledgeService,
  );
  await ewasteAiService.init();

  final ttsService = TtsService();
  final voiceAiService = VoiceAiService(
    pricingService: pricingService,
    knowledgeService: knowledgeService,
    ttsService: ttsService,
    ewasteAiService: ewasteAiService,
  );
  await voiceAiService.initSpeech();

  final appState = AppState();
  await appState.loadPersisted();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        Provider.value(value: firestoreService),
        Provider.value(value: AuthService()),
        ChangeNotifierProvider.value(value: pricingService),
        Provider.value(value: carbonCreditService),
        Provider.value(value: AnomalyDetectionService(pricingService)),
        Provider.value(value: RecyclerMatchingService()),
        Provider.value(value: GeoService()),
        Provider.value(value: ttsService),
        ChangeNotifierProvider.value(value: voiceAiService),
        Provider.value(value: ConnectivityService()),
        Provider.value(value: SeedDataService()),
        Provider.value(value: PlacesService()),
        Provider.value(value: classifierService),
        Provider.value(value: detectorService),
        Provider.value(value: knowledgeService),
        Provider.value(value: ewasteAiService),
      ],
      child: const KabadiConnectApp(),
    ),
  );
}

class KabadiConnectApp extends StatelessWidget {
  const KabadiConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KabadiConnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBrandGreen, primary: kBrandGreen),
        appBarTheme: const AppBarTheme(backgroundColor: kBrandGreen, foregroundColor: Colors.white, elevation: 0),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kBrandGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      home: const RootRouter(),
    );
  }
}
