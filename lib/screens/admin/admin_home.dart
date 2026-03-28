import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ems_project/screens/admin/add_employee.dart';
import 'package:ems_project/screens/admin/employee_list.dart'; // Correct Page for Directory

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Admin Command Center", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout), 
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // No need to pop if your main.dart is using a StreamBuilder for Auth
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quick Management", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                // Adaptive grid: 3 columns for wide screens (Web), 2 for mobile
                crossAxisCount: MediaQuery.of(context).size.width > 800 ? 3 : 2,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                children: [
                  _buildMenuCard(
                    context, 
                    "Add New Employee", 
                    "Onboard staff & set passwords", 
                    Icons.person_add, 
                    Colors.blue, 
                    const AddEmployeePage()
                  ),
                  _buildMenuCard(
                    context, 
                    "Employee Directory", 
                    "Live location, status & edits", 
                    Icons.badge, 
                    Colors.orange, 
                    const EmployeeListPage() // FIXED: Point to List Page
                  ),
                  _buildMenuCard(
                    context, 
                    "Attendance Reports", 
                    "Check daily logs & history", 
                    Icons.analytics, 
                    Colors.green, 
                    const Scaffold(body: Center(child: Text("Reports Module Coming Soon"))) 
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, String title, String subtitle, IconData icon, Color color, Widget destination) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => destination)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}