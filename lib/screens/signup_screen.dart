import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  
  String _selectedRole = 'employee';
  String _selectedDept = 'IT';
  bool _isLoading = false;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // 1. Create User in Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: _emailController.text.trim(), 
              password: _passwordController.text.trim());

      final counterRef = FirebaseFirestore.instance.collection('metadata').doc('user_counter');

      String finalEmpId = await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(counterRef);

      if (!snapshot.exists) {
        // First user starts at 1001
        transaction.set(counterRef, {'last_id': 1001});
        return "1001";
      } else {
        int newId = (snapshot.data() as Map<String, dynamic>)['last_id'] + 1;
        transaction.update(counterRef, {'last_id': newId});
        return newId.toString();
      }
    });

      // 2. Create Document in Firestore (Matching your schema)
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
      'emp_id': finalEmpId, // This is your 1001, 1002, etc.
      'full_name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'role': _selectedRole,
      'department': _selectedDept,
      'designation': _selectedRole == 'admin' ? 'System Admin' : 'Junior Associate',
      'joining_date': FieldValue.serverTimestamp(),
      'status': 'active',
    });

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registration Successful! Please Login.")),
      );

      // Redirect to Login
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));

    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Error occurred")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo[900], // Professional dark background
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 15,
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_rounded, size: 50, color: Colors.indigo[800]),
                      const SizedBox(height: 10),
                      const Text("Create Account", 
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      
                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person)),
                        validator: (value) => value!.isEmpty ? "Enter your name" : null,
                      ),
                      
                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: "Email Address", prefixIcon: Icon(Icons.email)),
                        validator: (value) => !value!.contains('@') ? "Enter a valid email" : null,
                      ),
                      
                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock)),
                        obscureText: true,
                        validator: (value) => value!.length < 6 ? "Minimum 6 characters" : null,
                      ),

                      const SizedBox(height: 15),

                      // Department Dropdown
                      DropdownButtonFormField(
                        value: _selectedDept,
                        decoration: const InputDecoration(labelText: "Department"),
                        items: ['IT', 'HR', 'Finance', 'Operations'].map((dept) => 
                          DropdownMenuItem(value: dept, child: Text(dept))).toList(),
                        onChanged: (val) => setState(() => _selectedDept = val as String),
                      ),

                      const SizedBox(height: 30),

                      // Register Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo[800],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                          onPressed: _isLoading ? null : _signUp,
                          child: _isLoading 
                            ? const CircularProgressIndicator(color: Colors.white) 
                            : const Text("REGISTER SYSTEM ACCOUNT", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),

                      // Redirect to Login
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen())),
                        child: const Text("Already have an account? Login here"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}