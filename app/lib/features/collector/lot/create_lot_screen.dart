import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/lot.dart';
import '../../../core/services/ml/ewaste_ai_service.dart';
import '../../../core/services/pricing_service.dart';
import '../../../core/services/voice_ai_service.dart';
import '../../../widgets/floating_ai_assistant_button.dart';
import '../knowledge/ewaste_guide_screen.dart';
import '../scanner/continuous_lens_scanner_screen.dart';
import 'ai_voice_assistant_sheet.dart';
import 'checkout_screen.dart';

const _conditions = ['intact', 'partially_damaged', 'burnt/tampered', 'mixed_lot'];

/// Mutable state for one material row while it's being configured. Weight
/// starts at 0 on purpose -- the collector must type a real weight for
/// every row (including every AI-detected one) before the lot can proceed,
/// rather than silently carrying over a default. [rect] is the detector's
/// bounding box for this row (normalized to the photo), null for rows
/// added manually -- only rows with a rect get a box drawn on the photo.
class _ItemDraft {
  MaterialCategory? category;
  double? aiConfidence;
  bool aiIsReal = false;
  String condition = 'intact';
  final TextEditingController weightCtrl = TextEditingController(text: '0');
  Rect? rect;

  double get weight => double.tryParse(weightCtrl.text) ?? 0;

  void dispose() => weightCtrl.dispose();
}

/// One photo can hold several distinct materials, and the on-device
/// detector (see ml/train_detector.py) finds and localizes each one
/// directly -- not just "what's the one dominant material" but "where is
/// each item, and what is it," drawn as a labelled box per item on the
/// photo. Every detected item becomes its own row on this page, editable
/// like any manually-added row; if nothing is confidently detected, this
/// falls back to a single whole-photo classification (the old behaviour)
/// so there's always at least a starting suggestion. Every row --
/// including AI-detected ones -- starts at 0 kg so the collector has to
/// enter a real weight to proceed.
class CreateLotScreen extends StatefulWidget {
  final List<LotItem>? initialItems;
  const CreateLotScreen({super.key, this.initialItems});
  @override
  State<CreateLotScreen> createState() => _CreateLotScreenState();
}

class _CreateLotScreenState extends State<CreateLotScreen> {
  Uint8List? _photoBytes;
  Size? _photoSize; // decoded once per photo, shared by the main overlay and every row's thumbnail
  final List<_ItemDraft> _rows = [];
  int? _editingIndex; // row currently showing the category picker, if any
  bool _classifying = false;
  bool _isRejected = false;
  String? _rejectionReason;
  String? _identifiedDevice;
  String? _safetyWarning;
  bool _isOnlineAiUsed = false;

  final String _sourceType = 'household';

  @override
  void initState() {
    super.initState();
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      for (final item in widget.initialItems!) {
        final draft = _ItemDraft()
          ..category = item.category
          ..condition = item.condition
          ..aiIsReal = true;
        if (item.weightKg > 0) {
          draft.weightCtrl.text = item.weightKg.toStringAsFixed(1);
        }
        _rows.add(draft);
      }
    }
  }

  void _addVoiceItems(List<VoiceLotDraftItem> items) {
    setState(() {
      for (final it in items) {
        final draft = _ItemDraft()
          ..category = it.category
          ..condition = it.condition
          ..aiIsReal = true;
        if (it.weightKg > 0) {
          draft.weightCtrl.text = it.weightKg.toStringAsFixed(1);
        }
        _rows.add(draft);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${items.length} scrap item(s) from AI Assistant'),
        backgroundColor: kBrandGreen,
      ),
    );
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 800);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photoBytes = bytes;
      _photoSize = null;
      _isRejected = false;
      _rejectionReason = null;
      _identifiedDevice = null;
      _safetyWarning = null;
    });
    ui.decodeImageFromList(bytes, (image) {
      if (mounted) setState(() => _photoSize = Size(image.width.toDouble(), image.height.toDouble()));
    });
    // Only the first ever photo for this lot gets detected -- retaking it
    // just replaces the reference image, it doesn't rerun detection or
    // touch rows already added.
    if (_rows.isNotEmpty) return;
    setState(() => _classifying = true);

    final ewasteAi = context.read<EwasteAiService>();
    final analysis = await ewasteAi.analyzeImage(bytes);
    if (!mounted) return;

    if (!analysis.isCollectible) {
      setState(() {
        _isRejected = true;
        _rejectionReason = analysis.rejectionReason ??
            'This item is not recognized as an authorized recyclable e-waste category under India E-Waste Rules.';
        _identifiedDevice = analysis.itemName;
        _safetyWarning = null;
        _rows.clear();
        _classifying = false;
      });
      return;
    }

    setState(() {
      _isRejected = false;
      _rejectionReason = null;
      _identifiedDevice = analysis.itemName;
      _safetyWarning = analysis.safetyHazardWarning;
      _isOnlineAiUsed = analysis.isOnlineModel;

      if (analysis.components.isNotEmpty) {
        for (final comp in analysis.components) {
          final draft = _ItemDraft()
            ..category = comp.category
            ..aiConfidence = comp.confidence
            ..aiIsReal = true
            ..condition = comp.condition;
          if (comp.estimatedWeightKg > 0) {
            draft.weightCtrl.text = comp.estimatedWeightKg.toStringAsFixed(1);
          }
          _rows.add(draft);
        }
      } else {
        _rows.add(_ItemDraft()
          ..category = MaterialCategory.mixedOther
          ..aiConfidence = 0.5
          ..aiIsReal = false);
      }
      _classifying = false;
    });
  }

  void _showAiSettingsDialog(BuildContext context) {
    final ewasteAi = context.read<EwasteAiService>();
    final keyController = TextEditingController();
    bool useOnline = ewasteAi.useOnlineAi;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.psychology, color: kBrandGreen),
              SizedBox(width: 8),
              Text('AI Detection Settings'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hybrid AI Architecture: Combines on-device TFLite neural models with online Multimodal AI (Gemini) for deep device recognition & decomposition.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Online AI (Gemini)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Decomposes complex devices into recyclable parts and rejects non-ewaste with live internet knowledge', style: TextStyle(fontSize: 12)),
                  value: useOnline,
                  onChanged: (v) {
                    setDlgState(() => useOnline = v);
                    ewasteAi.setUseOnlineAi(v);
                  },
                ),
                const SizedBox(height: 10),
                const Text('Gemini API Key (Optional):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: ewasteAi.hasApiKey ? 'Key is set (enter to update)' : 'Paste API Key here',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'When offline or without an API key, the app automatically runs the on-device TFLite MobileNetV2 classifier & YOLO detector.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ElevatedButton(
              onPressed: () {
                if (keyController.text.trim().isNotEmpty) {
                  ewasteAi.setApiKey(keyController.text.trim());
                }
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AI settings saved successfully')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// The collector's registered address (from Places search) rarely matches
  /// one of the six cities the price/recycler datasets are keyed by, so
  /// snap it to the nearest one -- see nearestServiceLocation.
  String _priceLocationKey(AppState appState) {
    final c = appState.collector;
    if (c?.lat != null && c?.lng != null) return nearestServiceLocation(c!.lat!, c.lng!);
    return serviceLocations.first;
  }

  double _estimateFor(AppState appState, _ItemDraft row) {
    if (row.category == null) return 0;
    final pricing = context.read<PricingService>();
    return pricing.estimateValue(
      category: row.category!,
      location: _priceLocationKey(appState),
      weightKg: row.weight,
      condition: row.condition,
    );
  }

  void _addRow() => setState(() {
        _rows.add(_ItemDraft());
        _editingIndex = _rows.length - 1;
      });

  void _removeRow(int index) => setState(() {
        _rows[index].dispose();
        _rows.removeAt(index);
        // Every row after the removed one shifts down by one -- keep
        // _editingIndex pointing at the same row it was before, not
        // whatever now happens to sit at that numeric index.
        if (_editingIndex == index) {
          _editingIndex = null;
        } else if (_editingIndex != null && _editingIndex! > index) {
          _editingIndex = _editingIndex! - 1;
        }
      });

  bool get _allRowsValid => _rows.isNotEmpty && _rows.every((r) => r.category != null && r.weight > 0);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String t(String k) => AppStrings.t(k, appState.locale);
    final totalEstimate = _rows.fold<double>(0, (a, r) => a + _estimateFor(appState, r));

    return Scaffold(
      appBar: AppBar(
        title: Text(t('newLot')),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI Voice & Chat Copilot',
            onPressed: () => AiVoiceAssistantSheet.show(
              context,
              onApplyItems: _addVoiceItems,
              onTriggerCamera: () => _pickPhoto(ImageSource.camera),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.psychology),
            tooltip: 'AI Settings',
            onPressed: () => _showAiSettingsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.school),
            tooltip: 'E-Waste Guide',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EwasteGuideScreen())),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
            children: [
          _BoxedPhoto(bytes: _photoBytes, imageSize: _photoSize, rows: _rows, onPick: _pickPhoto, label: t('takePhoto'), retakeLabel: t('retake')),
          const SizedBox(height: 12),
          if (_classifying)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 14),
                Text(t('detectingMaterials'), style: TextStyle(color: Colors.grey.shade700)),
              ]),
            ),
          if (_isRejected) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade400, width: 1.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.block, color: Colors.red.shade700, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '⚠️ Item Not Accepted (${_identifiedDevice ?? "Non-E-Waste"})',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _rejectionReason ??
                        'Only authorized e-waste categories (electronics, displays, circuit boards, batteries, cables, motors, and e-plastics) are accepted by authorized recyclers.',
                    style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade900,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EwasteGuideScreen())),
                        icon: const Icon(Icons.school, size: 16),
                        label: const Text('View Accepted Guide'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retake'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (_identifiedDevice != null && !_isRejected) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(_isOnlineAiUsed ? Icons.auto_awesome : Icons.memory, color: Colors.green.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI Identified: $_identifiedDevice (${_isOnlineAiUsed ? "Gemini Multimodal AI" : "On-Device Neural Model"})',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_safetyWarning != null && !_isRejected) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hazard Precaution: $_safetyWarning',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (_rows.isNotEmpty) Text('${t('itemsInLot')} (${_rows.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._rows.asMap().entries.map((e) => _MaterialRowCard(
                index: e.key + 1,
                row: e.value,
                editing: _editingIndex == e.key,
                canRemove: _rows.length > 1,
                estimate: _estimateFor(appState, e.value),
                photoBytes: _photoBytes,
                photoSize: _photoSize,
                t: t,
                onSelectCategory: (c) => setState(() {
                  e.value.category = c;
                  _editingIndex = null;
                }),
                onChangeCategory: () => setState(() => _editingIndex = e.key),
                onWeightChanged: () => setState(() {}),
                onConditionChanged: (c) => setState(() => e.value.condition = c),
                onRemove: () => _removeRow(e.key),
              )),
          if (_photoBytes != null && !_classifying) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: Text(t('addAnotherMaterial'))),
          ],
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kBrandGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Text(t('estimatedValue'), style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 6),
                Text('₹${totalEstimate.toStringAsFixed(0)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: kBrandGreenDark)),
                if (_rows.isNotEmpty && !_allRowsValid)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(t('enterWeightHint'), style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (!_isRejected && _photoBytes != null && _allRowsValid) ? () => _proceedToCheckout(context) : null,
            child: Text(t('createLotBtn')),
          ),
          const SizedBox(height: 24),
        ],
      ),
      FloatingAiAssistantButton(
        bottomOffset: 20,
        rightOffset: 16,
        onApplyItems: _addVoiceItems,
        onTriggerCamera: () => _pickPhoto(ImageSource.camera),
      ),
    ],
  ),
);
  }

  void _proceedToCheckout(BuildContext context) {
    final appState = context.read<AppState>();
    final items = _rows
        .map((r) => LotItem(category: r.category!, condition: r.condition, weightKg: r.weight, estimatedValue: _estimateFor(appState, r)))
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckoutScreen(items: items, photoBytes: _photoBytes!, sourceType: _sourceType)),
    );
  }
}

/// One material's full editing surface: category (AI-suggested for the
/// first row, manually picked for every other row), weight, condition, and
/// its own running estimate -- always visible on the page, never hidden
/// behind a separate "draft" step, so a multi-material lot shows every item
/// at once and it's clear which row is which.
class _MaterialRowCard extends StatelessWidget {
  final int index;
  final _ItemDraft row;
  final bool editing;
  final bool canRemove;
  final double estimate;
  final Uint8List? photoBytes;
  final Size? photoSize;
  final String Function(String) t;
  final void Function(MaterialCategory) onSelectCategory;
  final VoidCallback onChangeCategory;
  final VoidCallback onWeightChanged;
  final void Function(String) onConditionChanged;
  final VoidCallback onRemove;

  const _MaterialRowCard({
    required this.index,
    required this.row,
    required this.editing,
    required this.canRemove,
    required this.estimate,
    required this.photoBytes,
    required this.photoSize,
    required this.t,
    required this.onSelectCategory,
    required this.onChangeCategory,
    required this.onWeightChanged,
    required this.onConditionChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: row.category?.color ?? Colors.grey,
                  child: Text('$index', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.category != null ? t('cat_${row.category!.key}') : t('chooseCategory'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (canRemove) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
              ],
            ),
            const SizedBox(height: 10),
            if (row.rect != null && row.category != null && photoBytes != null && photoSize != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(photoBytes!, fit: BoxFit.contain),
                      CustomPaint(painter: _BoxesPainter(imageSize: photoSize!, rows: [row], indexOffset: index - 1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (editing || row.category == null)
              _CategoryGrid(selected: row.category, onSelect: onSelectCategory, t: t)
            else ...[
              if (row.aiConfidence != null)
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: row.category!.color),
                    const SizedBox(width: 6),
                    Text(
                      '${(row.aiConfidence! * 100).toStringAsFixed(0)}% confident${row.aiIsReal ? '' : ' · basic detector on web'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const Spacer(),
                    TextButton(onPressed: onChangeCategory, child: const Text('Not correct?')),
                  ],
                )
              else
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: onChangeCategory, child: Text(t('changeMaterial')))),
              const SizedBox(height: 10),
              Text(t('weightKg'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: row.weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onWeightChanged(),
                decoration: const InputDecoration(border: OutlineInputBorder(), suffixText: 'kg', isDense: true),
              ),
              const SizedBox(height: 12),
              Text(t('condition'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: _conditions
                    .map((c) => ChoiceChip(
                          label: Text(t('cond_$c')),
                          selected: row.condition == c,
                          onSelected: (_) => onConditionChanged(c),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text('≈ ₹${estimate.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The photo plus a labelled, colour-coded box for every row that has a
/// detected [_ItemDraft.rect] -- drawn with BoxFit.contain math so the
/// boxes line up with the photo regardless of its aspect ratio. Rows added
/// manually (no rect) just don't get a box; the photo still shows fine.
class _BoxedPhoto extends StatelessWidget {
  final Uint8List? bytes;
  final Size? imageSize;
  final List<_ItemDraft> rows;
  final void Function(ImageSource) onPick;
  final String label;
  final String retakeLabel;
  const _BoxedPhoto({
    required this.bytes,
    required this.imageSize,
    required this.rows,
    required this.onPick,
    required this.label,
    required this.retakeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes!, fit: BoxFit.contain),
                  if (imageSize != null) CustomPaint(painter: _BoxesPainter(imageSize: imageSize!, rows: rows)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandGreen,
                  foregroundColor: Colors.white,
                  elevation: 2,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContinuousLensScannerScreen()),
                ),
                icon: const Icon(Icons.center_focus_strong, size: 20),
                label: const Text('Live AI Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: () => onPick(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              tooltip: 'Camera',
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () => onPick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              tooltip: 'Gallery',
            ),
          ],
        ),
      ],
    );
  }
}

/// Draws one labelled rectangle per row with a [_ItemDraft.rect], mapping
/// normalized [0,1] box coordinates through the same "fit inside, centred"
/// transform BoxFit.contain uses, so boxes track the photo exactly.
class _BoxesPainter extends CustomPainter {
  final Size imageSize;
  final List<_ItemDraft> rows;
  final int indexOffset; // lets a single-row thumbnail still show the row's real number
  _BoxesPainter({required this.imageSize, required this.rows, this.indexOffset = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;
    final scale = math.min(size.width / imageSize.width, size.height / imageSize.height);
    final dx = (size.width - imageSize.width * scale) / 2;
    final dy = (size.height - imageSize.height * scale) / 2;

    for (var i = 0; i < rows.length; i++) {
      final rect = rows[i].rect;
      final category = rows[i].category;
      if (rect == null || category == null) continue;
      final left = dx + rect.left * imageSize.width * scale;
      final top = dy + rect.top * imageSize.height * scale;
      final right = dx + rect.right * imageSize.width * scale;
      final bottom = dy + rect.bottom * imageSize.height * scale;

      final boxPaint = Paint()
        ..color = category.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), boxPaint);

      final tp = TextPainter(
        text: TextSpan(text: '${indexOffset + i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelTop = (top - 18).clamp(0.0, size.height - 18);
      canvas.drawRect(Rect.fromLTWH(left, labelTop, tp.width + 10, 18), Paint()..color = category.color);
      tp.paint(canvas, Offset(left + 5, labelTop + 1));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxesPainter oldDelegate) =>
      oldDelegate.imageSize != imageSize || oldDelegate.rows != rows || oldDelegate.indexOffset != indexOffset;
}

class _CategoryGrid extends StatelessWidget {
  final MaterialCategory? selected;
  final void Function(MaterialCategory) onSelect;
  final String Function(String) t;
  const _CategoryGrid({required this.selected, required this.onSelect, required this.t});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 4.2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: MaterialCategory.values.map((c) {
        final isSelected = selected == c;
        return Material(
          color: isSelected ? c.color : c.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(c.icon, color: isSelected ? Colors.white : c.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('cat_${c.key}'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : c.color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
