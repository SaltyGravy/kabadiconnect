import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/models/lot.dart';
import '../../../core/services/ml/classifier_service.dart';
import '../../../core/services/ml/ewaste_ai_service.dart';
import '../../../core/services/pricing_service.dart';
import '../knowledge/ewaste_guide_screen.dart';
import '../lot/checkout_screen.dart';

/// Fullscreen Continuous AI Scanner like Google Lens.
///
/// Points at scrap, continuously identifies material and live rates using a
/// fast ON-DEVICE-ONLY classifier (no network calls in this loop -- that was
/// the cause of severe lag when the live HUD used the full analyzeImage
/// pipeline, which can call a remote model). Tapping the shutter runs the
/// full (possibly online) analysis once, pops up a weight dialog, and ADDS
/// the item to this scan session's lot -- the camera stays live so the
/// collector can keep scanning more items into the SAME lot. "Proceed to
/// Checkout" is a separate, explicit action once at least one item has
/// been added.
class ContinuousLensScannerScreen extends StatefulWidget {
  const ContinuousLensScannerScreen({super.key});

  @override
  State<ContinuousLensScannerScreen> createState() => _ContinuousLensScannerScreenState();
}

class _ContinuousLensScannerScreenState extends State<ContinuousLensScannerScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isFlashOn = false;
  bool _isCapturing = false;

  // Continuous Detection state -- local classifier only, see class doc.
  Timer? _continuousScanTimer;
  bool _isScanningFrame = false;
  bool _scanningPaused = false;
  MaterialCategory? _liveCategory;
  double _liveConfidence = 0.0;
  bool _liveIsCollectible = true;
  String? _liveRejectionReason;

  // This scan session's accumulating lot -- items added via the weight
  // popup pile up here across multiple shutter presses; nothing is sent to
  // checkout until the collector explicitly asks to proceed.
  final List<LotItem> _lotItems = [];
  Uint8List? _lotPhotoBytes;

  // Laser sweep animation
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();

    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.15, end: 0.85).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _isCameraInitialized = false);
        return;
      }

      final camera = _cameras[_selectedCameraIndex];
      _cameraController = CameraController(
        camera,
        // Medium is plenty for on-device AI + a receipt-style photo, and
        // capturing at "high" on every ~2s continuous tick was a big part
        // of the lag -- lower resolution stills are much faster to take,
        // encode, and read back.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
      _startContinuousScanning();
    } catch (_) {
      if (mounted) setState(() => _isCameraInitialized = false);
    }
  }

  void _startContinuousScanning() {
    // Scan every 2s for the live HUD. Only the fast on-device classifier
    // runs here -- never the online/network path -- so a slow or missing
    // internet connection can't stall the live preview.
    _continuousScanTimer = Timer.periodic(const Duration(milliseconds: 2000), (timer) async {
      if (!mounted || _scanningPaused || _cameraController == null || !_cameraController!.value.isInitialized) return;
      if (_isScanningFrame || _isCapturing) return;

      try {
        _isScanningFrame = true;
        final xfile = await _cameraController!.takePicture();
        final bytes = await xfile.readAsBytes();
        if (!mounted) return;

        final classifier = context.read<ClassifierService>();
        final result = await classifier.classify(bytes);

        if (mounted) {
          setState(() {
            _liveIsCollectible = result.isCollectible;
            _liveRejectionReason = result.rejectionReason;
            _liveCategory = result.isCollectible ? result.category : null;
            _liveConfidence = result.confidence;
          });
        }
      } catch (_) {
        // Silent catch for background preview scans
      } finally {
        _isScanningFrame = false;
      }
    });
  }

  @override
  void dispose() {
    _continuousScanTimer?.cancel();
    _laserController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _cameraController?.dispose();
    setState(() => _isCameraInitialized = false);
    _initCamera();
  }

  /// Shutter Click: Freeze frame, run the full (possibly online) analysis,
  /// and show the weight popup. The continuous loop pauses for this --
  /// no point burning a background capture while the shutter's own capture
  /// and the popup are in flight.
  Future<void> _onCapture() async {
    if (_isCapturing) return;
    setState(() {
      _isCapturing = true;
      _scanningPaused = true;
    });

    try {
      Uint8List imageBytes;
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final xfile = await _cameraController!.takePicture();
        imageBytes = await xfile.readAsBytes();
      } else {
        final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1000);
        if (file == null) {
          setState(() {
            _isCapturing = false;
            _scanningPaused = false;
          });
          return;
        }
        imageBytes = await file.readAsBytes();
      }

      if (!mounted) return;

      final ewasteAi = context.read<EwasteAiService>();
      final analysis = await ewasteAi.analyzeImage(imageBytes);

      if (!mounted) return;

      if (!analysis.isCollectible) {
        setState(() => _scanningPaused = false);
        _showRejectedDialog(analysis.itemName, analysis.rejectionReason);
        return;
      }

      final initialCategory = analysis.components.isNotEmpty
          ? analysis.components.first.category
          : (_liveCategory ?? MaterialCategory.pcb);

      final initialCondition = analysis.components.isNotEmpty
          ? analysis.components.first.condition
          : 'intact';

      _showQuickWeightDialog(
        imageBytes: imageBytes,
        category: initialCategory,
        condition: initialCondition,
        itemName: analysis.itemName,
        safetyWarning: analysis.safetyHazardWarning,
      );
    } catch (e) {
      setState(() => _scanningPaused = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _showRejectedDialog(String itemName, String? reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('Item Not Accepted'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Identified: $itemName',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              reason ??
                  'This item is non-electronic waste and cannot be collected under India E-Waste Management Rules.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EwasteGuideScreen()));
            },
            child: const Text('View Guide'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Scan Again'),
          ),
        ],
      ),
    );
  }

  String _getLocation(AppState appState) {
    final c = appState.collector;
    if (c?.lat != null && c?.lng != null) return nearestServiceLocation(c!.lat!, c.lng!);
    return serviceLocations.first;
  }

  /// Instant Weight Popup Modal Dialog. Confirming ADDS the item to this
  /// session's accumulating lot and returns to the live scanner -- it does
  /// NOT jump to checkout. Proceeding to checkout is a separate, explicit
  /// action from the main scanner screen once >=1 item has been added.
  void _showQuickWeightDialog({
    required Uint8List imageBytes,
    required MaterialCategory category,
    required String condition,
    required String itemName,
    String? safetyWarning,
  }) {
    final appState = context.read<AppState>();
    final pricing = context.read<PricingService>();
    final location = _getLocation(appState);

    MaterialCategory selectedCategory = category;
    String selectedCondition = condition;
    double weightKg = 1.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final rate = pricing.currentRate(selectedCategory, location) ?? 50.0;
          final estimatedVal = pricing.estimateValue(
            category: selectedCategory,
            location: location,
            weightKg: weightKg,
            condition: selectedCondition,
          );

          return Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                if (_lotItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${_lotItems.length} item(s) already in this lot',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(imageBytes, width: 60, height: 60, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(selectedCategory.icon, size: 18, color: selectedCategory.color),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  itemName.isNotEmpty ? itemName : selectedCategory.key,
                                  maxLines: 1,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Live Rate: ₹${rate.toStringAsFixed(0)}/kg ($location)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_note, color: kBrandGreen),
                      tooltip: 'Change Material',
                      onPressed: () {
                        _showCategorySelector(ctx, (newCat) {
                          setDlgState(() => selectedCategory = newCat);
                        });
                      },
                    ),
                  ],
                ),

                if (safetyWarning != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(safetyWarning, style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Text('Enter Scrap Weight:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: kBrandGreen, size: 30),
                        onPressed: () {
                          if (weightKg > 0.5) setDlgState(() => weightKg = (weightKg - 0.5));
                        },
                      ),
                      Text(
                        '${weightKg.toStringAsFixed(1)} kg',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kBrandGreenDark),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: kBrandGreen, size: 30),
                        onPressed: () => setDlgState(() => weightKg = (weightKg + 0.5)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _WeightChip(label: '+0.5 kg', onAdd: () => setDlgState(() => weightKg += 0.5)),
                      _WeightChip(label: '+1 kg', onAdd: () => setDlgState(() => weightKg += 1.0)),
                      _WeightChip(label: '+2 kg', onAdd: () => setDlgState(() => weightKg += 2.0)),
                      _WeightChip(label: '+5 kg', onAdd: () => setDlgState(() => weightKg += 5.0)),
                      _WeightChip(label: '+10 kg', onAdd: () => setDlgState(() => weightKg += 10.0)),
                      _WeightChip(label: '+25 kg', onAdd: () => setDlgState(() => weightKg += 25.0)),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Condition: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ...['intact', 'partially_damaged', 'burnt/tampered'].map((c) {
                      final isSelected = selectedCondition == c;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            c == 'intact' ? 'Intact' : (c == 'partially_damaged' ? 'Damaged' : 'Burnt'),
                            style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87),
                          ),
                          selected: isSelected,
                          selectedColor: kBrandGreen,
                          onSelected: (val) {
                            if (val) setDlgState(() => selectedCondition = c);
                          },
                        ),
                      );
                    }),
                  ],
                ),

                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kBrandGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBrandGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Estimated Value', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          Text(
                            '₹${estimatedVal.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: kBrandGreenDark),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBrandGreen,
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _lotItems.add(LotItem(
                          category: selectedCategory,
                          condition: selectedCondition,
                          weightKg: weightKg,
                          estimatedValue: estimatedVal,
                        ));
                        _lotPhotoBytes ??= imageBytes;
                        _scanningPaused = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          backgroundColor: kBrandGreen,
                          content: Text('Added to lot -- ${_lotItems.length} item(s) so far. Keep scanning or checkout below.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_task, size: 22),
                    label: const Text('Add to Lot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      // If the sheet was dismissed without confirming (swipe-down / tap
      // outside), still resume the live loop.
      if (mounted) setState(() => _scanningPaused = false);
    });
  }

  void _showCategorySelector(BuildContext context, Function(MaterialCategory) onSelect) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Select Material Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ...MaterialCategory.values.map((cat) => ListTile(
                leading: Icon(cat.icon, color: cat.color),
                title: Text(cat.key),
                onTap: () {
                  onSelect(cat);
                  Navigator.pop(ctx);
                },
              )),
        ],
      ),
    );
  }

  Future<void> _proceedToCheckout() async {
    if (_lotItems.isEmpty || _lotPhotoBytes == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proceed to checkout?'),
        content: Text('This lot has ${_lotItems.length} item(s). Review and confirm on the next screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Scanning')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Proceed')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(items: List.of(_lotItems), photoBytes: _lotPhotoBytes!, sourceType: 'household'),
      ),
    );
  }

  Future<bool> _confirmExit() async {
    if (_lotItems.isEmpty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard scanned items?'),
        content: Text('You have ${_lotItems.length} item(s) not yet checked out. Leaving now discards them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard & Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  /// Fits the camera preview to fill the screen while preserving its native
  /// aspect ratio (crop-to-fill, "BoxFit.cover"-style) -- StackFit.expand
  /// alone stretches/distorts the image since the sensor's aspect ratio
  /// almost never matches the phone screen's.
  Widget _buildCameraPreview(Size screenSize) {
    final controller = _cameraController!;
    var scale = screenSize.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return Transform.scale(
      scale: scale,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final pricing = context.watch<PricingService>();
    final location = _getLocation(appState);
    final screenSize = MediaQuery.of(context).size;

    final displayRate = _liveCategory != null ? (pricing.currentRate(_liveCategory!, location) ?? 50.0) : null;
    final lotTotal = _lotItems.fold<double>(0, (a, i) => a + i.estimatedValue);

    return PopScope(
      canPop: _lotItems.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _confirmExit();
        if (!shouldLeave || !mounted) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_isCameraInitialized && _cameraController != null)
              _buildCameraPreview(screenSize)
            else
              Container(
                color: Colors.black87,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: kBrandGreen),
                      SizedBox(height: 16),
                      Text('Starting Continuous AI Camera...', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),

            // Reticle overlay
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boxWidth = constraints.maxWidth * 0.76;
                  final boxHeight = constraints.maxHeight * 0.40;

                  return Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: boxWidth,
                          height: boxHeight,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24, width: 1.5),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: CustomPaint(painter: _ReticleCornerPainter(color: kBrandGreen)),
                        ),
                        AnimatedBuilder(
                          animation: _laserAnimation,
                          builder: (context, child) {
                            return Positioned(
                              top: (boxHeight * _laserAnimation.value),
                              child: Container(
                                width: boxWidth - 20,
                                height: 2.5,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      kBrandGreen.withValues(alpha: 0.1),
                                      kBrandGreen,
                                      kBrandGreen.withValues(alpha: 0.1),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: kBrandGreen.withValues(alpha: 0.8), blurRadius: 8, spreadRadius: 1),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Top action bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () async {
                          if (await _confirmExit() && context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kBrandGreen.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, color: kBrandGreen, size: 14),
                          SizedBox(width: 6),
                          Text('AI Continuous Lens', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: _isFlashOn ? Colors.amber : Colors.white),
                        onPressed: _toggleFlash,
                      ),
                    ),
                    if (_cameras.length > 1) ...[
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.black45,
                        child: IconButton(
                          icon: const Icon(Icons.flip_camera_android, color: Colors.white),
                          onPressed: _switchCamera,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom cluster: lot summary + live pill + shutter row, all
            // anchored inside a bottom SafeArea so gesture-nav insets don't
            // push the shutter under the system bar.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_lotItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildLotSummaryBar(lotTotal),
                      ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildLiveDetectionPill(displayRate, location),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white24,
                          child: IconButton(
                            icon: const Icon(Icons.photo_library, color: Colors.white),
                            tooltip: 'Gallery',
                            onPressed: () async {
                              final ewasteAi = context.read<EwasteAiService>();
                              final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000);
                              if (file == null) return;
                              final bytes = await file.readAsBytes();
                              setState(() => _scanningPaused = true);
                              final analysis = await ewasteAi.analyzeImage(bytes);
                              if (!mounted) return;
                              if (!analysis.isCollectible) {
                                setState(() => _scanningPaused = false);
                                _showRejectedDialog(analysis.itemName, analysis.rejectionReason);
                                return;
                              }
                              _showQuickWeightDialog(
                                imageBytes: bytes,
                                category: analysis.components.isNotEmpty ? analysis.components.first.category : MaterialCategory.pcb,
                                condition: 'intact',
                                itemName: analysis.itemName,
                              );
                            },
                          ),
                        ),
                        GestureDetector(
                          onTap: _isCapturing ? null : _onCapture,
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [kBrandGreen, kBrandGreenDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [BoxShadow(color: kBrandGreen.withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)],
                              ),
                              child: _isCapturing
                                  ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)))
                                  : const Icon(Icons.camera, color: Colors.white, size: 36),
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white24,
                          child: IconButton(
                            icon: const Icon(Icons.school, color: Colors.white),
                            tooltip: 'Accepted Scrap Guide',
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EwasteGuideScreen())),
                          ),
                        ),
                      ],
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

  Widget _buildLotSummaryBar(double lotTotal) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _proceedToCheckout,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: kBrandGreen,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory_2, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_lotItems.length} item(s) in this lot · ₹${lotTotal.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const Text('Checkout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveDetectionPill(double? rate, String location) {
    if (!_liveIsCollectible && _liveRejectionReason != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.red.shade400, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: const Row(
          children: [
            Icon(Icons.block, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Not accepted -- point at e-waste',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (_liveCategory == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Point camera at e-waste to scan...', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBrandGreen, width: 1.5),
        boxShadow: [BoxShadow(color: kBrandGreen.withValues(alpha: 0.35), blurRadius: 12)],
      ),
      child: Row(
        children: [
          Icon(_liveCategory!.icon, color: _liveCategory!.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _liveCategory!.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  'Tap shutter to add to lot · ${(_liveConfidence * 100).toStringAsFixed(0)}% match',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (rate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: kBrandGreen, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '₹${rate.toStringAsFixed(0)}/kg',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeightChip extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;
  const _WeightChip({required this.label, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        backgroundColor: kBrandGreen.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kBrandGreen.withValues(alpha: 0.3)),
        ),
        onPressed: onAdd,
      ),
    );
  }
}

/// Custom painter for Google Lens corner brackets
class _ReticleCornerPainter extends CustomPainter {
  final Color color;
  const _ReticleCornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 28.0;

    canvas.drawLine(const Offset(0, cornerLength), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(cornerLength, 0), paint);

    canvas.drawLine(Offset(size.width - cornerLength, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);

    canvas.drawLine(Offset(0, size.height - cornerLength), Offset(0, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);

    canvas.drawLine(Offset(size.width - cornerLength, size.height), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height - cornerLength), Offset(size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
