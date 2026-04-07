import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeDetailsPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId; // Required to target the specific Firestore document

  const EmployeeDetailsPage({super.key, required this.data, required this.docId});

  // --- DELETE FUNCTION ---
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Employee?"),
        content: Text("Are you sure you want to delete ${data['full_name']}? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('users').doc(docId).delete();
                Navigator.pop(context); // Close Dialog
                Navigator.pop(context); // Go back to List Page
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Employee Deleted"), backgroundColor: Colors.red),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    // Initialize controllers with existing data
    final nameController = TextEditingController(text: data['full_name']);
    final phoneController = TextEditingController(text: data['phone']);
    final salaryController = TextEditingController(text: data['salary'].toString());
    final desigController = TextEditingController(text: data['designation']);
    
    // State variables for dropdowns (using StatefulBuilder inside showDialog)
    String selectedDept = data['department'] ?? 'IT';
    String selectedRole = (data['role'] ?? 'employee').toString().toLowerCase();
    String selectedStatus = data['status'] ?? 'active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // Allows dropdowns to update inside the dialog
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Update Employee Profile"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildEditField(nameController, "Full Name", Icons.person),
                    _buildEditField(phoneController, "Phone", Icons.phone, isNum: true),
                    _buildEditField(salaryController, "Salary", Icons.currency_rupee, isNum: true),
                    _buildEditField(desigController, "Designation", Icons.work),
                    
                    const SizedBox(height: 15),
                    
                    // Department Dropdown
                    _buildDropdown("Department", selectedDept, ['IT', 'HR', 'Finance', 'Sales'], (val) {
                      setDialogState(() => selectedDept = val!);
                    }),
                    
                    const SizedBox(height: 15),
                    
                    // Role Dropdown
                    _buildDropdown("User Role", selectedRole, ['admin', 'manager', 'employee'], (val) {
                      setDialogState(() => selectedRole = val!);
                    }),

                    const SizedBox(height: 15),

                    // Status Dropdown
                    _buildDropdown("Status", selectedStatus, ['active', 'inactive', 'on leave'], (val) {
                      setDialogState(() => selectedStatus = val!);
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('users').doc(docId).update({
                    'full_name': nameController.text.trim(),
                    'phone': phoneController.text.trim(),
                    'salary': salaryController.text.trim(),
                    'designation': desigController.text.trim(),
                    'department': selectedDept,
                    'role': selectedRole,
                    'status': selectedStatus,
                  });
                  Navigator.pop(context);
                  Navigator.pop(context); // Return to list to see changes
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Updated!")));
                },
                child: const Text("SAVE CHANGES"),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Employee Profile"),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => _showEditDialog(context)),
          IconButton(icon: const Icon(Icons.delete), onPressed: () => _confirmDelete(context)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 20),
            _infoTile("Full Name", data['full_name'], Icons.person),
            _infoTile("Employee ID", data['emp_id'], Icons.badge),
            _infoTile("Email", data['email'], Icons.email),
            _infoTile("Phone", data['phone'], Icons.phone),
            _infoTile("Department", data['department'], Icons.business),
            _infoTile("Designation", data['designation'], Icons.work),
            _infoTile("Salary", "₹${data['salary']}", Icons.currency_rupee),
            _infoTile("Status", data['status'], Icons.info_outline),
          ],
        ),
      ),
    );
  }

  // Helper for Input Fields in Modal
  Widget _buildEditField(TextEditingController controller, String label, IconData icon, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  // Helper for Dropdowns in Modal
  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    // 1. Force everything to lowercase for a perfect match
    String lowercaseValue = value.toLowerCase();
    List<String> lowercaseItems = items.map((e) => e.toLowerCase()).toList();

    // 2. Safety Check: If the value isn't in the list, default to the first item
    String effectiveValue = lowercaseItems.contains(lowercaseValue) ? lowercaseValue : lowercaseItems.first;

    return DropdownButtonFormField<String>(
      value: effectiveValue,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: lowercaseItems.map((e) => DropdownMenuItem(
        value: e,
        child: Text(e.toUpperCase()), // Displayed as ADMIN, EMPLOYEE, etc.
      )).toList(),
      onChanged: onChanged,
    );
  }
  
  Widget _infoTile(String title, String? value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: Colors.indigo),
        title: Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(value ?? "N/A", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }
}