import 'package:flutter/material.dart';

class EmployeeDetailsPage extends StatelessWidget {
  final Map<String, dynamic> data;
  const EmployeeDetailsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(data['full_name'] ?? "Details")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50))),
          const SizedBox(height: 20),
          _infoTile("Full Name", data['full_name']),
          _infoTile("Employee ID", data['emp_id']),
          _infoTile("Department", data['department']),
          _infoTile("Email", data['email']),
          _infoTile("Salary", "₹${data['salary']}"),
          _infoTile("Initial Password", data['initial_password'] ?? "N/A"),
          const Divider(),
          _infoTile("Total Distance Today", "${data['total_distance_today'] ?? 0.0} km"),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String? value) => ListTile(
    title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
    subtitle: Text(value ?? "N/A", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  );
}