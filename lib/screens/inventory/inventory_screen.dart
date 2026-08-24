import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/inventory/inventory_categories.dart';
import 'package:almaworks/models/inventory/material_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/screens/inventory/add_asset_screen.dart';
import 'package:almaworks/screens/inventory/add_material_screen.dart';
import 'package:almaworks/screens/inventory/asset_detail_screen.dart';
import 'package:almaworks/screens/inventory/inventory_colors.dart';
import 'package:almaworks/screens/inventory/inventory_providers.dart';
import 'package:almaworks/screens/inventory/material_detail_screen.dart';
import 'package:almaworks/screens/inventory/pending_fabrication_orders_screen.dart';
import 'package:almaworks/screens/inventory/pending_requests_screen.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:almaworks/widgets/inventory_form_section.dart' show inventoryInputDecoration;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

const _navy = InventoryColors.navy;

/// Company-wide Inventory: three tabs (Assets / Tools / Materials), each
/// with its own filters, list, detail navigation, and "Add" action — tabbed
/// the same way lib/screens/drawings_screen.dart is (single
/// FloatingActionButton whose action dispatches on the active tab index).
/// Data fetching goes through Riverpod (see inventory_providers.dart) so
/// switching tabs/filters never tears down and recreates the underlying
/// Firestore listeners.
class InventoryScreen extends ConsumerStatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const InventoryScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(userRoleProvider);
    final usernameAsync = ref.watch(usernameProvider);
    // Gates only the Assets/Tools/Materials streams below (not the rest of
    // the app — see roleMirrorSyncProvider's doc comment) so they never
    // subscribe before the UserRoles/{uid} mirror they depend on exists.
    final mirrorSyncAsync = ref.watch(roleMirrorSyncProvider);

    if (roleAsync.isLoading || usernameAsync.isLoading || mirrorSyncAsync.isLoading) {
      return BaseLayout(
        title: 'Inventory',
        project: widget.project,
        logger: widget.logger,
        selectedMenuItem: 'Inventory',
        onMenuItemSelected: (_) {},
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final role = roleAsync.value ?? 'Client';
    final username = usernameAsync.value ?? '';
    // MainAdmin and Admin share full inventory management + direct booking/
    // approval powers (see asset_detail_screen.dart's action-button split);
    // Technician reads + requests checkouts only, via isAuthorized below.
    final isAuthorized = role == 'MainAdmin' || role == 'Admin' || role == 'Technician';
    final isManager = role == 'MainAdmin' || role == 'Admin';
    final uid = ref.watch(currentUidProvider);

    if (!isAuthorized) {
      return BaseLayout(
        title: 'Inventory',
        project: widget.project,
        logger: widget.logger,
        selectedMenuItem: 'Inventory',
        onMenuItemSelected: (_) {},
        child: Center(
          child: Text(
            'You do not have access to Inventory.',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700]),
          ),
        ),
      );
    }

    return BaseLayout(
      title: 'Inventory',
      project: widget.project,
      logger: widget.logger,
      selectedMenuItem: 'Inventory',
      onMenuItemSelected: (_) {},
      actions: isManager
          ? [
              _buildPendingFabricationOrdersAction(context, uid, username, role),
              _buildPendingRequestsAction(context, uid, username, role),
            ]
          : null,
      floatingActionButton: isManager ? _buildFab(uid, username) : null,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: _navy,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: _navy,
              indicatorWeight: 3,
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
              unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 15),
              tabs: const [
                Tab(icon: Icon(Icons.precision_manufacturing_outlined, size: 20), text: 'Assets'),
                Tab(icon: Icon(Icons.handyman_outlined, size: 20), text: 'Tools'),
                Tab(icon: Icon(Icons.inventory_2_outlined, size: 20), text: 'Materials'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AssetLikeTab(
                  key: const PageStorageKey('inventory-assets-tab'),
                  itemType: AssetModel.typeAsset,
                  categoryOptions: const ['All', ...InventoryCategories.asset],
                  emptyLabel: 'No assets yet',
                  emptyHint: 'Assets you register will show up here.',
                  project: widget.project,
                  logger: widget.logger,
                  userRole: role,
                  username: username,
                  currentUid: uid,
                ),
                _AssetLikeTab(
                  key: const PageStorageKey('inventory-tools-tab'),
                  itemType: AssetModel.typeTool,
                  categoryOptions: const ['All', ...InventoryCategories.tool],
                  emptyLabel: 'No tools yet',
                  emptyHint: 'Tools you register will show up here.',
                  project: widget.project,
                  logger: widget.logger,
                  userRole: role,
                  username: username,
                  currentUid: uid,
                ),
                _MaterialsTab(
                  key: const PageStorageKey('inventory-materials-tab'),
                  project: widget.project,
                  logger: widget.logger,
                  userRole: role,
                  username: username,
                  currentUid: uid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFab(String uid, String username) {
    final labels = ['Add Asset', 'Add Tool', 'Add Material'];
    return FloatingActionButton.extended(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      elevation: 3,
      onPressed: () {
        switch (_tabController.index) {
          case 0:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddAssetScreen(
                  project: widget.project,
                  logger: widget.logger,
                  itemType: AssetModel.typeAsset,
                  createdByUid: uid,
                  createdByName: username,
                ),
              ),
            );
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddAssetScreen(
                  project: widget.project,
                  logger: widget.logger,
                  itemType: AssetModel.typeTool,
                  createdByUid: uid,
                  createdByName: username,
                ),
              ),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddMaterialScreen(
                  project: widget.project,
                  logger: widget.logger,
                  createdByUid: uid,
                  createdByName: username,
                ),
              ),
            );
            break;
        }
      },
      icon: const Icon(Icons.add),
      label: Text(labels[_tabController.index], style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildPendingFabricationOrdersAction(BuildContext context, String uid, String username, String role) {
    return Consumer(
      builder: (context, ref, _) {
        final ordersAsync = ref.watch(pendingFabricationOrdersProvider);
        final count = ordersAsync.valueOrNull?.length ?? 0;
        return IconButton(
          tooltip: 'Fabrication Orders',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PendingFabricationOrdersScreen(
                project: widget.project,
                logger: widget.logger,
                currentUid: uid,
                username: username,
                userRole: role,
              ),
            ),
          ),
          icon: Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            backgroundColor: InventoryColors.damaged,
            child: const Icon(Icons.precision_manufacturing_outlined),
          ),
        );
      },
    );
  }

  Widget _buildPendingRequestsAction(BuildContext context, String uid, String username, String role) {
    return Consumer(
      builder: (context, ref, _) {
        final requestsAsync = ref.watch(pendingRequestsProvider);
        final count = requestsAsync.valueOrNull?.length ?? 0;
        return IconButton(
          tooltip: 'Pending Requests',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PendingRequestsScreen(
                project: widget.project,
                logger: widget.logger,
                currentUid: uid,
                username: username,
                userRole: role,
              ),
            ),
          ),
          icon: Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            backgroundColor: const Color(0xFFE65100),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Shared responsive layout helper: a list on narrow screens, a
// multi-column grid on wide (web) screens.
// ════════════════════════════════════════════════════════════════════

Widget _responsiveItems({
  required BuildContext context,
  required int itemCount,
  required Widget Function(BuildContext, int) itemBuilder,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 720;
      if (!isWide) {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 420,
          mainAxisExtent: 96,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    },
  );
}

Widget _filterSurface({required List<Widget> children}) {
  return Container(
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

/// Shown when a stream provider hits an error — most commonly a
/// permission-denied while the UserRoles/{uid} mirror write is still
/// catching up right after login (see BaseLayout._fetchUserRoleAndAccess).
/// Since allAssetsStreamProvider/allMaterialsStreamProvider aren't
/// autoDispose, a listener that errors out stays cached in that error state
/// for the rest of the session unless something invalidates it — this
/// button is that "something," rather than requiring an app restart.
Widget _buildStreamErrorState(Object error, {required VoidCallback onRetry}) {
  final isPermissionDenied = error.toString().contains('permission-denied');
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
        const SizedBox(height: 12),
        Text(
          isPermissionDenied ? 'Access still syncing' : 'Error loading items',
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[800]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            isPermissionDenied
                ? 'Your access is still being confirmed — this usually resolves in a moment.'
                : 'Something went wrong loading this list.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text('Retry', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

Widget _emptyState({required IconData icon, required String label, required String hint}) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _navy.withValues(alpha: 0.06), shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: _navy.withValues(alpha: 0.35)),
        ),
        const SizedBox(height: 14),
        Text(label, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[800])),
        const SizedBox(height: 4),
        Text(hint, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════════════
// ASSETS / TOOLS TAB — identical shape, parameterized by itemType and
// the category options relevant to that type.
// ════════════════════════════════════════════════════════════════════

class _AssetLikeTab extends ConsumerStatefulWidget {
  final String itemType;
  final List<String> categoryOptions;
  final String emptyLabel;
  final String emptyHint;
  final ProjectModel project;
  final Logger logger;
  final String userRole;
  final String username;
  final String currentUid;

  const _AssetLikeTab({
    super.key,
    required this.itemType,
    required this.categoryOptions,
    required this.emptyLabel,
    required this.emptyHint,
    required this.project,
    required this.logger,
    required this.userRole,
    required this.username,
    required this.currentUid,
  });

  @override
  ConsumerState<_AssetLikeTab> createState() => _AssetLikeTabState();
}

class _AssetLikeTabState extends ConsumerState<_AssetLikeTab> with AutomaticKeepAliveClientMixin {
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _categoryFilter = 'All';

  static const _statusOptions = [
    'All',
    AssetModel.statusAvailable,
    AssetModel.statusCheckedOut,
    AssetModel.statusUnderMaintenance,
    AssetModel.statusRetired,
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final assetsAsync = ref.watch(allAssetsStreamProvider);

    // Category filter = presets ∪ whatever categories are actually present
    // in the data — so a custom category typed on the Add form (not one of
    // the presets) still shows up as a usable filter instead of becoming
    // invisible/unfindable.
    final itemsOfType =
        assetsAsync.valueOrNull?.where((a) => a.itemType == widget.itemType).toList() ?? const <AssetModel>[];
    final dynamicCategories = <String>{
      'All',
      ...widget.categoryOptions.where((c) => c != 'All'),
      ...itemsOfType.map((a) => a.category).where((c) => c.isNotEmpty),
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilters(dynamicCategories),
        Expanded(
          child: assetsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) {
              widget.logger.e('❌ InventoryScreen(${widget.itemType}): stream error $err');
              return _buildStreamErrorState(err, onRetry: () => ref.invalidate(allAssetsStreamProvider));
            },
            data: (allAssets) {
              final allOfType = allAssets.where((a) => a.itemType == widget.itemType).toList();
              final items = _applyFilters(allOfType);

              if (items.isEmpty) {
                return _emptyState(
                  icon: widget.itemType == AssetModel.typeTool ? Icons.handyman_outlined : Icons.precision_manufacturing_outlined,
                  label: widget.emptyLabel,
                  hint: widget.emptyHint,
                );
              }

              // For Tools, several identical units are commonly registered
              // as separate docs sharing one name (each keeps its own full
              // custody history — better for traceability than a single
              // shared quantity counter would be). This aggregates them by
              // name so "4 hammers, 2 checked out" reads as "2 of 4
              // available" instead of 4 separate, hard-to-relate rows.
              final quantityAgg = widget.itemType == AssetModel.typeTool
                  ? _computeQuantityAggregate(allOfType)
                  : const <String, ({int total, int available})>{};

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey('${_statusFilter}_${_categoryFilter}_${_searchQuery}_${items.length}'),
                  child: _responsiveItems(
                    context: context,
                    itemCount: items.length,
                    itemBuilder: (context, index) => _buildItemCard(items[index], quantityAgg),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<AssetModel> _applyFilters(List<AssetModel> items) {
    return items.where((item) {
      final matchesStatus = _statusFilter == 'All' || item.status == _statusFilter;
      final matchesCategory = _categoryFilter == 'All' || item.category == _categoryFilter;
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          (item.serialNumber?.toLowerCase().contains(query) ?? false);
      return matchesStatus && matchesCategory && matchesSearch;
    }).toList();
  }

  Widget _buildFilters(List<String> dynamicCategories) {
    // If the category currently selected in the filter no longer appears in
    // the live data (e.g. the only item with that category was re-edited to
    // a different one), fall back to "All" rather than risk a Dropdown
    // assertion error from a value with no matching item.
    final safeCategoryFilter = dynamicCategories.contains(_categoryFilter) ? _categoryFilter : 'All';
    return _filterSurface(children: [
      TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: inventoryInputDecoration(
          hint: 'Search ${widget.itemType.toLowerCase()}s...',
          icon: Icons.search,
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              isExpanded: true,
              decoration: inventoryInputDecoration(label: 'Status', icon: Icons.flag_outlined, isDense: true),
              items: _statusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: 13))))
                  .toList(),
              onChanged: (value) => setState(() => _statusFilter = value ?? 'All'),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: safeCategoryFilter,
              isExpanded: true,
              decoration: inventoryInputDecoration(label: 'Category', icon: Icons.category_outlined, isDense: true),
              items: dynamicCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.poppins(fontSize: 13))))
                  .toList(),
              onChanged: (value) => setState(() => _categoryFilter = value ?? 'All'),
            ),
          ),
        ],
      ),
    ]);
  }

  /// Groups same-named Tools (each still its own doc with its own full
  /// custody history) into a total/available count, keyed by lower-cased
  /// trimmed name. Not used for Assets — those are always individually
  /// unique (vehicles, heavy equipment), so a count would be meaningless.
  Map<String, ({int total, int available})> _computeQuantityAggregate(List<AssetModel> itemsOfType) {
    final totals = <String, int>{};
    final available = <String, int>{};
    for (final item in itemsOfType) {
      final key = item.name.trim().toLowerCase();
      totals[key] = (totals[key] ?? 0) + 1;
      if (item.isAvailable) available[key] = (available[key] ?? 0) + 1;
    }
    return {for (final key in totals.keys) key: (total: totals[key]!, available: available[key] ?? 0)};
  }

  Widget _buildItemCard(AssetModel item, Map<String, ({int total, int available})> quantityAgg) {
    final statusColor = InventoryColors.forAsset(item);
    final agg = quantityAgg[item.name.trim().toLowerCase()];
    final showQuantity = widget.itemType == AssetModel.typeTool && agg != null && agg.total > 1;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      // A status-colored left accent strip — a quicker visual read of an
      // item's state than the pill alone, and the same "colored edge"
      // language now used for the sidebar's active-item indicator.
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 4, color: statusColor),
            Expanded(child: _buildItemCardBody(item, statusColor, showQuantity ? agg : null)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCardBody(AssetModel item, Color statusColor, ({int total, int available})? quantity) {
    final statusLabel = item.hasPendingRequest
        ? 'Request Pending'
        : (item.status == AssetModel.statusAvailable && item.hasUpcomingBooking)
            ? 'Booked'
            : item.status;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AssetDetailScreen(
              project: widget.project,
              logger: widget.logger,
              assetId: item.id,
              userRole: widget.userRole,
              username: widget.username,
              currentUid: widget.currentUid,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [statusColor.withValues(alpha: 0.85), statusColor.withValues(alpha: 0.55)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.itemType == AssetModel.typeTool ? Icons.handyman_outlined : Icons.precision_manufacturing_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      item.currentHolderName != null ? '${item.category} • Held by ${item.currentHolderName}' : item.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (quantity != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${quantity.available} of ${quantity.total} available',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: quantity.available > 0 ? const Color(0xFF2E7D32) : Colors.red[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusLabel,
                    style: GoogleFonts.poppins(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// MATERIALS TAB — quantity-based, its own filter shape (source + stock
// status instead of custody status).
// ════════════════════════════════════════════════════════════════════

class _MaterialsTab extends ConsumerStatefulWidget {
  final ProjectModel project;
  final Logger logger;
  final String userRole;
  final String username;
  final String currentUid;

  const _MaterialsTab({
    super.key,
    required this.project,
    required this.logger,
    required this.userRole,
    required this.username,
    required this.currentUid,
  });

  @override
  ConsumerState<_MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends ConsumerState<_MaterialsTab> with AutomaticKeepAliveClientMixin {
  String _searchQuery = '';
  String _sourceFilter = 'All';
  String _stockFilter = 'All';
  String _categoryFilter = 'All';

  static const _sourceOptions = ['All', MaterialModel.sourceLocal, MaterialModel.sourceInternational];
  static const _stockOptions = ['All', 'In Stock', 'Low Stock', 'Out of Stock'];

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final materialsAsync = ref.watch(allMaterialsStreamProvider);

    // Category filter = presets ∪ whatever categories are actually present
    // in the data, same reasoning as the Assets/Tools tabs.
    final allMaterialsLoaded = materialsAsync.valueOrNull ?? const <MaterialModel>[];
    final dynamicCategories = <String>{
      'All',
      ...InventoryCategories.material.where((c) => c != 'Other'),
      ...allMaterialsLoaded.map((m) => m.category).where((c) => c.isNotEmpty),
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilters(dynamicCategories),
        Expanded(
          child: materialsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) {
              widget.logger.e('❌ InventoryScreen(Materials): stream error $err');
              return _buildStreamErrorState(err, onRetry: () => ref.invalidate(allMaterialsStreamProvider));
            },
            data: (allMaterials) {
              final materials = _applyFilters(allMaterials);

              if (materials.isEmpty) {
                return _emptyState(
                  icon: Icons.inventory_2_outlined,
                  label: 'No materials yet',
                  hint: 'Materials you register will show up here.',
                );
              }

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey('${_sourceFilter}_${_stockFilter}_${_categoryFilter}_${_searchQuery}_${materials.length}'),
                  child: _responsiveItems(
                    context: context,
                    itemCount: materials.length,
                    itemBuilder: (context, index) => _buildMaterialCard(materials[index]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<MaterialModel> _applyFilters(List<MaterialModel> materials) {
    return materials.where((m) {
      final matchesSource = _sourceFilter == 'All' || m.source == _sourceFilter;
      final matchesCategory = _categoryFilter == 'All' || m.category == _categoryFilter;
      final matchesStock = _stockFilter == 'All' ||
          (_stockFilter == 'Out of Stock' && m.isOutOfStock) ||
          (_stockFilter == 'Low Stock' && m.isLowStock) ||
          (_stockFilter == 'In Stock' && !m.isOutOfStock && !m.isLowStock);
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          m.name.toLowerCase().contains(query) ||
          m.category.toLowerCase().contains(query);
      return matchesSource && matchesCategory && matchesStock && matchesSearch;
    }).toList();
  }

  Widget _buildFilters(List<String> dynamicCategories) {
    final safeCategoryFilter = dynamicCategories.contains(_categoryFilter) ? _categoryFilter : 'All';
    return _filterSurface(children: [
      TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: inventoryInputDecoration(hint: 'Search materials...', icon: Icons.search, isDense: true),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: _sourceFilter,
              isExpanded: true,
              decoration: inventoryInputDecoration(label: 'Source', icon: Icons.public_outlined, isDense: true),
              items: _sourceOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: 13))))
                  .toList(),
              onChanged: (value) => setState(() => _sourceFilter = value ?? 'All'),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: _stockFilter,
              isExpanded: true,
              decoration: inventoryInputDecoration(label: 'Stock', icon: Icons.inventory_2_outlined, isDense: true),
              items: _stockOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: 13))))
                  .toList(),
              onChanged: (value) => setState(() => _stockFilter = value ?? 'All'),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: safeCategoryFilter,
              isExpanded: true,
              decoration: inventoryInputDecoration(label: 'Category', icon: Icons.category_outlined, isDense: true),
              items: dynamicCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.poppins(fontSize: 13))))
                  .toList(),
              onChanged: (value) => setState(() => _categoryFilter = value ?? 'All'),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildMaterialCard(MaterialModel material) {
    final stockColor = material.isOutOfStock
        ? Colors.red
        : material.isLowStock
            ? const Color(0xFFE65100)
            : const Color(0xFF2E7D32);
    final stockLabel = material.isOutOfStock ? 'Out of Stock' : (material.isLowStock ? 'Low Stock' : 'In Stock');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 4, color: stockColor),
            Expanded(child: _buildMaterialCardBody(material, stockColor, stockLabel)),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialCardBody(MaterialModel material, Color stockColor, String stockLabel) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MaterialDetailScreen(
              project: widget.project,
              logger: widget.logger,
              materialId: material.id,
              userRole: widget.userRole,
              username: widget.username,
              currentUid: widget.currentUid,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [stockColor.withValues(alpha: 0.85), stockColor.withValues(alpha: 0.55)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(material.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      '${material.category} • ${material.quantityInStorage} ${material.unit} • ${material.source}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stockColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(stockLabel,
                    style: GoogleFonts.poppins(fontSize: 10, color: stockColor, fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
