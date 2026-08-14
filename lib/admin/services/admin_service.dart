import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> getStudentsCount() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();

    return snapshot.docs.length;
  }

  Future<int> getTeachersCount() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .get();

    return snapshot.docs.length;

  }

Future<int> getPendingRequestsCount() async {
  final snapshot = await _firestore
      .collection('teacher_requests')
      .where('status', isEqualTo: 'pending')
      .get();

  return snapshot.docs.length;
}
  Future<int> getAdminsCount() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .get();

    return snapshot.docs.length;
  }
}
