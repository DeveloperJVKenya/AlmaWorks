/// Single source of truth for Assets/Tools category options, shared by the
/// Add forms (quick-pick chips) and the list-tab filter dropdowns so the two
/// can never drift out of sync with each other.
class InventoryCategories {
  InventoryCategories._();

  static const asset = <String>[
    'Heavy Equipment',
    'Vehicle',
    'IT Equipment / Electronics',
    'Office Equipment',
    'Furniture',
    'Safety Equipment',
    'Other',
  ];

  static const tool = <String>[
    'Power Tool',
    'Hand Tool',
    'Measuring Tool',
    'IT Equipment / Electronics',
    'Safety Tool',
    'Other',
  ];

  static const material = <String>[
    'Cement & Aggregates',
    'Steel & Metal',
    'Electrical',
    'Plumbing',
    'Timber',
    'Finishes',
    'Other',
  ];
}
