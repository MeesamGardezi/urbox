import 'package:cloud_firestore/cloud_firestore.dart';

/// User Profile Model
///
/// Represents a user in the system with all profile information
/// Does NOT store passwords (Firebase Auth handles that)
/// Does NOT store subscription data (that's in Company model)
class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String companyId;
  final String role; // 'owner' | 'member'

  // Permissions & Access
  final List<String> assignedInboxIds;
  final String status; // 'active' | 'suspended' | 'deleted'

  // Security & Audit
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? invitedBy;
  final DateTime? lastLoginAt;

  // MFA & Security
  final bool mfaEnabled;
  final String? mfaMethod;

  // Profile
  final String? phoneNumber;
  final String? avatarUrl;
  final String? timezone;
  final String? language;

  // Notifications
  final bool emailNotifications;
  final bool pushNotifications;
  final Map<String, dynamic> preferences;

  UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.companyId,
    required this.role,
    this.assignedInboxIds = const [],
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
    this.invitedBy,
    this.lastLoginAt,
    this.mfaEnabled = false,
    this.mfaMethod,
    this.phoneNumber,
    this.avatarUrl,
    this.timezone,
    this.language,
    this.emailNotifications = true,
    this.pushNotifications = true,
    this.preferences = const {},
  });

  // Computed properties
  bool get isOwner => role == 'owner';
  bool get isMember => role == 'member';
  bool get isActive => status == 'active';
  bool get hasMFA => mfaEnabled;

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return UserProfile(
      id: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      companyId: data['companyId'] ?? '',
      role: data['role'] ?? 'member',
      assignedInboxIds: List<String>.from(data['assignedInboxIds'] ?? []),
      status: data['status'] ?? 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      invitedBy: data['invitedBy'],
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
      mfaEnabled: data['mfaEnabled'] ?? false,
      mfaMethod: data['mfaMethod'],
      phoneNumber: data['phoneNumber'],
      avatarUrl: data['avatarUrl'],
      timezone: data['timezone'],
      language: data['language'],
      emailNotifications: data['emailNotifications'] ?? true,
      pushNotifications: data['pushNotifications'] ?? true,
      preferences: Map<String, dynamic>.from(data['preferences'] ?? {}),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'companyId': companyId,
      'role': role,
      'assignedInboxIds': assignedInboxIds,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'invitedBy': invitedBy,
      'lastLoginAt': lastLoginAt != null
          ? Timestamp.fromDate(lastLoginAt!)
          : null,
      'mfaEnabled': mfaEnabled,
      'mfaMethod': mfaMethod,
      'phoneNumber': phoneNumber,
      'avatarUrl': avatarUrl,
      'timezone': timezone,
      'language': language,
      'emailNotifications': emailNotifications,
      'pushNotifications': pushNotifications,
      'preferences': preferences,
    };
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? displayName,
    String? companyId,
    String? role,
    List<String>? assignedInboxIds,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? invitedBy,
    DateTime? lastLoginAt,
    bool? mfaEnabled,
    String? mfaMethod,
    String? phoneNumber,
    String? avatarUrl,
    String? timezone,
    String? language,
    bool? emailNotifications,
    bool? pushNotifications,
    Map<String, dynamic>? preferences,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      companyId: companyId ?? this.companyId,
      role: role ?? this.role,
      assignedInboxIds: assignedInboxIds ?? this.assignedInboxIds,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      invitedBy: invitedBy ?? this.invitedBy,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      mfaEnabled: mfaEnabled ?? this.mfaEnabled,
      mfaMethod: mfaMethod ?? this.mfaMethod,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      timezone: timezone ?? this.timezone,
      language: language ?? this.language,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      pushNotifications: pushNotifications ?? this.pushNotifications,
      preferences: preferences ?? this.preferences,
    );
  }
}
