import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// action_pages.dart - Update the AttendanceHistoryPage
// import 'package:intl/intl.dart'; // Add intl: ^0.19.0 to pubspec.yaml

// action_pages.dart
class AttendanceHistoryPage extends StatelessWidget {
  const AttendanceHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Attendance"),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            .where('uid', isEqualTo: uid) 
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // This will show if the Index is missing!
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No attendance records found."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              // Formatting the date without the intl package for now
              DateTime? date = (data['timestamp'] as Timestamp?)?.toDate();
              
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: data['type'] == 'in' ? Colors.green[100] : Colors.red[100],
                    child: Icon(
                      data['type'] == 'in' ? Icons.login : Icons.logout,
                      color: data['type'] == 'in' ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text("Clocked ${data['type'].toString().toUpperCase()}"),
                  subtitle: Text(date != null ? date.toString().split('.')[0] : "Processing..."),
                  trailing: Text(
                    data['status'] ?? "Present",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
// action_pages.dart - Update ApplyLeavePage
class ApplyLeavePage extends StatefulWidget {
  const ApplyLeavePage({super.key});

  @override
  State<ApplyLeavePage> createState() => _ApplyLeavePageState();
}

class _ApplyLeavePageState extends State<ApplyLeavePage> {
  final _reasonController = TextEditingController();
  String _leaveType = "Sick Leave";
  bool _isSubmitting = false;

  Future<void> _submitLeave() async {
    if (_reasonController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a reason")));
      return;
    }

    setState(() => _isSubmitting = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      await FirebaseFirestore.instance.collection('leaves').add({
        'uid': uid,
        'type': _leaveType,
        'reason': _reasonController.text,
        'status': 'Pending',
        'applied_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Leave Request Submitted!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Apply Leave")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _leaveType,
              decoration: const InputDecoration(labelText: "Leave Type"),
              items: ["Sick Leave", "Casual Leave", "Vacation"]
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (val) => setState(() => _leaveType = val!),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: "Reason", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitLeave,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[800], foregroundColor: Colors.white),
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit Request"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// action_pages.dart - Update IDCardPage
class IDCardPage extends StatelessWidget {
  const IDCardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Digital ID Card")),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var userData = snapshot.data!.data() as Map<String, dynamic>;

          return Center(
            child: Card(
              elevation: 15,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: 320,
                height: 500,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    colors: [Colors.indigo[900]!, Colors.indigo[700]!],
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    const CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 80, color: Colors.indigo),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      userData['name']?.toUpperCase() ?? "NAME",
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      userData['role'] ?? "Employee",
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      color: Colors.white,
                      child: Text(
                        "UID: ${user?.uid.substring(0, 8)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
                      ),
                    ),
                    const Spacer(),
                    const Text("EMS SYSTEM", style: TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}