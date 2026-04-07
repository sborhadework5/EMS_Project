import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ems_project/api_service.dart';

class AddEmployeePage extends StatefulWidget {
  const AddEmployeePage({super.key});

  @override
  State<AddEmployeePage> createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends State<AddEmployeePage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _salaryController = TextEditingController();
  final _passwordController = TextEditingController();

  String _dept = 'IT';
  String _designation = 'Junior Associate';
  String _selectedRole = 'employee';

  bool _isLoading = false;

  Future<void> _saveEmployee() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        // 1. Call API
        final Map<String, dynamic> response = await ApiService().registerUser(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Log the response to debug if it fails again
        debugPrint("Backend Response: $response");

        final String? newUid = response['uid'];
        
        if (newUid == null || newUid.isEmpty) {
          throw "Backend failed to return a valid UID. Please try again.";
        }

        // 2. Save to Firestore
        await FirebaseFirestore.instance.collection('users').doc(newUid).set({
          'emp_id': _idController.text.trim(),
          'full_name': _nameController.text.trim(),
          'email': _emailController.text.trim().toLowerCase(),
          'phone': _phoneController.text.trim(),
          'department': _dept,
          'designation': _designation,
          'salary': _salaryController.text.trim(),
          'role': _selectedRole,
          'status': 'active',
          'joining_date': FieldValue.serverTimestamp(),
          'total_distance_today': 0.0,
          'created_at': FieldValue.serverTimestamp(),
          'last_location': {
            'lat': 0.0,
            'lng': 0.0,
            'last_updated': FieldValue.serverTimestamp(),
          },
        });

        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Employee added successfully!"), backgroundColor: Colors.green),
        );

      } catch (e) {
        debugPrint("SAVE ERROR: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${e.toString()}"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Onboarding")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildInput(_idController, "Employee ID", Icons.badge),
              _buildInput(_nameController, "Full Name", Icons.person),
              _buildInput(_emailController, "Official Email", Icons.email),
              _buildInput(_passwordController, "Set Login Password", Icons.lock, isPass: true),
              _buildInput(_phoneController, "Phone Number", Icons.phone),
              _buildInput(_salaryController, "Monthly Salary", Icons.currency_rupee, isNum: true),
              DropdownButtonFormField(
                value: _dept,
                decoration: const InputDecoration(labelText: "Department", border: OutlineInputBorder()),
                items: ['IT', 'HR', 'Finance', 'Sales'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) => setState(() => _dept = val as String),
              ),
              const SizedBox(height: 15), // Spacing
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: "User Role", 
                  prefixIcon: Icon(Icons.admin_panel_settings),
                  border: OutlineInputBorder()
                ),
                items: ['admin', 'manager', 'employee'].map((role) => DropdownMenuItem(
                  value: role, 
                  child: Text(role.toUpperCase())
                )).toList(),
                onChanged: (val) => setState(() => _selectedRole = val!),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: _saveEmployee,
                  child: const Text("SAVE TO DATABASE"),
                ),
              )
              
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController ctr, String label, IconData icon, {bool isPass = false, bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: ctr,
        obscureText: isPass,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
        validator: (v) => v!.isEmpty ? "Required field" : null,
      ),
    );
  }
}