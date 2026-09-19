import '../constants.dart';

class DisassemblyPart {
  final String part;
  final MaterialCategory category;
  final double weightSharePercent;
  final String conditionNotes;

  DisassemblyPart({
    required this.part,
    required this.category,
    required this.weightSharePercent,
    required this.conditionNotes,
  });

  factory DisassemblyPart.fromMap(Map<String, dynamic> map) {
    return DisassemblyPart(
      part: map['part'] as String? ?? 'Component',
      category: MaterialCategoryX.fromKey(map['category'] as String? ?? 'MIXED_OTHER'),
      weightSharePercent: (map['weight_share_percent'] as num?)?.toDouble() ?? 0.0,
      conditionNotes: map['condition_notes'] as String? ?? '',
    );
  }
}

class EwasteItem {
  final String id;
  final String name;
  final String cpcbCode;
  final List<String> aliases;
  final bool isCollectible;
  final String description;
  final String rejectionReason;
  final List<DisassemblyPart> disassemblyBreakdown;
  final List<String> hazardousElements;
  final String estimatedValueInr;

  EwasteItem({
    required this.id,
    required this.name,
    required this.cpcbCode,
    required this.aliases,
    required this.isCollectible,
    required this.description,
    required this.rejectionReason,
    required this.disassemblyBreakdown,
    required this.hazardousElements,
    required this.estimatedValueInr,
  });

  factory EwasteItem.fromMap(Map<String, dynamic> map) {
    return EwasteItem(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      cpcbCode: map['cpcb_code'] as String? ?? '',
      aliases: (map['aliases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      isCollectible: map['is_collectible'] as bool? ?? true,
      description: map['description'] as String? ?? '',
      rejectionReason: map['rejection_reason'] as String? ?? '',
      disassemblyBreakdown: (map['disassembly_breakdown'] as List<dynamic>?)
              ?.map((e) => DisassemblyPart.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      hazardousElements:
          (map['hazardous_elements'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      estimatedValueInr: map['estimated_value_inr'] as String? ?? '',
    );
  }
}

class CategoryGuide {
  final String categoryKey;
  final String name;
  final bool accepted;
  final String description;
  final List<String> subTypes;
  final List<String> valuableMaterials;
  final List<String> hazards;
  final String handlingGuidance;
  final double co2SavedKgPerKg;
  final String averageMarketPriceInr;

  CategoryGuide({
    required this.categoryKey,
    required this.name,
    required this.accepted,
    required this.description,
    required this.subTypes,
    required this.valuableMaterials,
    required this.hazards,
    required this.handlingGuidance,
    required this.co2SavedKgPerKg,
    required this.averageMarketPriceInr,
  });

  factory CategoryGuide.fromMap(String key, Map<String, dynamic> map) {
    return CategoryGuide(
      categoryKey: key,
      name: map['name'] as String? ?? key,
      accepted: map['accepted'] as bool? ?? true,
      description: map['description'] as String? ?? '',
      subTypes: (map['sub_types'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      valuableMaterials:
          (map['valuable_materials'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      hazards: (map['hazards'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      handlingGuidance: map['handling_guidance'] as String? ?? '',
      co2SavedKgPerKg: (map['co2_saved_kg_per_kg'] as num?)?.toDouble() ?? 0.0,
      averageMarketPriceInr: map['average_market_price_inr'] as String? ?? '',
    );
  }
}

class ProhibitedCategory {
  final String categoryName;
  final List<String> examples;
  final String rejectionReason;
  final String disposalRoute;

  ProhibitedCategory({
    required this.categoryName,
    required this.examples,
    required this.rejectionReason,
    required this.disposalRoute,
  });

  factory ProhibitedCategory.fromMap(Map<String, dynamic> map) {
    return ProhibitedCategory(
      categoryName: map['category_name'] as String? ?? '',
      examples: (map['examples'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      rejectionReason: map['rejection_reason'] as String? ?? '',
      disposalRoute: map['disposal_route'] as String? ?? '',
    );
  }
}
