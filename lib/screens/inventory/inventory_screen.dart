import 'package:almaworks/models/inventory/asset_model.dart';
import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/rbacsystem/auth_service.dart';
import 'package:almaworks/screens/inventory/add_asset_screen.dart';
import 'package:almaworks/screens/inventory/asset_detail_screen.dart';
import 'package:almaworks/services/inventory_service.dart';
import 'package:almaworks/widgets/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

class InventoryScreen extends StatefulWidget {
  final ProjectModel project;
  final Logger logger;

  const InventoryScreen({
    super.key,
    required this.project,
    required this.logger,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final AuthService _authService = AuthService();
  final InventoryService _inventoryService = InventoryService();

  String? _userRole;
  String _username = '';
  bool _isLoadingUserData = true;

  String _searchQuery = '';
  String _statusFilter = 'All';

  static const _statusOptions = [
    'All',
    AssetModel.statusAvailable,
    AssetModel.statusCheckedOut,
    AssetModel.statusUnderMaintenance,
    AssetModel.statusRetired,
  ];

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final role = await _authService.getUserRole();
    final username = await _authService.getUsername();
    if (!mounted) return;
    setState(() {
      _userRole = role;
      _username = username;
      _isLoadingUserData = false;
    });
    widget.logger.i('📦 InventoryScreen: role=$role user=$username');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserData) {
      return BaseLayout(
        title: 'Inventory',
        project: widget.project,
        logger: widget.logger,
        selectedMenuItem: 'Inventory',
        onMenuItemSelected: (_) {},
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool isAuthorized = _userRole == 'MainAdmin' || _userRole == 'Admin';
    final bool isMainAdmin = _userRole == 'MainAdmin';

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
      floatingActionButton: isMainAdmin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddAssetScreen(
                    project: widget.project,
                    logger: widget.logger,
                    createdByUid: _authService.currentUser?.uid ?? '',
                    createdByName: _username,
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text('Add Asset', style: GoogleFonts.poppins()),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilters(),
          Expanded(
            child: StreamBuilder<List<AssetModel>>(
              stream: _inventoryService.streamAllAssets(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  widget.logger.e('❌ InventoryScreen: stream error ${snapshot.error}');
                  return Center(
                    child: Text('Error loading assets', style: GoogleFonts.poppins()),
                  );
                }

                final assets = _applyFilters(snapshot.data ?? const []);

                if (assets.isEmpty) {
                  return Center(
                    child: Text(
                      'No assets found',
                      style: GoogleFonts.poppins(color: Colors.grey[600]),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: assets.length,
                  itemBuilder: (context, index) => _buildAssetCard(assets[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<AssetModel> _applyFilters(List<AssetModel> assets) {
    return assets.where((asset) {
      final matchesStatus = _statusFilter == 'All' || asset.status == _statusFilter;
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          asset.name.toLowerCase().contains(query) ||
          asset.category.toLowerCase().contains(query) ||
          (asset.serialNumber?.toLowerCase().contains(query) ?? false);
      return matchesStatus && matchesSearch;
    }).toList();
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search assets...',
                hintStyle: GoogleFonts.poppins(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _statusFilter,
            items: _statusOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: 13))))
                .toList(),
            onChanged: (value) => setState(() => _statusFilter = value ?? 'All'),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetCard(AssetModel asset) {
    final statusColor = _statusColor(asset.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(Icons.build_outlined, color: statusColor),
        ),
        title: Text(asset.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        subtitle: Text(
          asset.currentHolderName != null
              ? '${asset.category} • Held by ${asset.currentHolderName}'
              : asset.category,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700]),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            asset.status,
            style: GoogleFonts.poppins(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
          ),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AssetDetailScreen(
              project: widget.project,
              logger: widget.logger,
              assetId: asset.id,
              userRole: _userRole!,
              username: _username,
              currentUid: _authService.currentUser?.uid ?? '',
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case AssetModel.statusAvailable:
        return const Color(0xFF2E7D32);
      case AssetModel.statusCheckedOut:
        return const Color(0xFF1565C0);
      case AssetModel.statusUnderMaintenance:
        return const Color(0xFFE65100);
      case AssetModel.statusRetired:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
