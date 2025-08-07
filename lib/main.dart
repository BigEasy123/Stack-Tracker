import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const GoldTrackerApp());
}

class Purchase {
  final String metal;
  double quantity;
  final double purchasePrice;
  final DateTime date;

  Purchase({
    required this.metal,
    required this.quantity,
    required this.purchasePrice,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'metal': metal,
    'quantity': quantity,
    'purchasePrice': purchasePrice,
    'date': date.toIso8601String(),
  };

  static Purchase fromJson(Map<String, dynamic> json) => Purchase(
    metal: json['metal'],
    quantity: (json['quantity'] as num).toDouble(),
    purchasePrice: (json['purchasePrice'] as num).toDouble(),
    date: DateTime.parse(json['date']),
  );

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

class PurchaseStack {
  final String name;
  final List<Purchase> purchases;
  double realizedProfitLoss;

  PurchaseStack({
    required this.name,
    List<Purchase>? purchases,
    this.realizedProfitLoss = 0.0,
  }) : purchases = purchases ?? [];

  Map<String, dynamic> toJson() => {
    'name': name,
    'purchases': purchases.map((p) => p.toJson()).toList(),
    'realizedProfitLoss': realizedProfitLoss,
  };

  static PurchaseStack fromJson(Map<String, dynamic> json) => PurchaseStack(
    name: json['name'],
    purchases: (json['purchases'] as List)
        .map((e) => Purchase.fromJson(e))
        .toList(),
    realizedProfitLoss: json.containsKey('realizedProfitLoss')
        ? (json['realizedProfitLoss'] as num).toDouble()
        : 0.0,
  );
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

  List<PurchaseStack> _stacks = [];
  int _activeStackIndex = 0;
  Map<String, double> _latestPrices = {};
  bool _isLoading = true;

  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  String _selectedMetal = 'Gold';

  final _newStackNameController = TextEditingController();

  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;

  PurchaseStack get _activeStack =>
      _activeStackIndex >= 0 && _activeStackIndex < _stacks.length
      ? _stacks[_activeStackIndex]
      : PurchaseStack(name: ''); // fallback

  List<Purchase> get _activePurchases => _activeStack.purchases;

  @override
  void initState() {
    super.initState();
    _fetchPrices();
    _loadStacks();
    Timer.periodic(const Duration(minutes: 15), (_) => _fetchPrices());

    _bannerAd = BannerAd(
      adUnitId:
          'ca-app-pub-9980659109157314/6900972691', // Replace with your own Ad Unit ID
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

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _newStackNameController.dispose();
    _bannerAd.dispose();
    super.dispose();
  }

  Future<void> _saveStacks() async {
    final prefs = await SharedPreferences.getInstance();
    final stackList = _stacks.map((s) => json.encode(s.toJson())).toList();
    await prefs.setStringList('stacks', stackList);
  }

  Future<void> _loadStacks() async {
    final prefs = await SharedPreferences.getInstance();
    final stackList = prefs.getStringList('stacks');
    if (stackList != null && stackList.isNotEmpty) {
      setState(() {
        _stacks = stackList
            .map((e) => PurchaseStack.fromJson(json.decode(e)))
            .toList();
        _activeStackIndex = 0;
      });
    } else {
      setState(() {
        _stacks = [PurchaseStack(name: 'Default Stack')];
        _activeStackIndex = 0;
      });
    }
  }

  Future<void> _fetchPrices() async {
    setState(() => _isLoading = true);
    const String apiBaseUrl = 'https://metal-price-api-wf1l.onrender.com/';
    final url = Uri.parse('$apiBaseUrl/prices/usd');

    try {
      final response = await http.get(url);
      final data = json.decode(response.body);
      if (data['success'] == true) {
        final rates = Map<String, num>.from(data['rates']);
        setState(() {
          _latestPrices = {
            for (var entry in _metalCodes.entries)
              entry.key: (rates[entry.value] ?? 0).toDouble(),
          };
          _isLoading = false;
        });
      } else {
        throw Exception(data['error']['message']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching prices: $e')));
      }
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
      _activeStack.purchases.add(
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

    _saveStacks();
  }

  void _addStack(String stackName) {
    if (stackName.trim().isEmpty) return;
    if (_stacks.any((s) => s.name == stackName)) return;

    setState(() {
      _stacks.add(PurchaseStack(name: stackName, purchases: []));
      _activeStackIndex = _stacks.length - 1;
      _newStackNameController.clear();
    });

    _saveStacks();
  }

  void _deleteStack(int index) {
    if (index < 0 || index >= _stacks.length) return;

    setState(() {
      _stacks.removeAt(index);
      if (_activeStackIndex >= _stacks.length) {
        _activeStackIndex = _stacks.isEmpty ? -1 : _stacks.length - 1;
      }
    });

    _saveStacks();
  }

  double get _totalProfitLoss {
    if (_activeStackIndex < 0 || _activeStackIndex >= _stacks.length)
      return 0.0;
    return _activeStack.purchases.fold(
      0,
      (sum, p) => sum + p.profitLoss(_latestPrices),
    );
  }

  List<FlSpot> _generateChartSpots() {
    final purchases = _activePurchases;
    if (purchases.isEmpty) return [];

    purchases.sort((a, b) => a.date.compareTo(b.date));
    double cumulative = 0;
    List<FlSpot> spots = [];
    for (int i = 0; i < purchases.length; i++) {
      cumulative += purchases[i].investedValue();
      spots.add(FlSpot(i.toDouble(), cumulative));
    }
    return spots;
  }

  Future<void> _exportPurchases() async {
    if (_activeStackIndex < 0 || _activeStackIndex >= _stacks.length) return;

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/purchases.csv';
    final file = File(path);

    final buffer = StringBuffer();
    buffer.writeln('Metal,Quantity,PurchasePrice,Date');
    for (final p in _activePurchases) {
      buffer.writeln(
        '${p.metal},${p.quantity},${p.purchasePrice},${p.date.toIso8601String()}',
      );
    }

    await file.writeAsString(buffer.toString());

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported to: $path')));
    }
  }

  Future<void> _importPurchases() async {
    if (_activeStackIndex < 0 || _activeStackIndex >= _stacks.length) return;

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
        _activeStack.purchases.addAll(newPurchases);
      });

      _saveStacks();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Purchases imported!')));
      }
    }
  }

  void _deletePurchase(int index) {
    setState(() {
      _activeStack.purchases.removeAt(index);
    });
    _saveStacks();
  }

  void _sellPurchase(int index) {
    final purchase = _activePurchases[index];
    final quantityController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sell Purchase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Selling from: ${purchase.metal} - ${purchase.quantity.toStringAsFixed(4)} oz @ \$${purchase.purchasePrice.toStringAsFixed(2)}',
              ),
              TextField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantity to Sell',
                ),
              ),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Sell Price per oz',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final sellQty = double.tryParse(quantityController.text);
                final sellPrice = double.tryParse(priceController.text);
                if (sellQty == null || sellPrice == null || sellQty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter valid sell quantity and price'),
                    ),
                  );
                  return;
                }
                if (sellQty > purchase.quantity) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cannot sell more than purchase quantity'),
                    ),
                  );
                  return;
                }

                setState(() {
                  final realizedPL =
                      (sellPrice - purchase.purchasePrice) * sellQty;
                  _activeStack.realizedProfitLoss += realizedPL;

                  purchase.quantity -= sellQty;
                  if (purchase.quantity <= 0) {
                    _activeStack.purchases.removeAt(index);
                  }
                });

                _saveStacks();
                Navigator.pop(context);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chartSpots = _generateChartSpots();

    return Scaffold(
      appBar: AppBar(title: const Text('Stack Tracker v1.0.0')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
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

            Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value:
                        _activeStackIndex >= 0 &&
                            _activeStackIndex < _stacks.length
                        ? _activeStackIndex
                        : null,
                    hint: const Text('Select Stack'),
                    items: List.generate(_stacks.length, (index) {
                      return DropdownMenuItem(
                        value: index,
                        child: Text(_stacks[index].name),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _activeStackIndex = val);
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete Current Stack',
                  onPressed: _activeStackIndex >= 0 && _stacks.length > 1
                      ? () {
                          _deleteStack(_activeStackIndex);
                        }
                      : null,
                ),
              ],
            ),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newStackNameController,
                    decoration: const InputDecoration(
                      labelText: 'New Stack Name',
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    _addStack(_newStackNameController.text);
                  },
                  child: const Text('Add Stack'),
                ),
              ],
            ),

            const SizedBox(height: 12),

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
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedMetal = val);
                      }
                    },
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
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 ||
                                      idx >= _activePurchases.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final dt = _activePurchases[idx].date;
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    child: Text(
                                      DateFormat.Md().format(dt),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 50,
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: chartSpots,
                              isCurved: false,
                              color: Colors.amber,
                              barWidth: 3,
                              dotData: FlDotData(show: true),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 12),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activePurchases.length,
              itemBuilder: (context, index) {
                final p = _activePurchases[index];
                final profit = p.profitLoss(_latestPrices);
                return Card(
                  child: ListTile(
                    title: Text(
                      '${p.metal} - ${p.quantity.toStringAsFixed(4)} oz @ \$${p.purchasePrice.toStringAsFixed(2)}',
                    ),
                    subtitle: Text(
                      'Date: ${DateFormat.yMd().format(p.date)}\nCurrent: \$${p.currentValue(_latestPrices).toStringAsFixed(2)}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        Text(
                          '${profit >= 0 ? '+' : '-'}\$${profit.abs().toStringAsFixed(2)}',
                          style: TextStyle(
                            color: profit >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.sell, color: Colors.blue),
                          tooltip: 'Sell',
                          onPressed: () => _sellPurchase(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Delete Purchase',
                          onPressed: () => _deletePurchase(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 10),

            Text(
              'Unrealized P/L: \$${_totalProfitLoss.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _totalProfitLoss >= 0 ? Colors.green : Colors.redAccent,
              ),
            ),

            Text(
              'Realized P/L: \$${_activeStack.realizedProfitLoss.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _activeStack.realizedProfitLoss >= 0
                    ? Colors.green
                    : Colors.redAccent,
              ),
            ),

            if (_isBannerAdReady)
              SizedBox(
                height: _bannerAd.size.height.toDouble(),
                width: _bannerAd.size.width.toDouble(),
                child: AdWidget(ad: _bannerAd),
              ),
          ],
        ),
      ),
    );
  }
}
