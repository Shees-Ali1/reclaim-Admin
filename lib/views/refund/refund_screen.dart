import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../const/constants.dart';
import '../../controller/sidebarController.dart';
import '../../widgets/custom_button.dart';

class RefundScreen extends StatefulWidget {
  const RefundScreen({super.key});

  @override
  State<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends State<RefundScreen>
    with SingleTickerProviderStateMixin {
  final SidebarController sidebarController = Get.put(SidebarController());
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Automatically delete requests older than 48 hours that are still pending
    _cleanupExpiredRequests();
  }

  /// Deletes pending refund requests older than 48 hours from the database
  Future<void> _cleanupExpiredRequests() async {
    try {
      DateTime threshold = DateTime.now().subtract(const Duration(hours: 48));

      QuerySnapshot expiredSnapshot = await _firestore
          .collection('refundRequests')
          .where('status', isEqualTo: 'pending')
          .where('createdAt', isLessThan: Timestamp.fromDate(threshold))
          .get();

      if (expiredSnapshot.docs.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        for (var doc in expiredSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print(
            "Cleaned up ${expiredSnapshot.docs.length} expired refund requests.");
      }
    } catch (e) {
      print("Error cleaning up expired requests: $e");
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp != null && timestamp is Timestamp) {
      DateTime dateTime = timestamp.toDate();
      return DateFormat('dd/MM/yyyy hh:mm a').format(dateTime);
    }
    return 'N/A';
  }

  Future<void> _processRefund(
      Map<String, dynamic> data, String docId, String status) async {
    try {
      final String buyerId = data['buyerId'] ?? '';
      final double refundAmount =
          double.tryParse(data['amount'].toString()) ?? 0.0;

      if (status == 'approved') {
        // 1. Search for the wallet document where the field 'userId' == buyerId
        QuerySnapshot walletSnapshot = await _firestore
            .collection('wallet')
            .where('userId', isEqualTo: buyerId)
            .limit(1)
            .get();

        if (walletSnapshot.docs.isEmpty) {
          Get.snackbar("Error", "No wallet found for user ID: $buyerId",
              backgroundColor: Colors.red, colorText: Colors.white);
          return;
        }

        DocumentReference walletDocRef = walletSnapshot.docs.first.reference;
        WriteBatch batch = _firestore.batch();

        // 2. Update status of the Refund Request
        batch.update(_firestore.collection('refundRequests').doc(docId), {
          'status': 'approved',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // 3. Update Balance in the Wallet
        batch.update(walletDocRef, {
          'balance': FieldValue.increment(refundAmount),
        });

        // 4. Create Transaction history inside the wallet
        DocumentReference transRef =
            walletDocRef.collection('transaction').doc();
        batch.set(transRef, {
          'buyerId': buyerId,
          'date': FieldValue.serverTimestamp(),
          'price': refundAmount,
          'productName': data['productName'] ?? 'N/A',
          'sellerId': data['sellerId'] ?? '',
          'sellerName': data['sellerName'] ?? '',
          'type': 'refund',
          'userImage': data['userImage'] ?? '',
          'userName': data['userName'] ?? '',
        });

        await batch.commit();
        Get.snackbar("Success", "Refund Approved and Wallet Updated",
            backgroundColor: Colors.green, colorText: Colors.white);
      } else {
        // Handle Rejection
        await _firestore.collection('refundRequests').doc(docId).update({
          'status': 'rejected',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        Get.snackbar("Rejected", "Refund Request was rejected",
            backgroundColor: Colors.orange, colorText: Colors.white);
      }
    } catch (e) {
      Get.snackbar("Error", "Something went wrong: $e",
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  void _showActionDialog(
      Map<String, dynamic> data, String docId, String action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: primaryColor,
        title: Text("Confirm $action",
            style: const TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to $action this request?",
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          CustomButton(
            width: 100,
            height: 40,
            text: "Confirm",
            onPressed: () {
              Navigator.pop(context);
              _processRefund(
                  data, docId, action == 'Approve' ? 'approved' : 'rejected');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                if (Get.width < 768)
                  IconButton(
                    icon: const Icon(Icons.menu, color: primaryColor),
                    onPressed: () => sidebarController.showsidebar.value = true,
                  ),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => searchQuery = v),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Search Product or Buyer ID...",
                      hintStyle: const TextStyle(color: Colors.white54),
                      fillColor: primaryColor,
                      filled: true,
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(
                    child: Text('Product',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: primaryColor),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('Amount',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: primaryColor),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('Status',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: primaryColor),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('Actions',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: primaryColor),
                        textAlign: TextAlign.center)),
              ],
            ),
            const Divider(color: primaryColor),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('refundRequests').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());

                  DateTime threshold =
                      DateTime.now().subtract(const Duration(hours: 48));

                  var docs = snapshot.data!.docs.where((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    Timestamp? createdAt = d['createdAt'] as Timestamp?;
                    String status = d['status'] ?? 'pending';

                    // logic: If pending and older than 48 hours, hide from UI
                    if (status == 'pending' &&
                        createdAt != null &&
                        createdAt.toDate().isBefore(threshold)) {
                      return false;
                    }

                    // search logic
                    return d['productName']
                            .toString()
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()) ||
                        d['buyerId']
                            .toString()
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase());
                  }).toList();

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var data = docs[index].data() as Map<String, dynamic>;
                      String docId = docs[index].id;
                      String status = data['status'] ?? 'pending';

                      return Column(
                        children: [
                          ListTile(
                            title: Row(
                              children: [
                                Expanded(
                                    child: Text(data['productName'] ?? 'N/A',
                                        style: TextStyle(color: Colors.black),
                                        textAlign: TextAlign.center)),
                                Expanded(
                                    child: Text("Rs. ${data['amount']}",
                                        style: TextStyle(color: Colors.black),
                                        textAlign: TextAlign.center)),
                                Expanded(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: status == 'approved'
                                            ? Colors.green.withOpacity(0.1)
                                            : status == 'rejected'
                                                ? Colors.red.withOpacity(0.1)
                                                : Colors.orange
                                                    .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                            color: status == 'approved'
                                                ? Colors.green
                                                : status == 'rejected'
                                                    ? Colors.red
                                                    : Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (status == 'pending') ...[
                                        IconButton(
                                            icon: const Icon(Icons.check_circle,
                                                color: Colors.green),
                                            onPressed: () => _showActionDialog(
                                                data, docId, 'Approve')),
                                        IconButton(
                                            icon: const Icon(Icons.cancel,
                                                color: Colors.red),
                                            onPressed: () => _showActionDialog(
                                                data, docId, 'Reject')),
                                      ] else
                                        Text(status.capitalizeFirst!,
                                            style: const TextStyle(
                                                color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(thickness: 0.5),
                        ],
                      );
                    },
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
