import 'package:cloud_firestore/cloud_firestore.dart';

class TeamMember {
  final String name;
  final String role; // 'subcontractor', 'supplier', 'technician', 'manager'
  final String? category;

  TeamMember({
    required this.name,
    required this.role,
    this.category,
  });

  factory TeamMember.fromMap(Map<String, dynamic> map) {
    return TeamMember(
      name: map['name'] ?? '',
      role: map['role'] ?? '',
      category: map['category'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'role': role,
      if (category != null) 'category': category,
    };
  }

  TeamMember copyWith({
    String? name,
    String? role,
    String? category,
  }) {
    return TeamMember(
      name: name ?? this.name,
      role: role ?? this.role,
      category: category ?? this.category,
    );
  }
}

class ProjectModel {
  final String id;
  final String name;
  final String description;
  final String location;
  final String? contractNumber;
  final double? budget;
  final String? status; 
  final DateTime startDate;
  final DateTime? endDate;
  final String projectManager;
  final List<TeamMember> teamMembers;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectModel({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    this.contractNumber,
    this.budget,
    this.status,
    required this.startDate,
    this.endDate,
    required this.projectManager,
    required this.teamMembers,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProjectModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final teamMembersData = data['teamMembers'] as List<dynamic>? ?? <dynamic>[];
    final List<TeamMember> parsedTeamMembers = <TeamMember>[];
    for (final item in teamMembersData) {
      if (item is String) {
        parsedTeamMembers.add(TeamMember(name: item, role: 'team_member', category: null));
      } else if (item is Map<String, dynamic>) {
        try {
          parsedTeamMembers.add(TeamMember.fromMap(item));
        } catch (e) {
          // Skip invalid map
          continue;
        }
      } else {
        // Skip invalid item
        continue;
      }
    }
    final teamMembers = List<TeamMember>.from(parsedTeamMembers);
    return ProjectModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] ?? '',
      contractNumber: data['contractNumber'] as String?,
      budget: data['budget']?.toDouble(),
      status: data['status'], // Can be null
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: data['endDate'] != null ? (data['endDate'] as Timestamp).toDate() : null,
      projectManager: data['projectManager'] ?? '',
      teamMembers: teamMembers,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'location': location,
      if (contractNumber != null && contractNumber!.isNotEmpty)
        'contractNumber': contractNumber,
      'budget': budget,
      'status': status,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'projectManager': projectManager,
      'teamMembers': teamMembers.map((m) => m.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  ProjectModel copyWith({
    String? name,
    String? description,
    String? location,
    String? contractNumber,
    double? budget,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    String? projectManager,
    List<TeamMember>? teamMembers,
    DateTime? updatedAt,
  }) {
    return ProjectModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      contractNumber: contractNumber ?? this.contractNumber,
      budget: budget ?? this.budget,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      projectManager: projectManager ?? this.projectManager,
      teamMembers: teamMembers ?? this.teamMembers,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  bool get isTracked => status != null;
  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';

  // Calculate progress based on project dates and status
  double get progress {
    if (status == 'completed') return 100.0;
    if (status != 'active') return 0.0;
    
    final now = DateTime.now();
    if (now.isBefore(startDate)) return 0.0;
    
    if (endDate == null) {
      // If no end date, calculate based on time elapsed (rough estimate)
      final daysSinceStart = now.difference(startDate).inDays;
      // Assume 1% progress per week for active projects without end date
      return (daysSinceStart / 7).clamp(0.0, 90.0);
    }
    
    final totalDays = endDate!.difference(startDate).inDays;
    final elapsedDays = now.difference(startDate).inDays;
    
    if (totalDays <= 0) return 0.0;
    
    return ((elapsedDays / totalDays) * 100).clamp(0.0, 100.0);
  }

  // Calculate safety score (placeholder - will be based on real data later)
  double get safetyScore {
    // For now, return 0.0 as requested
    // Later this will be calculated from safety incidents, inspections, etc.
    return 0.0;
  }

  // Calculate quality score (placeholder - will be based on real data later)
  double get qualityScore {
    // For now, return 0.0 as requested
    // Later this will be calculated from quality inspections, defects, etc.
    return 0.0;
  }

  // Get project health status based on progress and timeline
  String get healthStatus {
    if (status != 'active') return 'N/A';
    
    final progressValue = progress;
    final now = DateTime.now();
    
    if (endDate != null && now.isAfter(endDate!)) {
      return progressValue >= 100 ? 'Completed' : 'Overdue';
    }
    
    if (progressValue >= 90) return 'Excellent';
    if (progressValue >= 70) return 'Good';
    if (progressValue >= 50) return 'Fair';
    return 'Behind Schedule';
  }

  // Get days remaining (if applicable)
  int? get daysRemaining {
    if (endDate == null || status != 'active') return null;
    
    final now = DateTime.now();
    if (now.isAfter(endDate!)) return 0;
    
    return endDate!.difference(now).inDays;
  }

  static void defaultModel() {}
}