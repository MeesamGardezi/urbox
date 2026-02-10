import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../../core/config/app_config.dart';
import '../models/assignment.dart';

class AssignmentService {
  static String get _baseUrl => AppConfig.assignmentsEndpoint;

  /// Get assignments for a company
  /// If [memberId] is provided, filtering happens on the backend or here?
  /// Backend supports querying by companyId and assignedTo.
  static Future<List<Assignment>> getAssignments(
    String companyId, {
    String? memberId,
    String? status,
  }) async {
    final queryParams = <String, String>{'companyId': companyId};

    if (memberId != null) {
      queryParams['assignedTo'] = memberId;
    }

    if (status != null) {
      queryParams['status'] = status;
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List list = data['assignments'];
          return list.map((e) => Assignment.fromJson(e)).toList();
        }
      }
      throw Exception('Failed to load assignments: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching assignments: $e');
    }
  }

  /// Create a new assignment
  static Future<String> createAssignment(Assignment assignment) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(assignment.toJson()),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['id'];
        }
      }
      throw Exception('Failed to create assignment: ${response.body}');
    } catch (e) {
      throw Exception('Error creating assignment: $e');
    }
  }

  /// Update assignment status
  static Future<void> updateStatus(
    String assignmentId,
    String status, // 'pending', 'in_progress', 'completed'
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/$assignmentId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update status');
      }
    } catch (e) {
      throw Exception('Error updating status: $e');
    }
  }

  /// Delete an assignment
  static Future<void> deleteAssignment(String assignmentId) async {
    try {
      final response = await http.delete(Uri.parse('$_baseUrl/$assignmentId'));

      if (response.statusCode != 200) {
        throw Exception('Failed to delete assignment');
      }
    } catch (e) {
      throw Exception('Error deleting assignment: $e');
    }
  }
}
