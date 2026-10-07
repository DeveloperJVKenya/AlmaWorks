import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/models/purchase_resource_model.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class PurchasingPlanScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final Logger logger;
  final ProjectModel project;

  const PurchasingPlanScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.logger,
    required this.project,
  });

  @override
  State<PurchasingPlanScreen> createState() => _PurchasingPlanScreenState();
}

class _PurchasingPlanScreenState extends State<PurchasingPlanScreen> {
  int _totalResources = 0;
  int _onSiteCount = 0;
  int _inStorageCount = 0;
  int _orderedCount = 0;
  int _notOrderedCount = 0;
  int _notAvailableCount = 0;

  @override
  void initState() {
    super.initState();
    widget.logger.i(
      '🛒 PurchasingPlan: Initialized for project: ${widget.projectName} (ID: ${widget.projectId})',
    );
  }

  void _updateSummary(List<PurchaseResourceModel> resources) {
    _totalResources = resources.length;
    _onSiteCount = resources.where((r) => r.status == 'On site').length;
    _inStorageCount = resources.where((r) => r.status == 'In storage').length;
    _notOrderedCount = resources.where((r) => r.status == 'Not Ordered').length;
    _orderedCount = resources.where((r) => r.status == 'Ordered').length;
    _notAvailableCount = resources.where((r) => r.status == 'Not Available').length;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('PurchaseplanResources')
          .where('projectId', isEqualTo: widget.projectId)
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e('❌ PurchasingPlan: Error in stream', error: snapshot.error);
          return Center(child: Text('Error loading resources', style: TextStyle(color: Colors.red)));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        List<PurchaseResourceModel> resources = [];
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final resource = PurchaseResourceModel.fromFirebaseMap(doc.id, data);
          resources.add(resource);
        }

        _updateSummary(resources);

        if (resources.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummaryCards(),
              const SizedBox(height: 16),
              _buildAddResourceButton(),
              const SizedBox(height: 16),
              ...resources.map((resource) => _buildResourceItem(resource)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Resources Added',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add resources to manage your purchasing plan',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addResource,
            icon: const Icon(Icons.add),
            label: Text('Add First Resource', style: TextStyle()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A2E5A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine screen type and optimal layout
        final width = constraints.maxWidth;
        final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        
        int crossAxisCount;
        double childAspectRatio;
        double spacing;
        
        // Desktop (wide screens)
        if (width > 1200) {
          crossAxisCount = 6;
          childAspectRatio = 1.2;
          spacing = 16;
        }
        // Tablet landscape or medium desktop
        else if (width > 900) {
          crossAxisCount = 6;
          childAspectRatio = 1.1;
          spacing = 12;
        }
        // Tablet portrait or small desktop
        else if (width > 600) {
          crossAxisCount = isPortrait ? 3 : 6;
          childAspectRatio = isPortrait ? 1.2 : 1.1;
          spacing = 12;
        }
        // Large phone landscape
        else if (width > 500 && !isPortrait) {
          crossAxisCount = 4;
          childAspectRatio = 1.1;
          spacing = 8;
        }
        // Phone portrait or small phone landscape
        else {
          crossAxisCount = isPortrait ? 2 : 3;
          childAspectRatio = isPortrait ? 1.9 : 1.4;
          spacing = 8;
        }

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: childAspectRatio,
          children: [
            _buildSummaryCard('Total', _totalResources, Icons.list, Colors.blue, width),
            _buildSummaryCard('On Site', _onSiteCount, Icons.location_on, Colors.green, width),
            _buildSummaryCard('In Storage', _inStorageCount, Icons.warehouse, Colors.blueGrey, width),
            _buildSummaryCard('Not Ordered', _notOrderedCount, Icons.shopping_cart, Colors.orange, width),
            _buildSummaryCard('Ordered', _orderedCount, Icons.local_shipping, Colors.teal, width),
            _buildSummaryCard('Not Available', _notAvailableCount, Icons.block, Colors.red, width),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(String title, int count, IconData icon, Color color, double screenWidth) {
    // Responsive sizing based on screen width
    double iconSize;
    double countSize;
    double titleSize;
    double cardPadding;
    
    if (screenWidth > 1200) {
      iconSize = 32;
      countSize = 24;
      titleSize = 14;
      cardPadding = 12;
    } else if (screenWidth > 900) {
      iconSize = 28;
      countSize = 22;
      titleSize = 13;
      cardPadding = 10;
    } else if (screenWidth > 600) {
      iconSize = 26;
      countSize = 20;
      titleSize = 12;
      cardPadding = 10;
    } else if (screenWidth > 400) {
      iconSize = 24;
      countSize = 18;
      titleSize = 11;
      cardPadding = 8;
    } else {
      iconSize = 22;
      countSize = 16;
      titleSize = 10;
      cardPadding = 6;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: color),
            SizedBox(height: cardPadding * 0.5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: countSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: cardPadding * 0.25),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: titleSize,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddResourceButton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        return ElevatedButton.icon(
          onPressed: _addResource,
          icon: const Icon(Icons.add),
          label: Text(
            'Add Resource',
            style: TextStyle(fontSize: isWide ? 16 : 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0A2E5A),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: isWide ? 16 : 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
    );
  }

  Widget _buildResourceItem(PurchaseResourceModel resource) {
    IconData typeIcon;
    switch (resource.type) {
      case ResourceType.material:
        typeIcon = Icons.inventory;
        break;
      case ResourceType.equipment:
        typeIcon = Icons.build;
        break;
      case ResourceType.labor:
        typeIcon = Icons.people;
        break;
      case ResourceType.other:
        typeIcon = Icons.category;
        break;
    }

    Color statusColor;
    switch (resource.status) {
      case 'On site':
        statusColor = Colors.green;
        break;
      case 'Not Ordered':
        statusColor = Colors.orange;
        break;
      case 'Ordered':
        statusColor = Colors.teal;
        break;
      case 'Not Available':
        statusColor = Colors.red;
        break;
      case 'In storage':
        statusColor = Colors.blueGrey;
        break;
      default:
        statusColor = Colors.grey;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: isWide ? 16 : 12,
              vertical: isWide ? 8 : 4,
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(typeIcon, color: Colors.blue.shade800, size: isWide ? 24 : 20),
            ),
            title: Text(
              resource.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: isWide ? 16 : 14,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.straighten, size: isWide ? 14 : 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        resource.quantity,
                        style: TextStyle(fontSize: isWide ? 14 : 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.circle, size: isWide ? 14 : 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      resource.status,
                      style: TextStyle(
                        fontSize: isWide ? 14 : 12,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) => _handleResourceAction(value, resource),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addResource() async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController();
    String selectedType = 'material';
    String selectedStatus = 'On site';

    final typeOptions = ['material', 'equipment', 'labor', 'other'];
    final statusOptions = ['On site', 'Not Ordered', 'Ordered', 'Not Available', 'In storage'];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Add Resource', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity (e.g., 500 kg)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: typeOptions.map((type) => DropdownMenuItem(value: type, child: Text(type.capitalize()))).toList(),
                  onChanged: (value) => setState(() => selectedType = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: statusOptions.map((status) => DropdownMenuItem(value: status, child: Text(status))).toList(),
                  onChanged: (value) => setState(() => selectedStatus = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty && quantityController.text.isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      await FirebaseFirestore.instance.collection('PurchaseplanResources').add(
        PurchaseResourceModel(
          id: '',
          name: nameController.text,
          type: PurchaseResourceModel.parseResourceType(selectedType),
          quantity: quantityController.text,
          status: selectedStatus,
          projectId: widget.projectId,
          projectName: widget.projectName,
          updatedAt: DateTime.now(),
        ).toFirebaseMap(),
      );
      widget.logger.i('🛒 PurchasingPlan: Added new resource: ${nameController.text}');
    } catch (e) {
      widget.logger.e('❌ PurchasingPlan: Error adding resource', error: e);
    }
  }

  Future<void> _handleResourceAction(String action, PurchaseResourceModel resource) async {
    if (action == 'edit') {
      final nameController = TextEditingController(text: resource.name);
      final quantityController = TextEditingController(text: resource.quantity);
      String selectedType = resource.type.toString().split('.').last;
      String selectedStatus = resource.status;

      final typeOptions = ['material', 'equipment', 'labor', 'other'];
      final statusOptions = ['On site', 'Not Ordered', 'Ordered', 'Not Available', 'In storage'];

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Edit Resource', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity (e.g., 500 kg)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: typeOptions.map((type) => DropdownMenuItem(value: type, child: Text(type.capitalize()))).toList(),
                    onChanged: (value) => setState(() => selectedType = value!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: statusOptions.map((status) => DropdownMenuItem(value: status, child: Text(status))).toList(),
                    onChanged: (value) => setState(() => selectedStatus = value!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty && quantityController.text.isNotEmpty) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );

      if (result != true) return;

      try {
        await FirebaseFirestore.instance.collection('PurchaseplanResources').doc(resource.id).update(
          PurchaseResourceModel(
            id: resource.id,
            name: nameController.text,
            type: PurchaseResourceModel.parseResourceType(selectedType),
            quantity: quantityController.text,
            status: selectedStatus,
            projectId: widget.projectId,
            projectName: widget.projectName,
            updatedAt: DateTime.now(),
          ).toFirebaseMap(),
        );
        widget.logger.i('🛒 PurchasingPlan: Updated resource: ${resource.id}');
      } catch (e) {
        widget.logger.e('❌ PurchasingPlan: Error updating resource', error: e);
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Resource', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to delete "${resource.name}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
      );

      if (confirm != true) return;

      try {
        await FirebaseFirestore.instance.collection('PurchaseplanResources').doc(resource.id).delete();
        widget.logger.i('🛒 PurchasingPlan: Deleted resource: ${resource.id}');
      } catch (e) {
        widget.logger.e('❌ PurchasingPlan: Error deleting resource', error: e);
      }
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}