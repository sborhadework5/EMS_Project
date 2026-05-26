import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ems_project/screens/admin/add_employee.dart';
import 'package:ems_project/screens/admin/employee_list.dart'; // Correct Page for Directory
import 'package:ems_project/screens/admin/attendance_list.dart';
import 'package:ems_project/screens/admin/admin_leave_page.dart'; // ← add this // Ensure correct path
import 'package:ems_project/screens/admin/admin_attendance_page.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Admin Command Center",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quick Management",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: GridView.count(
                  // Adaptive grid: 3 columns for wide screens (Web), 2 for mobile
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount:
                      MediaQuery.of(context).size.width > 800 ? 3 : 2,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio:
                      MediaQuery.of(context).size.width > 800 ? 1.2 : 1.0,
                  children: [
                    _buildMenuCard(
                        context,
                        "Employee Directory",
                        "Manage staff, edits & deletion", // Updated subtitle
                        Icons.badge,
                        Colors.orange,
                        const EmployeeListPage()),
                    _buildMenuCard(
                        context,
                        "Attendance Reports",
                        "Monthly timecards per employee",
                        Icons.analytics,
                        Colors.green,
                        const AdminAttendancePage()),
                    _buildMenuCard(
                      context,
                      "Leave Requests",
                      "Approve or reject leave applications",
                      Icons.event_note,
                      Colors.purple,
                      const AdminLeavePage(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, String title, String subtitle,
      IconData icon, Color color, Widget destination) {
    return InkWell(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (context) => destination)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // ← key fix
          children: [
            CircleAvatar(
              radius: 26, // ← slightly smaller
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
