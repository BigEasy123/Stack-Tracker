import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const GoldTrackerApp());
}

class Purchase {
  final String metal;
  final double quantity;
  final double purchasePrice;
  final DateTime date;

  Purchase({
    required this.metal,
    required this.quantity,
    required this.purchasePrice,
    required this.date,
  });

  double currentPrice(Map<String, double> latestPrices) {
    return latestPrices[metal] ?? 0.0;
  }

  double currentValue(Map<String, double> latestPrices) {
    return currentPrice(latestPrices) * quantity;
  }

  double investedValue() => purchasePrice * quantity;

  double profitLoss(Map<String, double> latestPrices) =>
      currentValue(latestPrices) - investedValue();
}

class GoldTrackerApp extends StatelessWidget {
  const GoldTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stack Tracker',
      theme: ThemeData(
        primarySwatch: Colors.amber,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.amber,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
        ),
        textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.white)),
      ),
      themeMode: ThemeMode.system,
      home: const InvestmentFormPage(),
    );
  }
}

class InvestmentFormPage extends StatefulWidget {
  const InvestmentFormPage({super.key});

  @override
  State<InvestmentFormPage> createState() => _InvestmentFormPageState();
}

class _InvestmentFormPageState extends State<InvestmentFormPage> {
  final _metalCodes = {
    'Gold': 'XAU',
    'Silver': 'XAG',
    'Platinum': 'XPT',
    'Palladium': 'XPD',
  };

  final String _apiKey = 'c510fd073bc6dfb09de4026c71cda31f';

  final List<Purchase> _purchases = [];
  Map<String, double> _latestPrices = {};
  bool _isLoading = true;

  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  String _selectedMetal = 'Gold';

  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _fetchPrices();
    Timer.periodic(const Duration(minutes: 15), (_) => _fetchPrices());

    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-9980659109157314/6900972691', // Test ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdReady = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _isBannerAdReady = false);
        },
      ),
    )..load();
  }

  Future<void> _fetchPrices() async {
    setState(() => _isLoading = true);

    final url = Uri.parse(
      'https://metal-price-api-wf1l.onrender.com', // CHANGE THIS TO YOUR REAL URL
    );

    try {
      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data.containsKey('rates')) {
        final rates = Map<String, num>.from(data['rates']);

        setState(() {
          _latestPrices = {
            for (var entry in _metalCodes.entries)
              entry.key: (rates['USD${entry.value}'] ?? 0).toDouble(),
          };
          _isLoading = false;
        });
      } else if (data.containsKey('error')) {
        throw Exception(data['error']);
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching prices: $e')));
      setState(() {
        _latestPrices = {};
        _isLoading = false;
      });
    }
  }

  void _addPurchase() {
    final quantity = double.tryParse(_quantityController.text);
    final price = double.tryParse(_priceController.text);
    if (quantity == null || price == null) return;

    setState(() {
      _purchases.add(
        Purchase(
          metal: _selectedMetal,
          quantity: quantity,
          purchasePrice: price,
          date: DateTime.now(),
        ),
      );
      _quantityController.clear();
      _priceController.clear();
    });
  }

  Future<void> _exportPurchases() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/purchases.csv';
    final file = File(path);

    final buffer = StringBuffer();
    buffer.writeln('Metal,Quantity,PurchasePrice,Date');
    for (final p in _purchases) {
      buffer.writeln(
        '${p.metal},${p.quantity},${p.purchasePrice},${p.date.toIso8601String()}',
      );
    }

    await file.writeAsString(buffer.toString());

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Exported to: $path')));
  }

  Future<void> _importPurchases() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final lines = await file.readAsLines();

      final newPurchases = <Purchase>[];

      for (int i = 1; i < lines.length; i++) {
        final parts = lines[i].split(',');
        if (parts.length == 4) {
          try {
            final metal = parts[0];
            final quantity = double.parse(parts[1]);
            final price = double.parse(parts[2]);
            final date = DateTime.parse(parts[3]);
            newPurchases.add(
              Purchase(
                metal: metal,
                quantity: quantity,
                purchasePrice: price,
                date: date,
              ),
            );
          } catch (_) {
            // Skip invalid lines
          }
        }
      }

      setState(() {
        _purchases.addAll(newPurchases);
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Purchases imported!')));
    }
  }

  double get _totalProfitLoss =>
      _purchases.fold(0, (sum, p) => sum + p.profitLoss(_latestPrices));

  List<FlSpot> _generateChartSpots() {
    _purchases.sort((a, b) => a.date.compareTo(b.date));
    double cumulative = 0;
    List<FlSpot> spots = [];
    for (int i = 0; i < _purchases.length; i++) {
      cumulative += _purchases[i].investedValue();
      spots.add(FlSpot(i.toDouble(), cumulative));
    }
    return spots;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _bannerAd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chartSpots = _generateChartSpots();

    return Scaffold(
      appBar: AppBar(title: const Text('Stack Tracker v1.0.0')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              )
            else
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _latestPrices.entries
                      .map((e) => '${e.key}: \$${e.value.toStringAsFixed(2)}')
                      .join(' | '),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  DropdownButton<String>(
                    value: _selectedMetal,
                    items: _metalCodes.keys
                        .map(
                          (metal) => DropdownMenuItem(
                            value: metal,
                            child: Text(metal),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedMetal = val!),
                  ),
                  TextField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity (oz)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  TextField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Purchase Price per oz',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _addPurchase,
                    child: const Text('Add Purchase'),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Export CSV'),
                        onPressed: _exportPurchases,
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload),
                        label: const Text('Import CSV'),
                        onPressed: _importPurchases,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: chartSpots.isEmpty
                  ? const Center(child: Text('No data for chart.'))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY:
                              chartSpots
                                  .map((e) => e.y)
                                  .reduce((a, b) => a > b ? a : b) *
                              1.2,
                          minX: 0,
                          maxX: chartSpots.length - 1,
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                getTitlesWidget: (value, _) {
                                  int i = value.toInt();
                                  if (i < _purchases.length) {
                                    return Text(
                                      DateFormat.Md().format(
                                        _purchases[i].date,
                                      ),
                                      style: const TextStyle(fontSize: 10),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: chartSpots,
                              isCurved: true,
                              color: Colors.amber,
                              dotData: FlDotData(show: false),
                              barWidth: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _purchases.length,
              itemBuilder: (context, index) {
                final p = _purchases[index];
                final profit = p.profitLoss(_latestPrices);
                return Card(
                  child: ListTile(
                    title: Text(
                      '${p.metal} - ${p.quantity} oz @ \$${p.purchasePrice.toStringAsFixed(2)}',
                    ),
                    subtitle: Text(
                      'Date: ${DateFormat.yMd().format(p.date)}\nCurrent: \$${p.currentValue(_latestPrices).toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '${profit >= 0 ? '+' : '-'}\$${profit.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        color: profit >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Total P/L: \$${_totalProfitLoss.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _totalProfitLoss >= 0 ? Colors.green : Colors.redAccent,
              ),
            ),
            if (_isBannerAdReady)
              SizedBox(
                height: _bannerAd.size.height.toDouble(),
                width: _bannerAd.size.width.toDouble(),
                child: AdWidget(ad: _bannerAd),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
