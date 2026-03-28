import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ems_project/screens/admin/employee_details.dart';

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Employee Directory"),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: "Search by Name or ID...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
            ),
            const SizedBox(height: 20),
            
            // Employee Table
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  // Filter logic for the search bar
                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['full_name'] ?? "").toString().toLowerCase();
                    final id = (data['emp_id'] ?? "").toString().toLowerCase();
                    return name.contains(_searchQuery) || id.contains(_searchQuery);
                  }).toList();

                  return DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    minWidth: 600,
                    columns: const [
                      DataColumn2(label: Text('ID'), size: ColumnSize.S),
                      DataColumn2(label: Text('Name'), size: ColumnSize.L),
                      DataColumn2(label: Text('Dept')),
                      DataColumn2(label: Text('View'), fixedWidth: 80),
                    ],
                    rows: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DataRow(cells: [
                        DataCell(Text(data['emp_id'] ?? '-')),
                        DataCell(Text(data['full_name'] ?? 'N/A')),
                        DataCell(Text(data['department'] ?? 'IT')),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.indigo),
                            onPressed: () {
                              // NAVIGATE TO THE DETAILS PAGE
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EmployeeDetailsPage(data: data),
                                ),
                              );
                            },
                          ),
                        ),
                      ]);
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}