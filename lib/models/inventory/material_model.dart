import 'package:cloud_firestore/cloud_firestore.dart';

/// Company material/stock register entry — Inventory module.
///
/// Unlike [AssetModel] (single item, one holder at a time), materials are
/// quantity-based: `quantityInStorage` is a denormalized running balance,
/// kept in sync by [InventoryService]'s receive/issue transaction. The
/// authoritative history lives in the append-only
/// `InventoryMaterialMovements` ledger — this field is a read optimization,
/// not the source of truth.
class MaterialModel {
  static const sourceLocal = 'Local';
  static const sourceInternational = 'International';

  static const conditionNew = 'New';
  static const conditionGood = 'Good';
  static const conditionFair = 'Fair';
  static const conditionDamaged = 'Damaged';

  final String id;
  final String name;
  final String category;
  final String unit; // e.g. bags, pieces, kg, m, litres
  final String source; // sourceLocal | sourceInternational
  final String? description;
  final String? photoUrl;
  final double quantityInStorage;
  final double reorderLevel; // below this, the material is "Low Stock"

  /// Condition recorded when the material was first registered — distinct
  /// from `conditionOnReceipt` captured on each individual receipt movement.
  final String initialCondition;

  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MaterialModel({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.source,
    this.description,
    this.photoUrl,
    required this.quantityInStorage,
    this.reorderLevel = 0,
    this.initialCondition = conditionGood,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOutOfStock => quantityInStorage <= 0;
  bool get isLowStock => !isOutOfStock && quantityInStorage <= reorderLevel;

  factory MaterialModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return MaterialModel(
      id: doc.id,
      name: data['name'] ?? '',
      category: data['category'] ?? '',
      unit: data['unit'] ?? '',
      source: data['source'] ?? sourceLocal,
      description: data['description'] as String?,
      photoUrl: data['photoUrl'] as String?,
      quantityInStorage: (data['quantityInStorage'] as num?)?.toDouble() ?? 0,
      reorderLevel: (data['reorderLevel'] as num?)?.toDouble() ?? 0,
      initialCondition: data['initialCondition'] ?? conditionGood,
      createdByUid: data['createdByUid'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'category': category,
      'unit': unit,
      'source': source,
      if (description != null) 'description': description,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'quantityInStorage': quantityInStorage,
      'reorderLevel': reorderLevel,
      'initialCondition': initialCondition,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
