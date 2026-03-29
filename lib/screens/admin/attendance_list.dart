import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AttendanceListPage extends StatefulWidget {
  const AttendanceListPage({super.key});

  @override
  State<AttendanceListPage> createState() => _AttendanceListPageState();
}

class _AttendanceListPageState extends State<AttendanceListPage> {
  String _searchQuery = "";
  Map<String, DateTime> _selectedDates = {}; // Keeps track of date filter per employee

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Employee Attendance", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());

                // Filter users based on search query (ID or Name)
                var users = userSnapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  return data['emp_id'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
                         data['full_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    var userData = users[index].data() as Map<String, dynamic>;
                    String empId = userData['emp_id'] ?? "Unknown";
                    String uid = users[index].id; // The document ID (Auth UID)

                    return _buildEmployeeExpandableCard(empId, userData['full_name'], uid);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.indigo[900],
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Search Employee ID or Name...",
          hintStyle: const TextStyle(color: Colors.white60),
          prefixIcon: const Icon(Icons.search, color: Colors.white60),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildEmployeeExpandableCard(String empId, String name, String uid) {
    DateTime selectedDate = _selectedDates[uid] ?? DateTime.now();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo[100],
          child: Text(name[0], style: TextStyle(color: Colors.indigo[900], fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("ID: $empId", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        children: [
          const Divider(),
          // Date Selector Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Logs for: ${DateFormat('dd MMM yyyy').format(selectedDate)}", 
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo)),
                TextButton.icon(
                  onPressed: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _selectedDates[uid] = picked);
                  },
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text("Change Date"),
                )
              ],
            ),
          ),
          // Nested Stream for actual attendance logs of THIS user on THIS date
          _buildAttendanceList(uid, selectedDate),
        ],
      ),
    );
  }

  Widget _buildAttendanceList(String uid, DateTime date) {
    // Creating start and end of the selected day for Firestore filtering
    DateTime startOfDay = DateTime(date.year, date.month, date.day, 0, 0);
    DateTime endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .where('uid', isEqualTo: uid)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThanOrEqualTo: endOfDay)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
            return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.red)),
            );
        }
        if (!snapshot.hasData) return const Center(child: Padding(
            padding: EdgeInsets.all(8.0),
            child: LinearProgressIndicator(),
        ));
        var logs = snapshot.data!.docs;

        if (logs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("No records found for this date.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          );
        }

        return ListView.builder(
          shrinkWrap: true, // Important for nested lists
          physics: const NeverScrollableScrollPhysics(),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            var log = logs[index].data() as Map<String, dynamic>;
            bool isIn = log['type'] == 'in';
            DateTime time = (log['timestamp'] as Timestamp).toDate();

            return ListTile(
              dense: true,
              leading: Icon(isIn ? Icons.login : Icons.logout, color: isIn ? Colors.green : Colors.red, size: 20),
              title: Text(isIn ? "Punch In" : "Punch Out", style: const TextStyle(fontWeight: FontWeight.w500)),
              trailing: Text(DateFormat('hh:mm a').format(time), style: const TextStyle(color: Colors.blueGrey)),
            );
          },
        );
      },
    );
  }
}