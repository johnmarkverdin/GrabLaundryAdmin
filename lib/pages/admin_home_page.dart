import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 👈 for remember-me clear
import '../supabase_config.dart';
import 'auth_admin_page.dart'; // 👈 to navigate back to login
import 'admin_price_list_page.dart'; // 👈 NEW: admin price list page

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _riders = [];

  bool _loading = false;
  String _statusFilter = 'all';
  final _searchCtl = TextEditingController();

  String? _editingOrderId;
  String? _selectedRiderIdForEdit; // stores rider UUID or "unassigned"
  String? _selectedStatusForEdit;

  final TextEditingController _totalPriceController = TextEditingController();
  final TextEditingController _deliveryFeeController = TextEditingController();

  final List<String> _statusOptions = const [
    'all',
    'pending',
    'accepted',
    'picked_up',
    'in_wash',
    'in_delivery',
    'completed',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _loadRiders();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _totalPriceController.dispose();
    _deliveryFeeController.dispose();
    super.dispose();
  }

  // ---------- RIDERS ----------
  Future<void> _loadRiders() async {
    try {
      final res = await supabase
          .from('profiles')
          .select('id, full_name, phone, role')
          .eq('role', 'rider')
          .order('full_name', ascending: true);

      setState(() {
        _riders = (res as List).cast<Map<String, dynamic>>();
      });

      if (_riders.isEmpty) {
        _snack(
          'No riders found. Ask riders to sign up in the Rider app so you can assign them.',
        );
      }
    } catch (e) {
      _snack('Failed to load riders: $e');
    }
  }

  // ---------- ORDERS ----------
  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('laundry_orders')
          .select('''
            id,
            customer_id,
            customer:profiles!laundry_orders_customer_id_fkey ( full_name ),
            rider_id,
            rider:profiles!laundry_orders_rider_id_fkey ( full_name ),
            pickup_address,
            delivery_address,
            service,
            payment_method,
            status,
            pickup_at,
            delivery_at,
            total_price,
            delivery_fee,
            proof_of_billing_url,
            notes
          ''') // 👈 added notes
          .order('created_at', ascending: false);

      setState(() {
        _orders = (res as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      _snack('Failed to load orders: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- EDIT ----------
  void _startEdit(Map<String, dynamic> order) {
    setState(() {
      _editingOrderId = order['id'].toString();
      final riderId = order['rider_id'];
      _selectedRiderIdForEdit =
      riderId == null ? 'unassigned' : riderId.toString();
      _selectedStatusForEdit = order['status']?.toString() ?? 'pending';

      final total = order['total_price'];
      _totalPriceController.text = total == null ? '' : total.toString();

      final delivering = order['delivery_fee'];
      _deliveryFeeController.text =
      delivering == null ? '' : delivering.toString();
    });
  }

  Future<void> _saveEdit() async {
    if (_editingOrderId == null) return;

    final updateData = <String, dynamic>{};

    if (_selectedRiderIdForEdit == 'unassigned') {
      updateData['rider_id'] = null;
    } else if (_selectedRiderIdForEdit != null &&
        _selectedRiderIdForEdit!.isNotEmpty) {
      updateData['rider_id'] = _selectedRiderIdForEdit;
    }

    if (_selectedStatusForEdit != null &&
        _selectedStatusForEdit!.isNotEmpty) {
      updateData['status'] = _selectedStatusForEdit;
    }

    final totalText = _totalPriceController.text.trim();
    if (totalText.isNotEmpty) {
      final parsed = num.tryParse(totalText);
      if (parsed == null) {
        _snack('Invalid total price. Use numbers only (e.g. 250 or 250.50).');
        return;
      }
      updateData['total_price'] = parsed;
    }

    final shippingText = _deliveryFeeController.text.trim();
    if (shippingText.isNotEmpty) {
      final parsed = num.tryParse(shippingText);
      if (parsed == null) {
        _snack('Invalid delivery fee. Use numbers only (e.g. 50 or 75.00).');
        return;
      }
      updateData['delivery_fee'] = parsed;
    }

    if (updateData.isEmpty) {
      _snack('No changes to save.');
      return;
    }

    setState(() => _loading = true);
    try {
      await supabase
          .from('laundry_orders')
          .update(updateData)
          .eq('id', _editingOrderId!);

      setState(() {
        _editingOrderId = null;
        _selectedRiderIdForEdit = null;
        _selectedStatusForEdit = null;
        _totalPriceController.clear();
        _deliveryFeeController.clear();
      });

      await _loadOrders();
      _snack('Order updated successfully.');
    } catch (e) {
      _snack('Failed to update order: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- DELETE ----------
  Future<void> _deleteOrder(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Order'),
        content: const Text(
          'Are you sure you want to permanently delete this order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      _snack('Delete cancelled.');
      return;
    }

    setState(() => _loading = true);
    try {
      await supabase.from('laundry_orders').delete().eq('id', orderId);
      _snack('Order deleted.');
      await _loadOrders();
    } catch (e) {
      _snack('Failed to delete order: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- HELPERS ----------
  Future<void> _logout() async {
    try {
      // Clear remember-me for admin
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_remember_me');
      await prefs.remove('admin_email');

      // Sign out from Supabase
      await supabase.auth.signOut();

      if (!mounted) return;

      // Go back to AdminAuthPage and clear navigation stack
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AdminAuthPage()),
            (route) => false,
      );
    } catch (e) {
      _snack('Error signing out: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  int _countByStatus(String status) {
    if (status == 'all') return _orders.length;
    return _orders.where((o) => (o['status'] ?? '') == status).length;
  }

  String _formatDateTime(dynamic v) {
    if (v == null) return '-';
    try {
      final dt = DateTime.parse(v.toString());
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return v.toString();
    }
  }

  void _showProofDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusBadgeColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.amber.shade600;
      case 'accepted':
        return Colors.indigo.shade600;
      case 'picked_up':
      case 'in_wash':
        return Colors.blue.shade600;
      case 'in_delivery':
        return Colors.orange.shade600;
      case 'completed':
        return Colors.green.shade600;
      case 'cancelled':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  String _prettyStatus(String status) =>
      status.replaceAll('_', ' ').toUpperCase();

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final loader = _loading
        ? const LinearProgressIndicator(minHeight: 2)
        : const SizedBox.shrink();
    final primaryTextColor = Colors.grey.shade900;
    final secondaryTextColor = Colors.grey.shade600;

    final q = _searchCtl.text.trim().toLowerCase();
    final filtered = _orders.where((o) {
      final status = (o['status'] ?? '').toString();
      final statusOk = _statusFilter == 'all' || status == _statusFilter;

      if (q.isEmpty) return statusOk;

      final customer = o['customer'] as Map<String, dynamic>?;
      final customerName = customer?['full_name'];

      final rider = o['rider'] as Map<String, dynamic>?;
      final riderName = rider?['full_name'];

      final combined = [
        customerName,
        riderName,
        o['pickup_address'],
        o['delivery_address'],
        o['service'],
      ].where((v) => v != null).join(' ').toLowerCase();

      return statusOk && combined.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3F9),
      appBar: AppBar(
        elevation: 2,
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        centerTitle: false,
        titleSpacing: 8,
        title: Row(
          children: [
            Hero(
              tag: 'app_logo',
              child: ClipOval(
                child: Image.asset(
                  'assets/logo.png',
                  height: 32,
                  width: 32,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Laundry Admin',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE5E7EB),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              _loadRiders();
              _loadOrders();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
          // 👇 NEW: Price List admin button
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PriceListPage(),
                ),
              );
            },
            icon: const Icon(Icons.list_alt),
            tooltip: 'Manage Price List',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: loader,
        ),
      ),
      body: Column(
        children: [
          // summary & filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 8),

                // ✅ Wrap instead of Row for the stat chips
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _StatChip(
                      label: 'All',
                      value: _countByStatus('all'),
                      color: Colors.indigo.shade50,
                      textColor: Colors.indigo.shade700,
                    ),
                    _StatChip(
                      label: 'Pending',
                      value: _countByStatus('pending'),
                      color: Colors.amber.shade50,
                      textColor: Colors.amber.shade800,
                    ),
                    _StatChip(
                      label: 'Completed',
                      value: _countByStatus('completed'),
                      color: Colors.green.shade50,
                      textColor: Colors.green.shade700,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ✅ Responsive filter/search: avoids overflow on small screens
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 380;

                    if (isNarrow) {
                      // stack vertically
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _statusFilter,
                            items: _statusOptions
                                .map(
                                  (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s == 'all'
                                      ? 'All statuses'
                                      : s.replaceAll('_', ' '),
                                ),
                              ),
                            )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _statusFilter = v);
                            },
                            decoration: const InputDecoration(
                              labelText: 'Filter by status',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _searchCtl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText:
                              'Search customers, riders, address',
                              prefixIcon: const Icon(Icons.search),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              border: const OutlineInputBorder(),
                              suffixIcon: _searchCtl.text.isNotEmpty
                                  ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtl.clear();
                                  setState(() {});
                                },
                              )
                                  : null,
                            ),
                          ),
                        ],
                      );
                    }

                    // wide enough: row layout
                    return Row(
                      children: [
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String>(
                            value: _statusFilter,
                            items: _statusOptions
                                .map(
                                  (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s == 'all'
                                      ? 'All statuses'
                                      : s.replaceAll('_', ' '),
                                ),
                              ),
                            )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _statusFilter = v);
                            },
                            decoration: const InputDecoration(
                              labelText: 'Filter by status',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText:
                              'Search customers, riders, address',
                              prefixIcon: const Icon(Icons.search),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              border: const OutlineInputBorder(),
                              suffixIcon: _searchCtl.text.isNotEmpty
                                  ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtl.clear();
                                  setState(() {});
                                },
                              )
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          // orders list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadOrders,
              child: filtered.isEmpty
                  ? ListView(
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    Icons.inbox_outlined,
                    size: 72,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No matching orders found',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Adjust your filters or search keywords to see more results.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final o = filtered[i];
                  final customer =
                  o['customer'] as Map<String, dynamic>?;
                  final customerName =
                      customer?['full_name'] ?? o['customer_id'];
                  final rider =
                  o['rider'] as Map<String, dynamic>?;
                  final riderName =
                      rider?['full_name'] ?? 'Unassigned';

                  final status = (o['status'] ?? '').toString();
                  final orderId = o['id'].toString();
                  final proofUrl =
                  o['proof_of_billing_url'] as String?;
                  final badgeColor = _statusBadgeColor(status);
                  final totalPrice = o['total_price'];
                  final deliveryFee = o['delivery_fee'];
                  final notes = o['notes']?.toString().trim() ?? '';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: badgeColor.withOpacity(0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            // header row
                            Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customerName.toString(),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                          FontWeight.w700,
                                          color: primaryTextColor,
                                        ),
                                        overflow:
                                        TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding:
                                  const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor
                                        .withOpacity(0.12),
                                    borderRadius:
                                    BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _prettyStatus(status),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: badgeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // addresses
                            Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 18,
                                  color: Colors.indigo.shade400,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pickup Address',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        o['pickup_address'] ??
                                            'Not specified',
                                        style: const TextStyle(
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Delivery Address',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        o['delivery_address'] ??
                                            'Not specified',
                                        style: const TextStyle(
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // details
                            Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      if (o['service'] != null) ...[
                                        Text(
                                          'Service',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                            secondaryTextColor,
                                          ),
                                        ),
                                        Text(
                                          o['service'].toString(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                      if (o['payment_method'] !=
                                          null) ...[
                                        Text(
                                          'Payment Method',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                            secondaryTextColor,
                                          ),
                                        ),
                                        Text(
                                          o['payment_method']
                                              .toString(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                      if (notes.isNotEmpty) ...[
                                        Text(
                                          'Notes',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                            secondaryTextColor,
                                          ),
                                        ),
                                        Text(
                                          notes,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontStyle:
                                            FontStyle.italic,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                      Text(
                                        'Total Bill',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        totalPrice == null
                                            ? '₱0'
                                            : '₱$totalPrice',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                          FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Delivery Fee',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        deliveryFee == null
                                            ? '₱0'
                                            : '₱$deliveryFee',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                          FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Rider',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        riderName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                        ),
                                        overflow:
                                        TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Schedule',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        'Pickup: ${_formatDateTime(o['pickup_at'])}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        'Delivery: ${_formatDateTime(o['delivery_at'])}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            if (proofUrl != null &&
                                proofUrl.trim().isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _showProofDialog(proofUrl),
                                  icon: Icon(
                                    Icons.image,
                                    size: 18,
                                    color: Colors.teal.shade600,
                                  ),
                                  label: const Text(
                                    'View Proof of Billing',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 4),
                            const Divider(height: 16),

                            // actions
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _startEdit(o),
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: Colors.indigo.shade600,
                                  ),
                                  label: Text(
                                    'Edit',
                                    style: TextStyle(
                                      color:
                                      Colors.indigo.shade600,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () =>
                                      _deleteOrder(orderId),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Delete',
                                    style: TextStyle(
                                        color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // edit panel
          if (_editingOrderId != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: Colors.indigo.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Edit Order',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _editingOrderId = null;
                            _selectedRiderIdForEdit = null;
                            _selectedStatusForEdit = null;
                            _totalPriceController.clear();
                            _deliveryFeeController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_riders.isEmpty) ...[
                    const Text(
                      'No riders available. Ask riders to register in the Rider app to assign orders.',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      value: _selectedRiderIdForEdit ?? 'unassigned',
                      items: [
                        const DropdownMenuItem(
                          value: 'unassigned',
                          child: Text('Unassigned'),
                        ),
                        ..._riders.map(
                              (r) => DropdownMenuItem<String>(
                            value: r['id'] as String,
                            child: Text(
                              (r['full_name'] as String?) ??
                                  (r['phone'] as String?) ??
                                  (r['id'] as String),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedRiderIdForEdit = v),
                      decoration: const InputDecoration(
                        labelText: 'Assign Rider',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedStatusForEdit ?? 'pending',
                    items: _statusOptions
                        .where((s) => s != 'all')
                        .map(
                          (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.replaceAll('_', ' ')),
                      ),
                    )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedStatusForEdit = v),
                    decoration: const InputDecoration(
                      labelText: 'Order Status',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 8),
                  TextField(
                    controller: _totalPriceController,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Total Bill (₱)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 250 or 250.50',
                    ),
                  ),

                  const SizedBox(height: 8),
                  TextField(
                    controller: _deliveryFeeController,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'delivery_fee (₱)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 50 or 75.00',
                    ),
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loading ? null : _saveEdit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Save Changes'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _editingOrderId = null;
                            _selectedRiderIdForEdit = null;
                            _selectedStatusForEdit = null;
                            _totalPriceController.clear();
                            _deliveryFeeController.clear();
                          });
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color textColor;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value.toString(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
