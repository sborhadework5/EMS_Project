import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. Create/Add a new Employee
  Future<void> addEmployee(String name, String role) async {
    await _db.collection('employees').add({
      'name': name,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 2. Read Employees (Real-time stream)
  Stream<QuerySnapshot> getEmployees() {
    return _db.collection('employees').orderBy('createdAt').snapshots();
  }
}