import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 👈 for RealtimeChannel
import '../supabase_config.dart';

class PriceListPage extends StatefulWidget {
  const PriceListPage({
    super.key,
    this.editable = false,
  });

  /// When true, allows add/edit/delete of price list entries.
  final bool editable;

  @override
  State<PriceListPage> createState() => _PriceListPageState();
}

class _PriceListPageState extends State<PriceListPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _rows = [];

  // 👇 Realtime channel to listen for admin edits in price_list
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadRows();
    _initRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // 👇 subscribe to price_list changes so customer sees updates automatically
  void _initRealtime() {
    _channel?.unsubscribe();

    _channel = supabase.channel('price_list_changes').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'price_list',
      callback: (_) {
        // whenever admin inserts/updates/deletes in price_list, reload
        _loadRows();
      },
    ).subscribe();
  }

  Future<void> _loadRows() async {
    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('price_list')
          .select()
          .order('sort_order', ascending: true);

      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load price list: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------- UI HELPERS ---------

  InputDecoration _fieldDecoration(
      String label, {
        String? hint,
      }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.indigo.shade500, width: 1.4),
      ),
    );
  }

  double? _parsePrice(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final cleaned = trimmed
        .replaceAll('₱', '')
        .replaceAll(',', '')
        .trim();

    return double.tryParse(cleaned);
  }

  String _formatPrice(double value) {
    // No decimals if it's a whole number, otherwise 2 decimals
    if (value % 1 == 0) {
      return '₱${value.toStringAsFixed(0)}';
    }
    return '₱${value.toStringAsFixed(2)}';
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // --------- CRUD HELPERS ---------

  Future<void> _upsertRow({
    Map<String, dynamic>? existingRow,
    required String type,
    required String label,
    String? price,
  }) async {
    try {
      final isEdit = existingRow != null;
      final id = existingRow?['id'];

      final data = <String, dynamic>{
        'type': type,
        'label': label,
      };

      // Only items have prices, others set to null
      if (type == 'item') {
        if (price != null && price.trim().isNotEmpty) {
          data['price'] = price.trim();
        } else {
          data['price'] = null;
        }
      } else {
        data['price'] = null;
      }

      if (isEdit) {
        await supabase.from('price_list').update(data).eq('id', id);
      } else {
        // new row, assign sort_order at the end
        int nextSortOrder = 1;
        if (_rows.isNotEmpty) {
          final last = _rows.last;
          final lastSortOrder =
              (last['sort_order'] as int?) ?? _rows.length;
          nextSortOrder = lastSortOrder + 1;
        }
        data['sort_order'] = nextSortOrder;
        await supabase.from('price_list').insert(data);
      }

      // Realtime will trigger _loadRows too, but this keeps UI snappy if needed
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save row: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;

    try {
      await supabase.from('price_list').delete().eq('id', id);
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete row: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final label = (row['label'] ?? '').toString();
    final type = (row['type'] ?? 'item').toString();

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete row?',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: Text(
            type == 'divider'
                ? 'Are you sure you want to delete this divider?'
                : 'Are you sure you want to delete "$label"?',
          ),
          actionsPadding:
          const EdgeInsets.only(right: 16, bottom: 10, left: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteRow(row);
    }
  }

  void _showRowDialog({Map<String, dynamic>? row}) {
    final isEdit = row != null;
    final labelController = TextEditingController(
      text: row?['label']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: row?['price']?.toString() ?? '',
    );
    String selectedType = (row?['type'] ?? 'item').toString();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              titlePadding:
              const EdgeInsets.only(top: 18, left: 20, right: 20),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              actionsPadding:
              const EdgeInsets.only(right: 16, bottom: 10, left: 16),
              title: Text(
                isEdit ? 'Edit Entry' : 'Add Entry',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: _fieldDecoration('Type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'item',
                          child: Text('Item (service + price)'),
                        ),
                        DropdownMenuItem(
                          value: 'header',
                          child: Text('Header'),
                        ),
                        DropdownMenuItem(
                          value: 'note',
                          child: Text('Note'),
                        ),
                        DropdownMenuItem(
                          value: 'divider',
                          child: Text('Divider'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setStateDialog(() {
                          selectedType = val;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    if (selectedType != 'divider') ...[
                      TextField(
                        controller: labelController,
                        decoration: _fieldDecoration(
                          'Label / Description',
                        ),
                      ),
                    ],
                    if (selectedType == 'item') ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: priceController,
                        keyboardType:
                        const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _fieldDecoration(
                          'Price',
                          hint: 'Numbers only, no ₱',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (isEdit)
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _confirmDelete(row!);
                    },
                    child: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  onPressed: () async {
                    final label = labelController.text.trim();
                    final price = priceController.text.trim();

                    if (selectedType != 'divider' && label.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                          const Text('Label cannot be empty.'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.of(ctx).pop();
                    await _upsertRow(
                      existingRow: row,
                      type: selectedType,
                      label: label,
                      price: selectedType == 'item' ? price : null,
                    );
                  },
                  child: Text(isEdit ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF4F46E5);
    final primaryTextColor = Colors.grey.shade900;
    final secondaryTextColor = Colors.grey.shade600;
    final backgroundColor = const Color(0xFFF4F4FB);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: primaryTextColor,
        centerTitle: false,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.editable ? 'Manage Price List' : 'Service Price Guide',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.editable
                  ? 'Update your laundry pricing in real time'
                  : 'Updated automatically when prices change',
              style: TextStyle(
                fontSize: 11.5,
                color: secondaryTextColor,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _loadRows,
          ),
          // 👇 Edit button that opens editable version of this page
          if (!widget.editable)
            IconButton(
              tooltip: 'Edit prices',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PriceListPage(editable: true),
                  ),
                );
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Column(
            children: [
              if (_loading)
                const LinearProgressIndicator(minHeight: 2)
              else
                const SizedBox(height: 2),
              Container(
                height: 0.5,
                color: Colors.grey.shade200,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.editable
          ? FloatingActionButton.extended(
        onPressed: () => _showRowDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 3,
      )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadRows,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: (_rows.isEmpty ? 1 : _rows.length + 1),
          itemBuilder: (context, i) {
            // Top intro card
            if (i == 0) {
              // 🔢 Compute some stats from current data
              final itemRows = _rows
                  .where((r) => (r['type'] ?? 'item').toString() == 'item')
                  .toList();

              final prices = itemRows
                  .map((r) => _parsePrice(r['price']?.toString()))
                  .whereType<double>()
                  .toList();

              int itemCount = itemRows.length;
              double? minPrice;
              double? maxPrice;
              double? avgPrice;

              if (prices.isNotEmpty) {
                prices.sort();
                minPrice = prices.first;
                maxPrice = prices.last;
                avgPrice =
                    prices.reduce((a, b) => a + b) / prices.length;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withOpacity(0.12),
                      primaryColor.withOpacity(0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: primaryColor.withOpacity(0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.local_laundry_service_outlined,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.editable
                                ? 'Edit Laundry Service Pricing'
                                : 'Laundry Service Pricing',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _rows.isEmpty
                                ? (widget.editable
                                ? 'No price list is configured yet. Tap "Add entry" to create one.'
                                : 'No price list is available yet. Please check again later.')
                                : (widget.editable
                                ? 'Tap on any row to edit it. Use the + button to add new headers, notes, dividers, or services.'
                                : 'Below is an overview of our standard service rates for washing, ironing, dry cleaning, and delivery.'),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: secondaryTextColor,
                            ),
                          ),
                          if (_rows.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (itemCount > 0)
                                  _buildStatChip(
                                    icon: Icons.list_alt,
                                    label: 'Services',
                                    value: '$itemCount items',
                                    color: primaryColor,
                                  ),
                                if (minPrice != null && maxPrice != null)
                                  _buildStatChip(
                                    icon: Icons.swap_vert,
                                    label: 'Price range',
                                    value:
                                    '${_formatPrice(minPrice)} – ${_formatPrice(maxPrice)}',
                                    color: Colors.teal,
                                  ),
                                if (avgPrice != null)
                                  _buildStatChip(
                                    icon: Icons.stacked_bar_chart,
                                    label: 'Average price',
                                    value: _formatPrice(avgPrice),
                                    color: Colors.deepOrange,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            if (_rows.isEmpty) {
              // no rows, just show empty state after intro card
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.editable
                            ? 'No prices configured.\nTap the + button to add one.'
                            : 'No prices configured yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final row = _rows[i - 1];
            final type = (row['type'] ?? 'item').toString();
            final label = (row['label'] ?? '').toString();
            final price = row['price']?.toString();

            Widget buildHeader() {
              return Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: primaryTextColor,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget buildDividerRow() {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        thickness: 0.9,
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget buildNoteRow() {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: secondaryTextColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget buildItemRow() {
              final displayPrice = (price == null || price.isEmpty)
                  ? ''
                  : (price.startsWith('₱') ? price : '₱$price');

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                      if (displayPrice.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            displayPrice,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                      // EDIT BUTTON PER ROW (only shows in editable mode)
                      if (widget.editable) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: Colors.grey.shade500,
                          ),
                          tooltip: 'Edit',
                          onPressed: () => _showRowDialog(row: row),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            Widget content;

            if (type == 'header') {
              content = buildHeader();
            } else if (type == 'divider') {
              content = buildDividerRow();
            } else if (type == 'note') {
              content = buildNoteRow();
            } else {
              // item
              content = buildItemRow();
            }

            if (!widget.editable) return content;

            // Tappable/editable wrapper for admin mode
            return InkWell(
              onTap: () => _showRowDialog(row: row),
              onLongPress: () => _confirmDelete(row),
              borderRadius: BorderRadius.circular(14),
              child: content,
            );
          },
        ),
      ),
    );
  }
}
