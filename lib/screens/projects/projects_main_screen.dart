import 'package:almaworks/models/project_model.dart';
import 'package:almaworks/providers/selected_project_provider.dart';
import 'package:almaworks/screens/projects/add_project_screen.dart';
import 'package:almaworks/screens/projects/edit_project_screen.dart';
import 'package:almaworks/screens/projects/project_summary_screen.dart';
import 'package:almaworks/services/project_service.dart';
import 'package:almaworks/widgets/base_layout.dart' show projectSummaryRouteName;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class ProjectsMainScreen extends StatefulWidget {
  final Logger logger;
  final int initialTabIndex;
  final List<String>? clientProjectIds;
  
  const ProjectsMainScreen({
    super.key,
    required this.logger,
    this.initialTabIndex = 0,
    this.clientProjectIds,
  });

  @override
  State<ProjectsMainScreen> createState() => _ProjectsMainScreenState();
}

class _ProjectsMainScreenState extends State<ProjectsMainScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  late final ProjectService _projectService;
  late final Logger _logger;
  
  String _statusFilter = 'All';
  bool _isLoading = true;
  
  int _allCount = 0;
  int _activeCount = 0;
  int _completedCount = 0;
  
  List<QueryDocumentSnapshot> _allProjects = [];

  bool get _isClientView => widget.clientProjectIds != null;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _logger = widget.logger;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _projectService = ProjectService();
    
    switch (widget.initialTabIndex) {
      case 0:
        _statusFilter = 'All';
        break;
      case 1:
        _statusFilter = 'active';
        break;
      case 2:
        _statusFilter = 'completed';
        break;
    }
    
    _logger.i('🏗️ ProjectsMainScreen: Initialized - isClientView: $_isClientView, clientProjects: ${widget.clientProjectIds?.length ?? 0}');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _logger.d('🎨 ProjectsMainScreen: Building UI, isLoading: $_isLoading');
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isClientView ? 'My Projects' : 'Projects',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A2E5A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildNavigationTabBar(),
          Expanded(
            child: _buildProjectsList(),
          ),
        ],
      ),
      floatingActionButton: _isClientView
          ? null
          : FloatingActionButton(
              onPressed: () async {
                _logger.i('➕ ProjectsMainScreen: Add project button pressed');
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddProjectScreen(logger: _logger),
                  ),
                );
                
                if (result == true) {
                  _logger.d('🔄 ProjectsMainScreen: Project added successfully');
                }
              },
              backgroundColor: const Color(0xFF0A2E5A),
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  Widget _buildNavigationTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha:0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        // Non-scrollable (the default) forces each tab into an equal,
        // fixed-width slot — on a narrower desktop window that's not wide
        // enough for "All Projects"/"Active"/"Completed" plus their count
        // badges, the Row inside each Tab can't shrink to fit, which is
        // exactly what threw the RenderFlex pixel-overflow. Scrollable
        // tabs size to their own natural content width instead and simply
        // scroll if the bar as a whole doesn't fit.
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: Theme.of(context).primaryColor,
        unselectedLabelColor: Colors.grey[600],
        indicatorColor: Theme.of(context).primaryColor,
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
        onTap: (index) {
          setState(() {
            switch (index) {
              case 0:
                _statusFilter = 'All';
                break;
              case 1:
                _statusFilter = 'active';
                break;
              case 2:
                _statusFilter = 'completed';
                break;
            }
          });
          _logger.d('📑 ProjectsMainScreen: Tab changed to index: $index, filter: $_statusFilter');
        },
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('All Projects'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _allCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Active'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _activeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Completed'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _completedCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Projects')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _isLoading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        if (snapshot.hasError) {
          _logger.e('Firestore error: ${snapshot.error}');
          return _buildContentWithFooter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading projects',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.red[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please check your connection and try again',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        if (!snapshot.hasData) {
          return _buildContentWithFooter(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        
        // Apply client project filtering if needed
        _allProjects = _isClientView
            ? snapshot.data!.docs.where((doc) {
                return widget.clientProjectIds!.contains(doc.id);
              }).toList()
            : snapshot.data!.docs;
        
        _isLoading = false;
        
        _logger.d('📊 ProjectsMainScreen: Filtered projects count: ${_allProjects.length}');
        
        _updateStatusCounts(_allProjects);
        
        final filteredProjects = _getFilteredProjects();
        
        if (filteredProjects.isEmpty) {
          final filterText = _statusFilter == 'All'
              ? (_isClientView 
                  ? 'No projects assigned to you yet' 
                  : 'No projects found')
              : (_isClientView
                  ? 'No $_statusFilter projects assigned to you'
                  : 'No $_statusFilter projects');
          
          return _buildContentWithFooter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      filterText,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!_isClientView) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tap the + button to create your first project',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        
        return RefreshIndicator(
          onRefresh: () async {
            _logger.i('🔄 ProjectsMainScreen: Pull to refresh triggered');
            setState(() {
              _isLoading = true;
            });
            await Future.delayed(const Duration(milliseconds: 500));
            setState(() {
              _isLoading = false;
            });
          },
          child: _buildContentWithFooter(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: filteredProjects.length,
              itemBuilder: (context, index) {
                try {
                  final project = ProjectModel.fromFirestore(filteredProjects[index]);
                  _logger.d('🏗️ ProjectsMainScreen: Building list item for project: ${project.name}');
                  
                  return _buildProjectCard(project, context);
                } catch (e) {
                  _logger.e('❌ ProjectsMainScreen: Error building project card at index $index: $e');
                  return const SizedBox.shrink();
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildContentWithFooter({required Widget child}) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                child,
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  color: const Color(0xFF0A2E5A),
                  child: Text(
                    '© 2026 JV Alma C.I.S Site Management System',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateStatusCounts(List<QueryDocumentSnapshot> allDocs) {
    final newAllCount = allDocs.length;
    int newActiveCount = 0;
    int newCompletedCount = 0;
    
    for (var doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'];
      
      switch (status) {
        case 'active':
          newActiveCount++;
          break;
        case 'completed':
          newCompletedCount++;
          break;
      }
    }
    
    if (_allCount != newAllCount ||
        _activeCount != newActiveCount ||
        _completedCount != newCompletedCount) {
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _allCount = newAllCount;
            _activeCount = newActiveCount;
            _completedCount = newCompletedCount;
          });
        }
      });
    }
  }

  List<QueryDocumentSnapshot> _getFilteredProjects() {
    if (_statusFilter == 'All') {
      return _allProjects;
    } else {
      return _allProjects.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['status'] == _statusFilter;
      }).toList();
    }
  }

  Widget _buildProjectCard(ProjectModel project, BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          _logger.i('👆 ProjectsMainScreen: Project tapped: ${project.name}');
          _navigateToProjectSummary(project, context);
        },
        onLongPress: _isClientView
            ? null
            : () {
                _logger.i('👆 ProjectsMainScreen: Project long pressed: ${project.name}');
                _showProjectOptions(context, project);
              },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _getStatusColor(project.status),
                    child: Text(
                      project.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          project.location,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(project.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              // Wrap (not Row) — on a narrow window there isn't always
              // room for budget + PM name + live progress on one line;
              // wrapping to a second line instead of a fixed Row avoids
              // forcing these below their natural width and overflowing.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (project.budget != null) ...[
                    Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
                    Text(
                      '\$${_formatBudget(project.budget!)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(Icons.person, size: 14, color: Colors.grey[600]),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      project.projectManager,
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ── Live progress from TaskProgressMonitor ──────────
                  StreamBuilder<double>(
                    stream: FirebaseFirestore.instance
                        .collection('TaskProgressMonitor')
                        .doc(project.id)
                        .snapshots()
                        .map(_computeProgressFromSnapshot),
                    builder: (context, snapshot) {
                      if (!project.isActive) return const SizedBox.shrink();
                      // Fallback to static value while the stream loads or on error.
                      final double raw = snapshot.hasData
                          ? snapshot.data!
                          : project.progress / 100.0;
                      final String pct = (raw * 100).toStringAsFixed(0);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up, size: 14, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            '$pct%',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String? status) {
    if (status == null) {
      return Chip(
        label: const Text('Untracked'),
        backgroundColor: Colors.grey.withValues(alpha:0.1),
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
    }
    
    return Chip(
      label: Text(_getStatusText(status)),
      backgroundColor: _getStatusColor(status).withValues(alpha:0.1),
      labelStyle: TextStyle(
        color: _getStatusColor(status),
        fontSize: 10,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  void _navigateToProjectSummary(ProjectModel project, BuildContext context) {
    _logger.i('🧭 ProjectsMainScreen: Navigating to project summary: ${project.name}');
    
    try {
      final provider = Provider.of<SelectedProjectProvider>(context, listen: false);
      provider.selectProject(project);
    } catch (e) {
      _logger.w('⚠️ ProjectsMainScreen: Provider not found in current context');
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: projectSummaryRouteName),
        builder: (context) => ChangeNotifierProvider(
          create: (context) => SelectedProjectProvider()..selectProject(project),
          child: ProjectSummaryScreen(
            project: project,
            logger: _logger,
          ),
        ),
      ),
    ).then((_) {
      _logger.d('🔙 ProjectsMainScreen: Returned from project summary');
    }).catchError((error) {
      _logger.e('❌ ProjectsMainScreen: Error navigating: $error');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error opening project: ${error.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
    });
  }

  void _showProjectOptions(BuildContext context, ProjectModel project) {
    _logger.i('📋 ProjectsMainScreen: Showing project options for: ${project.name}');
    
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View Details'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToProjectSummary(project, context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Project'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToEditProject(project, context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Project', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteProject(context, project);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToEditProject(ProjectModel project, BuildContext context) {
    _logger.i('✏️ ProjectsMainScreen: Navigating to edit project: ${project.name}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProjectScreen(
          project: project,
          logger: _logger,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _logger.d('🔄 ProjectsMainScreen: Project edited successfully');
      }
    });
  }

  void _confirmDeleteProject(BuildContext context, ProjectModel project) {
    _logger.i('❓ ProjectsMainScreen: Confirming delete for project: ${project.name}');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Project'),
          content: Text(
            'Are you sure you want to delete "${project.name}"? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                _logger.i('❌ ProjectsMainScreen: Delete cancelled');
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                _logger.i('✅ ProjectsMainScreen: Delete confirmed for: ${project.name}');
                
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                
                navigator.pop();
                
                try {
                  await _projectService.deleteProject(project.id);
                  _logger.i('✅ ProjectsMainScreen: Project deleted successfully');
                  
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Project "${project.name}" deleted successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  _logger.e('❌ ProjectsMainScreen: Error deleting project: $e');
                  
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Error deleting project: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  String _formatBudget(double budget) {
    if (budget >= 1000000) {
      return '${(budget / 1000000).toStringAsFixed(1)}M';
    } else if (budget >= 1000) {
      return '${(budget / 1000).toStringAsFixed(0)}K';
    } else {
      return budget.toStringAsFixed(0);
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      default:
        return 'Untracked';
    }
  }

  // ── TaskProgressMonitor helpers (mirrors TaskProgressMonitorScreen) ─────────

  /// Replicates the exact formula from TaskProgressMonitorScreen:
  ///   task %  = checkedDays / expectedWorkDays (or 1.0 once completed)
  ///   phase % = weighted average of its own tasks' progress (by expected days)
  ///   project % = EQUAL-weight average across phases — every phase counts as
  ///               1/N of the project regardless of task count or day-span
  ///               (4 phases → 25% each, 5 phases → 20% each, etc.)
  static double _computeProgressFromSnapshot(DocumentSnapshot snap) {
    if (!snap.exists) return 0.0;

    final data      = snap.data() as Map<String, dynamic>? ?? {};
    final rawRows   = data['rows']          as List<dynamic>?        ?? [];
    final rawStatus = data['dailyStatuses'] as Map<String, dynamic>? ?? {};

    final phaseIds = <String>{};
    // phaseId → (weightedSum, totalWeight)
    final phaseWeightedSum = <String, double>{};
    final phaseTotalWeight = <String, int>{};

    for (final entry in rawRows) {
      final m = Map<String, dynamic>.from(entry as Map);
      if ((m['type'] as String?) == 'phase') {
        final id = m['id'] as String? ?? '';
        if (id.isNotEmpty) phaseIds.add(id);
      }
    }

    for (final entry in rawRows) {
      final m = Map<String, dynamic>.from(entry as Map);
      if ((m['type'] as String?) != 'task') continue;

      final id             = m['id']             as String? ?? '';
      final parentPhaseId  = m['parentPhaseId']   as String?;
      final start          = (m['startDate'] as Timestamp?)?.toDate();
      final end            = (m['endDate']   as Timestamp?)?.toDate();
      if (start == null || end == null || id.isEmpty || parentPhaseId == null) {
        continue;
      }

      final expected = _countWorkDays(start, end);
      if (expected == 0) continue;

      bool hasCompleted = false;
      int checkedDays = 0;
      final prefix = '${id}_';
      for (final kv in rawStatus.entries) {
        if (!kv.key.startsWith(prefix)) continue;
        final code = kv.value as String?;
        if (code == 'X') {
          hasCompleted = true;
        } else if (code == 'D' || code == 'S' || code == 'O' || code == 'C') {
          checkedDays++;
        }
      }

      final taskProgress = hasCompleted
          ? 1.0
          : (checkedDays / expected).clamp(0.0, 1.0);

      phaseWeightedSum[parentPhaseId] =
          (phaseWeightedSum[parentPhaseId] ?? 0.0) + taskProgress * expected;
      phaseTotalWeight[parentPhaseId] =
          (phaseTotalWeight[parentPhaseId] ?? 0) + expected;
    }

    if (phaseIds.isEmpty) return 0.0;

    double total = 0.0;
    for (final phaseId in phaseIds) {
      final weight = phaseTotalWeight[phaseId] ?? 0;
      final sum    = phaseWeightedSum[phaseId] ?? 0.0;
      total += weight > 0 ? (sum / weight).clamp(0.0, 1.0) : 0.0;
    }
    return (total / phaseIds.length).clamp(0.0, 1.0);
  }

  /// Mon–Sat working days between [start] and [end] inclusive.
  static int _countWorkDays(DateTime start, DateTime end) {
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final endN   = DateTime(end.year,   end.month,   end.day);
    while (!cur.isAfter(endN)) {
      if (cur.weekday != DateTime.sunday) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  @override
  void dispose() {
    _logger.i('🧹 ProjectsMainScreen: Disposing tab controller');
    _tabController.dispose();
    super.dispose();
  }
}