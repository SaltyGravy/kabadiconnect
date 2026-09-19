import 'dart:convert';
import 'package:flutter/services.dart';

import '../../constants.dart';
import '../../models/ewaste_item.dart';

class CollectibilityResult {
  final bool isCollectible;
  final String? matchedItemName;
  final String? rejectionReason;
  final List<DisassemblyPart> suggestedComponents;
  final List<String> hazardousWarnings;

  CollectibilityResult({
    required this.isCollectible,
    this.matchedItemName,
    this.rejectionReason,
    this.suggestedComponents = const [],
    this.hazardousWarnings = const [],
  });
}

class EwasteKnowledgeService {
  final Map<String, CategoryGuide> _categoryGuides = {};
  final List<ProhibitedCategory> _prohibitedCategories = [];
  final List<EwasteItem> _items = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<EwasteItem> get allItems => List.unmodifiable(_items);
  List<ProhibitedCategory> get prohibitedCategories => List.unmodifiable(_prohibitedCategories);
  Map<String, CategoryGuide> get categoryGuides => Map.unmodifiable(_categoryGuides);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/ml/ewaste_knowledge_base.json');
      final data = json.decode(raw) as Map<String, dynamic>;

      // Load collection category guides
      final cats = data['collection_categories'] as Map<String, dynamic>? ?? {};
      cats.forEach((key, val) {
        _categoryGuides[key] = CategoryGuide.fromMap(key, val as Map<String, dynamic>);
      });

      // Load prohibited items
      final prohibited = data['prohibited_and_rejected_items'] as List<dynamic>? ?? [];
      _prohibitedCategories.clear();
      for (final p in prohibited) {
        _prohibitedCategories.add(ProhibitedCategory.fromMap(p as Map<String, dynamic>));
      }

      // Load items catalogue
      final itemsList = data['electronic_items_catalogue'] as List<dynamic>? ?? [];
      _items.clear();
      for (final item in itemsList) {
        _items.add(EwasteItem.fromMap(item as Map<String, dynamic>));
      }

      _loaded = true;
    } catch (e) {
      // Keep empty if load fails
      _loaded = false;
    }
  }

  List<EwasteItem> search(String query) {
    if (query.trim().isEmpty) return _items;
    final q = query.trim().toLowerCase();
    return _items.where((item) {
      if (item.name.toLowerCase().contains(q)) return true;
      if (item.cpcbCode.toLowerCase().contains(q)) return true;
      if (item.description.toLowerCase().contains(q)) return true;
      for (final alias in item.aliases) {
        if (alias.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  CategoryGuide? getGuideForCategory(MaterialCategory category) {
    return _categoryGuides[category.key];
  }

  CollectibilityResult checkCollectibility(String text) {
    final lower = text.trim().toLowerCase();

    // Check prohibited categories first
    for (final prohibited in _prohibitedCategories) {
      for (final ex in prohibited.examples) {
        if (lower.contains(ex.toLowerCase()) || ex.toLowerCase().contains(lower)) {
          return CollectibilityResult(
            isCollectible: false,
            matchedItemName: prohibited.categoryName,
            rejectionReason: prohibited.rejectionReason,
          );
        }
      }
    }

    // Check known items catalogue
    for (final item in _items) {
      final matchesName = lower.contains(item.name.toLowerCase()) || item.name.toLowerCase().contains(lower);
      final matchesAlias = item.aliases.any((a) => lower.contains(a.toLowerCase()) || a.toLowerCase().contains(lower));
      if (matchesName || matchesAlias) {
        if (!item.isCollectible) {
          return CollectibilityResult(
            isCollectible: false,
            matchedItemName: item.name,
            rejectionReason: item.rejectionReason,
          );
        }
        return CollectibilityResult(
          isCollectible: true,
          matchedItemName: item.name,
          suggestedComponents: item.disassemblyBreakdown,
          hazardousWarnings: item.hazardousElements,
        );
      }
    }

    // Default neutral acceptance if not recognized as non-collectible
    return CollectibilityResult(
      isCollectible: true,
      suggestedComponents: [],
      hazardousWarnings: [],
    );
  }
}
