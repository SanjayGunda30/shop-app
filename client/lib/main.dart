import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
const currency = '₹';
final money = NumberFormat.currency(locale: 'en_IN', symbol: currency, decimalDigits: 2);

const sampleItems = <Map<String, dynamic>>[
  {'id': 'i-1', 'name': 'Filter coffee', 'sku': 'DRK-001', 'price': 45.0, 'unit': 'cup', 'stock': 38.0, 'low_stock': 8.0, 'gst_rate': 5.0, 'hsn_sac': '9963', 'image_url': ''},
  {'id': 'i-2', 'name': 'Brown bread', 'sku': 'BAK-014', 'price': 48.0, 'unit': 'loaf', 'stock': 12.0, 'low_stock': 5.0, 'gst_rate': 0.0, 'hsn_sac': '1905', 'image_url': ''},
  {'id': 'i-3', 'name': 'Almond milk', 'sku': 'GRC-021', 'price': 125.0, 'unit': 'bottle', 'stock': 4.0, 'low_stock': 6.0, 'gst_rate': 5.0, 'hsn_sac': '2202', 'image_url': ''},
  {'id': 'i-4', 'name': 'Dark chocolate', 'sku': 'SNK-032', 'price': 90.0, 'unit': 'bar', 'stock': 21.0, 'low_stock': 5.0, 'gst_rate': 18.0, 'hsn_sac': '1806', 'image_url': ''},
  {'id': 'i-5', 'name': 'Masala chai', 'sku': 'DRK-009', 'price': 35.0, 'unit': 'cup', 'stock': 26.0, 'low_stock': 8.0, 'gst_rate': 5.0, 'hsn_sac': '9963', 'image_url': ''},
];

void main() => runApp(const LedgerlyApp());

class LedgerlyApp extends StatelessWidget {
  const LedgerlyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ledgerly POS', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, scaffoldBackgroundColor: const Color(0xfff5f6f3),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b59), primary: const Color(0xff176b59), surface: const Color(0xfffbfcfa)),
      textTheme: GoogleFonts.manropeTextTheme(), dividerColor: const Color(0xffe5e8e1),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xffdce1d8))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xffdce1d8)))),
    ), home: const PosHome(),
  );
}

class PosHome extends StatefulWidget {
  const PosHome({super.key});
  @override
  State<PosHome> createState() => _PosHomeState();
}

class _PosHomeState extends State<PosHome> {
  int page = 0;
  String role = 'admin';
  bool loading = false;
  int invoiceSequence = 0;
  List<Map<String, dynamic>> items = sampleItems.map((e) => Map<String, dynamic>.from(e)).toList();
  List<Map<String, dynamic>> sales = [];
  Map<String, dynamic> shop = {'name': 'The Green Counter', 'address': '18 Market Road, Bengaluru', 'phone': '+91 98765 43210', 'gstin': '', 'state': 'Karnataka', 'currency': 'INR'};
  Map<String, dynamic> report = {};
  final Map<String, int> cart = {};
  final search = TextEditingController();
  final placeOfSupply = TextEditingController(text: 'Karnataka');
  String paymentMode = 'UPI';
  String supplyType = 'intra_state';
  bool get isAdmin => role == 'admin';

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { search.dispose(); placeOfSupply.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString('ledgerly.localState');
      if (saved != null) {
        final state = Map<String, dynamic>.from(jsonDecode(saved));
        items = List<Map<String, dynamic>>.from((state['items'] as List).map((item) => Map<String, dynamic>.from(item)));
        sales = List<Map<String, dynamic>>.from((state['sales'] as List).map((sale) => Map<String, dynamic>.from(sale)));
        shop = Map<String, dynamic>.from(state['shop']);
        invoiceSequence = state['invoice_sequence'] as int? ?? 0;
      }
      final now = DateTime.now();
      final todaySales = sales.where((sale) {
        final date = DateTime.tryParse('${sale['created_at']}')?.toLocal();
        return date != null && date.year == now.year && date.month == now.month && date.day == now.day;
      }).toList();
      final lowStockCount = items.where((item) => _number(item['stock']) <= _number(item['low_stock'])).length;
      if (!mounted) return;
      setState(() {
        report = {
          'revenue': todaySales.fold<double>(0, (sum, sale) => sum + _number(sale['total'])),
          'sale_count': todaySales.length,
          'tax': todaySales.fold<double>(0, (sum, sale) => sum + _number(sale['tax'])),
          'item_count': items.length,
          'low_stock_count': lowStockCount,
        };
        placeOfSupply.text = '${shop['state'] ?? ''}';
      });
    } catch (_) { /* Keep sample data available if browser storage is unavailable. */ }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('ledgerly.localState', jsonEncode({
      'items': items,
      'sales': sales,
      'shop': shop,
      'invoice_sequence': invoiceSequence,
    }));
  }

  Future<void> _resetDemo() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('ledgerly.localState');
    setState(() {
      items = sampleItems.map((item) => Map<String, dynamic>.from(item)).toList();
      sales = [];
      shop = {'name': 'The Green Counter', 'address': '18 Market Road, Bengaluru', 'phone': '+91 98765 43210', 'gstin': '', 'state': 'Karnataka', 'currency': 'INR'};
      invoiceSequence = 0;
    });
    await _refresh();
    _notice('Local demo data reset');
  }
  void _notice(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  double _number(dynamic value) => (value as num?)?.toDouble() ?? 0;
  String _shortId(dynamic value) { final text = '$value'; return text.substring(0, text.length < 8 ? text.length : 8); }
  double get cartSubtotal => cart.entries.fold(0, (sum, entry) => sum + _number(items.firstWhere((item) => item['id'] == entry.key)['price']) * entry.value);
  double get cartTax => cart.entries.fold(0, (sum, entry) { final item = items.firstWhere((row) => row['id'] == entry.key); return sum + _number(item['price']) * entry.value * _number(item['gst_rate']) / 100; });

  Future<void> _saveItem([Map<String, dynamic>? item]) async {
    final name = TextEditingController(text: item?['name'] ?? ''); final sku = TextEditingController(text: item?['sku'] ?? '');
    final price = TextEditingController(text: '${item?['price'] ?? ''}'); final unit = TextEditingController(text: item?['unit'] ?? 'each');
    final stock = TextEditingController(text: '${item?['stock'] ?? 0}'); final gst = TextEditingController(text: '${item?['gst_rate'] ?? 0}');
    final hsn = TextEditingController(text: item?['hsn_sac'] ?? '');
    final image = TextEditingController(text: item?['image_url'] ?? '');
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => AlertDialog(
      title: Text(item == null ? 'Add item' : 'Edit item'), content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Item name')), const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: sku, decoration: const InputDecoration(labelText: 'SKU / code'))), const SizedBox(width: 10), Expanded(child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit')))]), const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price'))), const SizedBox(width: 10), Expanded(child: TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock on hand')))]), const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: gst, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'GST rate %'))), const SizedBox(width: 10), Expanded(child: TextField(controller: hsn, decoration: const InputDecoration(labelText: 'HSN / SAC')))]), const SizedBox(height: 10),
        TextField(controller: image, decoration: const InputDecoration(labelText: 'Image URL')),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'sku': sku.text.trim(), 'price': double.tryParse(price.text) ?? 0, 'unit': unit.text.trim(), 'stock': double.tryParse(stock.text) ?? 0, 'low_stock': item?['low_stock'] ?? 5, 'gst_rate': double.tryParse(gst.text) ?? 0, 'hsn_sac': hsn.text.trim(), 'image_url': image.text.trim()}), child: const Text('Save item'))],
    ));
    if (result == null || result['name'] == '' || result['sku'] == '') return;
    setState(() {
      if (item == null) {
        items.add({'id': 'item_${DateTime.now().microsecondsSinceEpoch}', ...result});
      } else {
        final index = items.indexWhere((row) => row['id'] == item['id']);
        if (index >= 0) items[index] = {...item, ...result};
      }
    });
    await _persist();
    _notice('Item saved in this browser');
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    setState(() => items.removeWhere((row) => row['id'] == item['id']));
    await _persist();
  }

  Future<void> _checkout() async {
    if (cart.isEmpty) return;
    for (final entry in cart.entries) {
      final item = items.firstWhere((row) => row['id'] == entry.key);
      if (_number(item['stock']) < entry.value) {
        _notice('Not enough stock for ${item['name']}');
        return;
      }
    }
    final now = DateTime.now();
    final financialYear = now.month >= 4 ? now.year : now.year - 1;
    invoiceSequence += 1;
    final invoiceNo = 'INV/${financialYear.toString().substring(2)}-${((financialYear + 1) % 100).toString().padLeft(2, '0')}/${invoiceSequence.toString().padLeft(5, '0')}';
    final lines = cart.entries.map((entry) {
      final item = items.firstWhere((row) => row['id'] == entry.key);
      final base = _number(item['price']) * entry.value;
      final tax = base * _number(item['gst_rate']) / 100;
      return {
        'id': 'line_${now.microsecondsSinceEpoch}_${entry.key}',
        'item_id': item['id'],
        'item_name': item['name'],
        'hsn_sac': item['hsn_sac'] ?? '',
        'quantity': entry.value,
        'unit_price': _number(item['price']),
        'gst_rate': _number(item['gst_rate']),
        'line_total': base + tax,
      };
    }).toList();
    final subtotal = lines.fold<double>(0, (sum, line) => sum + _number(line['unit_price']) * _number(line['quantity']));
    final tax = lines.fold<double>(0, (sum, line) => sum + _number(line['unit_price']) * _number(line['quantity']) * _number(line['gst_rate']) / 100);
    final sale = <String, dynamic>{
      'id': 'sale_${now.microsecondsSinceEpoch}',
      'invoice_no': invoiceNo,
      'supply_type': supplyType,
      'place_of_supply': placeOfSupply.text.trim(),
      'created_at': now.toIso8601String(),
      'payment_mode': paymentMode,
      'subtotal': subtotal,
      'tax': tax,
      'total': subtotal + tax,
      'cashier_name': 'Local demo',
      'lines': lines,
    };
    setState(() {
      for (final entry in cart.entries) {
        final index = items.indexWhere((item) => item['id'] == entry.key);
        items[index]['stock'] = _number(items[index]['stock']) - entry.value;
      }
      cart.clear();
      sales.insert(0, sale);
    });
    await _persist();
    await _refresh();
    await _invoice(sale);
  }

  Future<void> _invoice(Map<String, dynamic> sale) async {
    final document = pw.Document(); final lines = List<Map<String, dynamic>>.from(sale['lines'] ?? []);
    final interstate = sale['supply_type'] == 'inter_state'; final tax = _number(sale['tax']);
    document.addPage(pw.Page(build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(shop['name'] ?? 'Shop', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)), pw.Text(shop['address'] ?? ''), pw.Text('${shop['state'] ?? ''}  |  Phone: ${shop['phone'] ?? ''}'), pw.Text('Supplier GSTIN: ${shop['gstin'] ?? 'Not provided'}'), pw.SizedBox(height: 22),
      pw.Text('TAX INVOICE  ${sale['invoice_no'] ?? sale['id'] ?? ''}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)), pw.Text(DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.tryParse('${sale['created_at']}') ?? DateTime.now())), pw.Text('Place of supply: ${sale['place_of_supply'] ?? ''}'), pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(headers: ['Item', 'HSN/SAC', 'Qty', 'Rate', 'GST', 'Amount'], data: lines.map((line) => [line['item_name'], line['hsn_sac'] ?? '', '${line['quantity']}', money.format(line['unit_price']), '${line['gst_rate']}%', money.format(line['line_total'])]).toList()), pw.SizedBox(height: 16),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('Taxable value: ${money.format(sale['subtotal'])}'), if (interstate) pw.Text('IGST: ${money.format(tax)}') else ...[pw.Text('CGST: ${money.format(tax / 2)}'), pw.Text('SGST: ${money.format(tax / 2)}')], pw.Text('Total: ${money.format(sale['total'])}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)), pw.Text('Paid by ${sale['payment_mode']}')])), pw.Spacer(), pw.Center(child: pw.Text('Thank you for shopping with us')),
    ])));
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }

  Future<void> _saveShop() async {
    final name = TextEditingController(text: '${shop['name'] ?? ''}'); final address = TextEditingController(text: '${shop['address'] ?? ''}');
    final phone = TextEditingController(text: '${shop['phone'] ?? ''}'); final gstin = TextEditingController(text: '${shop['gstin'] ?? ''}'); final state = TextEditingController(text: '${shop['state'] ?? ''}');
    final saved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Shop profile'), content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Shop name')), const SizedBox(height: 10), TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')), const SizedBox(height: 10), TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')), const SizedBox(height: 10), TextField(controller: gstin, decoration: const InputDecoration(labelText: 'GSTIN')), const SizedBox(height: 10), TextField(controller: state, decoration: const InputDecoration(labelText: 'Supplier state'))])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (saved != true) return;
    final next = {...shop, 'name': name.text, 'address': address.text, 'phone': phone.text, 'gstin': gstin.text, 'state': state.text, 'currency': 'INR'};
    setState(() { shop = next; placeOfSupply.text = state.text; });
    await _persist();
    _notice('Shop profile saved in this browser');
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final titles = ['Overview', 'Point of sale', 'Inventory', 'Sales', 'Settings'];
    final icons = [Icons.grid_view_rounded, Icons.point_of_sale_rounded, Icons.inventory_2_outlined, Icons.receipt_long_outlined, Icons.storefront_outlined];
    final visiblePages = isAdmin ? [0, 1, 2, 3, 4] : role == 'cashier' ? [0, 1, 2, 3] : [0, 2, 3, 4];
    if (!visiblePages.contains(page)) page = 0;
    final sidebar = Container(
      width: 224,
      color: const Color(0xff192b27),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(23, 22, 20, 30),
              child: Row(children: [
                const Icon(Icons.bolt_rounded, color: Color(0xffb9e0a5), size: 27),
                const SizedBox(width: 10),
                Text('ledgerly', style: GoogleFonts.manrope(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
            for (final index in visiblePages) _navItem(index, titles[index], icons[index]),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: const Color(0xff263a35), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const CircleAvatar(radius: 17, backgroundColor: Color(0xffb9e0a5), child: Icon(Icons.storage_outlined, size: 18, color: Color(0xff192b27))),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Local demo', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(role.toUpperCase(), style: const TextStyle(color: Color(0xffadc2b9), fontSize: 10)),
                  ])),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
    final header = Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(color: Color(0xfffbfcfa), border: Border(bottom: BorderSide(color: Color(0xffe5e8e1)))),
      child: Row(children: [
        if (!wide) const Icon(Icons.bolt_rounded, color: Color(0xff176b59)),
        if (!wide) const SizedBox(width: 10),
        Text(titles[page], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff20302b))),
        const Spacer(),
        Text('Local demo · ${DateFormat('EEE, d MMM').format(DateTime.now())}', style: const TextStyle(color: Color(0xff78847d), fontSize: 12)),
        const SizedBox(width: 14),
        IconButton(tooltip: 'Reload local data', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, size: 20)),
      ]),
    );
    return Scaffold(
      body: Row(children: [
        if (wide) sidebar,
        Expanded(child: SafeArea(child: Column(children: [
          header,
          Expanded(child: loading && report.isEmpty ? const Center(child: CircularProgressIndicator()) : _pageView()),
          if (!wide) NavigationBar(
            selectedIndex: visiblePages.indexOf(page),
            onDestinationSelected: (value) => setState(() => page = visiblePages[value]),
            destinations: [for (final index in visiblePages) NavigationDestination(icon: Icon(icons[index]), label: titles[index])],
          ),
        ]))),
      ]),
    );
  }

  Widget _navItem(int index, String title, IconData icon) {
    final selected = page == index;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2), child: ListTile(selected: selected, selectedTileColor: const Color(0xff30463f), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)), leading: Icon(icon, size: 19, color: selected ? const Color(0xffc1e5aa) : const Color(0xffadc2b9)), title: Text(title, style: TextStyle(color: selected ? Colors.white : const Color(0xffd1ddd7), fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)), onTap: () => setState(() => page = index));
  }

  Widget _pageView() => switch (page) { 0 => _dashboard(), 1 => _pos(), 2 => _inventory(), 3 => _sales(), _ => _settings() };

  Widget _dashboard() {
    final revenue = _number(report['revenue']); final saleCount = _number(report['sale_count']);
    final low = items.where((item) => _number(item['stock']) <= _number(item['low_stock'])).toList();
    return ListView(padding: const EdgeInsets.all(28), children: [
      Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Good ${DateTime.now().hour < 12 ? 'morning' : 'afternoon'}', style: const TextStyle(color: Color(0xff78847d), fontSize: 13)), const SizedBox(height: 4), Text(shop['name'] ?? 'Your shop', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xff20302b)))])), if (isAdmin) FilledButton.icon(onPressed: () => setState(() => page = 1), icon: const Icon(Icons.add, size: 18), label: const Text('New sale'))]),
      const SizedBox(height: 23), LayoutBuilder(builder: (context, box) { final count = box.maxWidth > 900 ? 4 : box.maxWidth > 550 ? 2 : 1; return GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: count, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: count == 1 ? 3.4 : 1.65, children: [
        _metric('Today’s sales', money.format(revenue), Icons.payments_outlined, '+$saleCount bills', const Color(0xff176b59)),
        _metric('Transactions', '${report['sale_count'] ?? 0}', Icons.receipt_long_outlined, 'Today', const Color(0xffc57c2d)),
        _metric('Items in catalogue', '${report['item_count'] ?? items.length}', Icons.inventory_2_outlined, '${items.length} active products', const Color(0xff426b9a)),
        _metric('Needs restock', '${report['low_stock_count'] ?? low.length}', Icons.warning_amber_rounded, 'At or below threshold', const Color(0xffb0523c)),
      ]); }), const SizedBox(height: 24),
      LayoutBuilder(builder: (context, box) => Flex(direction: box.maxWidth > 780 ? Axis.horizontal : Axis.vertical, crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExpandedIfWide(wide: box.maxWidth > 780, child: _section('Recent sales', trailing: TextButton(onPressed: () => setState(() => page = 3), child: const Text('All sales')), child: _recentSales())),
        SizedBox(width: box.maxWidth > 780 ? 16 : 0, height: box.maxWidth > 780 ? 0 : 16),
        ExpandedIfWide(wide: box.maxWidth > 780, child: _section('Restock watch', trailing: Text('${low.length} items', style: const TextStyle(color: Color(0xff78847d), fontSize: 12)), child: low.isEmpty ? const Padding(padding: EdgeInsets.all(18), child: Text('Everything is looking stocked.')) : Column(children: low.take(5).map((item) => _stockRow(item)).toList()))),
      ])),
    ]);
  }

  Widget _metric(String title, String value, IconData icon, String note, Color color) => Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: const Color(0xfffbfcfa), border: Border.all(color: const Color(0xffe5e8e1)), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Icon(icon, color: color, size: 19), const Spacer(), Text(note, style: const TextStyle(fontSize: 10, color: Color(0xff78847d)))]), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff20302b))), Text(title, style: const TextStyle(fontSize: 12, color: Color(0xff78847d)))]));
  Widget _section(String title, {required Widget child, Widget? trailing}) => Container(width: double.infinity, decoration: BoxDecoration(color: const Color(0xfffbfcfa), border: Border.all(color: const Color(0xffe5e8e1)), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.fromLTRB(17, 13, 12, 11), child: Row(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), const Spacer(), if (trailing != null) trailing])), const Divider(height: 1), child]));
  Widget _recentSales() => sales.isEmpty ? const Padding(padding: EdgeInsets.all(18), child: Text('No sales recorded yet.')) : Column(children: sales.take(5).map((sale) => ListTile(dense: true, leading: const CircleAvatar(radius: 16, backgroundColor: Color(0xffe7f0e9), child: Icon(Icons.receipt_outlined, size: 16, color: Color(0xff176b59))), title: Text('Sale #${sale['invoice_no'] ?? _shortId(sale['id'])}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), subtitle: Text('${sale['payment_mode'] ?? ''} · ${sale['cashier_name'] ?? ''}', style: const TextStyle(fontSize: 10)), trailing: Text(money.format(_number(sale['total'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))).toList());
  Widget _stockRow(Map<String, dynamic> item) => ListTile(dense: true, title: Text('${item['name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), subtitle: Text('SKU ${item['sku']}', style: const TextStyle(fontSize: 10)), trailing: Text('${item['stock']} ${item['unit']}', style: const TextStyle(color: Color(0xffb0523c), fontWeight: FontWeight.w800, fontSize: 12)));

  Widget _inventory() {
    final filtered = items.where((item) => '${item['name']} ${item['sku']}'.toLowerCase().contains(search.text.toLowerCase())).toList();
    return ListView(padding: const EdgeInsets.all(26), children: [Row(children: [Expanded(child: Text('${items.length} products', style: const TextStyle(color: Color(0xff78847d), fontSize: 12))), SizedBox(width: 260, child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Search name or SKU', prefixIcon: Icon(Icons.search, size: 19), contentPadding: EdgeInsets.symmetric(vertical: 10)))), if (isAdmin) ...[const SizedBox(width: 12), FilledButton.icon(onPressed: () => _saveItem(), icon: const Icon(Icons.add, size: 18), label: const Text('Add item'))]]), const SizedBox(height: 16), _section('Inventory', child: filtered.isEmpty ? const Padding(padding: EdgeInsets.all(22), child: Text('No matching items')) : Column(children: [if (MediaQuery.sizeOf(context).width > 650) const Padding(padding: EdgeInsets.symmetric(horizontal: 17, vertical: 10), child: Row(children: [Expanded(flex: 4, child: Text('ITEM', style: TextStyle(fontSize: 10, color: Color(0xff78847d), fontWeight: FontWeight.w700))), Expanded(flex: 2, child: Text('PRICE', style: TextStyle(fontSize: 10, color: Color(0xff78847d), fontWeight: FontWeight.w700))), Expanded(flex: 2, child: Text('ON HAND', style: TextStyle(fontSize: 10, color: Color(0xff78847d), fontWeight: FontWeight.w700))), Expanded(flex: 2, child: Text('GST', style: TextStyle(fontSize: 10, color: Color(0xff78847d), fontWeight: FontWeight.w700))), SizedBox(width: 70)])), const Divider(height: 1), for (final item in filtered) _inventoryRow(item)]))]);
  }

  Widget _inventoryRow(Map<String, dynamic> item) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [CircleAvatar(radius: 17, backgroundColor: const Color(0xffe8eee8), child: Text('${item['name']}'.isEmpty ? '?' : '${item['name']}'.substring(0, 1).toUpperCase(), style: const TextStyle(color: Color(0xff176b59), fontSize: 12, fontWeight: FontWeight.w800))), const SizedBox(width: 10), Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${item['name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), Text('${item['sku']} · ${item['unit']}', style: const TextStyle(fontSize: 10, color: Color(0xff78847d)))])), if (MediaQuery.sizeOf(context).width > 650) ...[Expanded(flex: 2, child: Text(money.format(_number(item['price'])), style: const TextStyle(fontSize: 12))), Expanded(flex: 2, child: Text('${item['stock']} ${item['unit']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _number(item['stock']) <= _number(item['low_stock']) ? const Color(0xffb0523c) : const Color(0xff20302b)))), Expanded(flex: 2, child: Text('${item['gst_rate']}%', style: const TextStyle(fontSize: 12)))], if (isAdmin) SizedBox(width: 70, child: Row(children: [IconButton(tooltip: 'Edit item', onPressed: () => _saveItem(item), icon: const Icon(Icons.edit_outlined, size: 17)), IconButton(tooltip: 'Delete item', onPressed: () => _deleteItem(item), icon: const Icon(Icons.delete_outline, size: 17))]))]));

  Widget _pos() {
    final filtered = items.where((item) => '${item['name']} ${item['sku']}'.toLowerCase().contains(search.text.toLowerCase())).toList();
    final wide = MediaQuery.sizeOf(context).width > 850;
    return Padding(padding: const EdgeInsets.all(20), child: Flex(direction: wide ? Axis.horizontal : Axis.vertical, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: Column(children: [TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Find a product by name or code')), const SizedBox(height: 14), Expanded(child: GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: wide ? 3 : 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.65), itemCount: filtered.length, itemBuilder: (context, index) { final item = filtered[index]; final unavailable = _number(item['stock']) <= 0; return InkWell(onTap: unavailable ? null : () => setState(() => cart.update('${item['id']}', (qty) => qty + 1, ifAbsent: () => 1)), borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xffe5e8e1)), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [const Icon(Icons.local_cafe_outlined, color: Color(0xff176b59), size: 19), const Spacer(), Text('${item['stock']} ${item['unit']}', style: const TextStyle(fontSize: 10, color: Color(0xff78847d)))]), Text('${item['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), Text(money.format(_number(item['price'])), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff176b59)))])); }) )])),
      SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 14),
      SizedBox(width: wide ? 340 : double.infinity, height: wide ? null : 400, child: Column(children: [DropdownButtonFormField<String>(initialValue: supplyType, decoration: const InputDecoration(labelText: 'Tax supply type', isDense: true), items: const [DropdownMenuItem(value: 'intra_state', child: Text('Intra-state · CGST + SGST')), DropdownMenuItem(value: 'inter_state', child: Text('Inter-state · IGST'))], onChanged: (value) { if (value != null) setState(() => supplyType = value); }), const SizedBox(height: 8), TextField(controller: placeOfSupply, decoration: const InputDecoration(labelText: 'Place of supply (state)', isDense: true)), const SizedBox(height: 8), Expanded(child: _cartPanel())])),
    ]));
  }

  Widget _cartPanel() => Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: const Color(0xfffbfcfa), border: Border.all(color: const Color(0xffe5e8e1)), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text('Current sale', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const Spacer(), Text('${cart.values.fold<int>(0, (a, b) => a + b)} items', style: const TextStyle(fontSize: 11, color: Color(0xff78847d)))]), const Divider(height: 22), Expanded(child: cart.isEmpty ? const Center(child: Text('Tap an item to add it here', style: TextStyle(color: Color(0xff78847d), fontSize: 12))) : ListView(children: cart.entries.map((entry) { final item = items.firstWhere((row) => row['id'] == entry.key); return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Text(money.format(_number(item['price'])), style: const TextStyle(fontSize: 10, color: Color(0xff78847d)))])), IconButton(onPressed: () => setState(() { if (entry.value <= 1) { cart.remove(entry.key); } else { cart[entry.key] = entry.value - 1; } }), icon: const Icon(Icons.remove_circle_outline, size: 18)), Text('${entry.value}', style: const TextStyle(fontSize: 12)), IconButton(onPressed: () => setState(() => cart[entry.key] = entry.value + 1), icon: const Icon(Icons.add_circle_outline, size: 18)), Text(money.format(_number(item['price']) * entry.value), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))])); }).toList())), const Divider(height: 20), Row(children: [const Text('Taxable value', style: TextStyle(fontSize: 12)), const Spacer(), Text(money.format(cartSubtotal), style: const TextStyle(fontSize: 12))]), const SizedBox(height: 7), Row(children: [const Text('GST', style: TextStyle(fontSize: 12)), const Spacer(), Text(money.format(cartTax), style: const TextStyle(fontSize: 12))]), const SizedBox(height: 12), Row(children: [const Text('Total due', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const Spacer(), Text(money.format(cartSubtotal + cartTax), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: Color(0xff176b59)))]), const SizedBox(height: 12), SegmentedButton<String>(segments: const [ButtonSegment(value: 'Cash', label: Text('Cash')), ButtonSegment(value: 'UPI', label: Text('UPI')), ButtonSegment(value: 'Card', label: Text('Card'))], selected: {paymentMode}, onSelectionChanged: (value) => setState(() => paymentMode = value.first)), const SizedBox(height: 11), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: cart.isEmpty ? null : _checkout, icon: const Icon(Icons.check), label: const Text('Charge & print invoice'))]));

  Widget _sales() => ListView(padding: const EdgeInsets.all(26), children: [Text('${sales.length} recent transactions', style: const TextStyle(color: Color(0xff78847d), fontSize: 12)), const SizedBox(height: 15), _section('Sales history', child: sales.isEmpty ? const Padding(padding: EdgeInsets.all(22), child: Text('Completed transactions appear here.')) : Column(children: sales.map((sale) => ListTile(leading: const Icon(Icons.receipt_long_outlined, color: Color(0xff176b59)), title: Text('Invoice ${sale['invoice_no'] ?? _shortId(sale['id'])}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), subtitle: Text('${sale['created_at'] ?? ''} · ${sale['payment_mode'] ?? ''} · ${sale['cashier_name'] ?? ''}', style: const TextStyle(fontSize: 11)), trailing: Text(money.format(_number(sale['total'])), style: const TextStyle(fontWeight: FontWeight.w800)))).toList()))]);
  Widget _settings() => ListView(
    padding: const EdgeInsets.all(26),
    children: [
      const Text('Local browser data', style: TextStyle(color: Color(0xff78847d), fontSize: 12)),
      const SizedBox(height: 15),
      _section(
        'Invoice identity',
        trailing: isAdmin ? IconButton(tooltip: 'Edit profile', onPressed: _saveShop, icon: const Icon(Icons.edit_outlined, size: 18)) : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${shop['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text('${shop['address']}', style: const TextStyle(color: Color(0xff78847d))),
            Text('${shop['state']} · ${shop['phone']}', style: const TextStyle(color: Color(0xff78847d))),
            const SizedBox(height: 6),
            Text('GSTIN  ${shop['gstin']?.toString().isEmpty ?? true ? 'Not added' : shop['gstin']}', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      _section(
        'Role preview',
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Role previews only; this demo has no sign-in or permission security.', style: TextStyle(fontSize: 12, color: Color(0xff78847d))),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final value in ['admin', 'cashier', 'viewer'])
                  ChoiceChip(
                    label: Text(value),
                    selected: role == value,
                    onSelected: (_) {
                      setState(() {
                        role = value;
                        if (page >= 4 && value != 'admin') page = 0;
                      });
                    },
                  ),
              ],
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: _resetDemo, icon: const Icon(Icons.restart_alt), label: const Text('Reset local demo data'))),
    ],
  );
}

class ExpandedIfWide extends StatelessWidget {
  const ExpandedIfWide({super.key, required this.wide, required this.child});
  final bool wide; final Widget child;
  @override
  Widget build(BuildContext context) => wide ? Expanded(child: child) : child;
}
