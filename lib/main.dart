import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const VaultLedgerApp());
}

class VaultLedgerApp extends StatelessWidget {
  const VaultLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vault Ledger Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E293B)),
        useMaterial3: true,
      ),
      home: const SavingsHomePage(),
    );
  }
}

class SavingsHomePage extends StatefulWidget {
  const SavingsHomePage({super.key});

  @override
  State<SavingsHomePage> createState() => _SavingsHomePageState();
}

class _SavingsHomePageState extends State<SavingsHomePage> {
  static const storageKey = 'vaultV4';

  final List<Unit> units = [];
  final List<LedgerLog> logs = [];
  double unsortedBalance = 0;
  int selectedPageIndex = 0;
  bool isLoading = true;

  double get allocatedPercent => units.fold(0, (sum, unit) => sum + unit.percent);
  double get remainingPercent => (100 - allocatedPercent).clamp(0.0, 100.0);
  bool get hasUnsorted => remainingPercent > 0 || unsortedBalance > 0;
  double get totalBalance => units.fold(unsortedBalance, (sum, unit) => sum + unit.balance);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(storageKey);
    if (stored != null) {
      final decoded = jsonDecode(stored) as Map<String, dynamic>;
      final storedUnits = (decoded['units'] as List<dynamic>?) ?? [];
      final storedLogs = (decoded['logs'] as List<dynamic>?) ?? [];
      final storedUnsorted = (decoded['unsortedBalance'] as num?)?.toDouble() ?? 0.0;

      units
        ..clear()
        ..addAll(storedUnits.map((item) => Unit.fromJson(item as Map<String, dynamic>)));
      logs
        ..clear()
        ..addAll(storedLogs.map((item) => LedgerLog.fromJson(item as Map<String, dynamic>)));
      unsortedBalance = storedUnsorted;
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'units': units.map((u) => u.toJson()).toList(),
      'logs': logs.map((l) => l.toJson()).toList(),
      'unsortedBalance': unsortedBalance,
    });
    await prefs.setString(storageKey, payload);
  }

  Future<void> _showIncomeDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Input Income'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Total Amount (\u0024)'),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                final amount = double.parse(controller.text);
                _processIncome(amount);
                Navigator.pop(context);
              },
              child: const Text('Split & Store'),
            ),
          ],
        );
      },
    );
  }

  void _processIncome(double amount) {
    setState(() {
      final allocations = <String, double>{};
      for (final unit in units) {
        final allocated = amount * (unit.percent / 100);
        unit.balance += allocated;
        allocations[unit.name] = allocated;
      }
      if (remainingPercent > 0) {
        unsortedBalance += amount * (remainingPercent / 100);
      }
      logs.add(LedgerLog(
        type: LedgerType.income,
        amount: amount,
        timestamp: DateTime.now(),
        unallocatedAmount: remainingPercent > 0 ? amount * (remainingPercent / 100) : 0,
        unitAllocations: allocations,
      ));
    });
    _saveData();
  }

  Future<void> _showExpenseDialog(int index) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isUnsorted = index == -1;
    final balance = isUnsorted ? unsortedBalance : units[index].balance;
    final title = isUnsorted ? 'Expense from Unsorted' : 'Expense from ${units[index].name}';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Amount (\u0024)'),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter a valid amount';
                }
                if (amount > balance) {
                  return 'Insufficient funds';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                final amount = double.parse(controller.text);
                _recordExpense(index, amount);
                Navigator.pop(context);
              },
              child: const Text('Log Expense'),
            ),
          ],
        );
      },
    );
  }

  void _recordExpense(int index, double amount) {
    final isUnsorted = index == -1;
    setState(() {
      if (isUnsorted) {
        unsortedBalance = (unsortedBalance - amount).clamp(0.0, double.infinity);
      } else {
        units[index].balance = (units[index].balance - amount).clamp(0.0, double.infinity);
      }
      logs.add(LedgerLog(
        type: LedgerType.expense,
        amount: amount,
        unit: isUnsorted ? 'Unsorted' : units[index].name,
        timestamp: DateTime.now(),
      ));
    });
    _saveData();
  }

  Future<void> _showUnitIncomeDialog(int index) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final unit = units[index];

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Deposit to ${unit.name}'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Amount (\u0024)'),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                final amount = double.parse(controller.text);
                _recordUnitIncome(index, amount);
                Navigator.pop(context);
              },
              child: const Text('Deposit'),
            ),
          ],
        );
      },
    );
  }

  void _recordUnitIncome(int index, double amount) {
    final unit = units[index];
    setState(() {
      unit.balance += amount;
      logs.add(LedgerLog(
        type: LedgerType.income,
        amount: amount,
        unit: unit.name,
        timestamp: DateTime.now(),
        unallocatedAmount: 0,
      ));
    });
    _saveData();
  }

  Future<void> _showUnitDialog({int? index, bool reopenParent = false}) async {
    final nameController = TextEditingController();
    final percentController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isEdit = false;

    if (index != null) {
      final unit = units[index];
      nameController.text = unit.name;
      percentController.text = unit.percent.toStringAsFixed(0);
      isEdit = true;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        final otherTotal = units.asMap().entries
            .where((entry) => entry.key != index)
            .fold(0.0, (sum, entry) => sum + entry.value.percent);
        final remaining = (100 - otherTotal).clamp(0.0, 100.0);

        return AlertDialog(
          title: Text(isEdit ? 'Unit Settings' : 'New Storage Unit'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(hintText: 'Name'),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Enter a name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: percentController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: 'Allocation %'),
                    validator: (value) {
                      final percent = double.tryParse(value ?? '');
                      if (percent == null || percent <= 0 || percent > 100) {
                        return 'Enter a percent between 1 and 100';
                      }
                      if (otherTotal + percent > 100) {
                        return 'Total allocation exceeds 100%. Edit existing units or lower this value.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current allocation: ${otherTotal.toStringAsFixed(0)}%. Remaining: ${remaining.toStringAsFixed(0)}%.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  if (units.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text('Edit existing unit allocations', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...units.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final unit = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text('${unit.name} (${unit.percent.toStringAsFixed(0)}%)')),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Future.microtask(() => _showUnitDialog(index: idx, reopenParent: !isEdit));
                              },
                              child: const Text('Edit'),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (remaining <= 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'No remaining allocation available. Edit an existing unit to free up percent.',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (isEdit)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteUnit(index!);
                },
                child: const Text('Delete Unit', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                final name = nameController.text.trim();
                final percent = double.parse(percentController.text);
                if (isEdit) {
                  _editUnit(index!, name, percent);
                } else {
                  _addUnit(name, percent);
                }
                Navigator.pop(context);
              },
              child: Text(isEdit ? 'Save' : 'Create'),
            ),
          ],
        );
      },
    );

    if (reopenParent) {
      await Future<void>.delayed(Duration.zero);
      _showUnitDialog();
    }
  }

  void _addUnit(String name, double percent) {
    setState(() {
      units.add(Unit(name: name, percent: percent, balance: 0));
    });
    _saveData();
  }

  void _editUnit(int index, String name, double percent) {
    setState(() {
      units[index].name = name;
      units[index].percent = percent;
    });
    _saveData();
  }

  void _deleteUnit(int index) {
    setState(() {
      unsortedBalance += units[index].balance;
      units.removeAt(index);
    });
    _saveData();
  }

  Future<void> _confirmDeleteLog(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Transaction?'),
          content: const Text('Delete and reverse this transaction?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _deleteLog(index);
    }
  }

  void _deleteLog(int index) {
    final log = logs[index];
    setState(() {
      if (log.type == LedgerType.income) {
        if (log.unit != null) {
          final unit = units.firstWhere(
            (u) => u.name == log.unit,
            orElse: () => Unit(name: 'Unknown', percent: 0, balance: 0),
          );
          unit.balance -= log.amount;
        } else {
          if (log.unitAllocations != null) {
            for (final entry in log.unitAllocations!.entries) {
              final unit = units.firstWhere(
                (u) => u.name == entry.key,
                orElse: () => Unit(name: 'Unknown', percent: 0, balance: 0),
              );
              if (unit.name != 'Unknown') {
                unit.balance -= entry.value;
              }
            }
          } else {
            for (final unit in units) {
              unit.balance -= log.amount * (unit.percent / 100);
            }
          }
          unsortedBalance -= log.unallocatedAmount;
        }
      } else {
        if (log.unit == 'Unsorted') {
          unsortedBalance += log.amount;
        } else {
          final unit = units.firstWhere(
            (u) => u.name == log.unit,
            orElse: () => Unit(name: 'Unknown', percent: 0, balance: 0),
          );
          unit.balance += log.amount;
        }
      }
      logs.removeAt(index);
    });
    _saveData();
  }

  Future<void> _editLog(int index) async {
    final log = logs[index];
    final controller = TextEditingController(text: log.amount.toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Amount'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'New amount'),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount < 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                final updatedAmount = double.parse(controller.text);
                _applyLogEdit(index, updatedAmount);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _applyLogEdit(int index, double updatedAmount) {
    final log = logs[index];
    final diff = updatedAmount - log.amount;
    setState(() {
      if (log.type == LedgerType.income) {
        if (log.unit != null) {
          final unit = units.firstWhere(
            (u) => u.name == log.unit,
            orElse: () => Unit(name: '', percent: 0, balance: 0),
          );
          if (unit.name.isNotEmpty) {
            unit.balance = (unit.balance + diff).clamp(0.0, double.infinity);
          }
        } else {
          if (log.unitAllocations != null) {
            final scale = log.amount > 0 ? updatedAmount / log.amount : 0;
            final newAllocations = <String, double>{};
            for (final entry in log.unitAllocations!.entries) {
              final newAlloc = entry.value * scale;
              newAllocations[entry.key] = newAlloc;
              final unit = units.firstWhere(
                (u) => u.name == entry.key,
                orElse: () => Unit(name: '', percent: 0, balance: 0),
              );
              if (unit.name.isNotEmpty) {
                unit.balance = (unit.balance - entry.value + newAlloc).clamp(0.0, double.infinity);
              }
            }
            final newUnallocated = log.unallocatedAmount * scale;
            unsortedBalance = (unsortedBalance - log.unallocatedAmount + newUnallocated).clamp(0.0, double.infinity);
            log.unitAllocations = newAllocations;
            log.unallocatedAmount = newUnallocated;
          } else {
            for (final unit in units) {
              unit.balance = (unit.balance + diff * (unit.percent / 100)).clamp(0.0, double.infinity);
            }
            final ratio = log.amount > 0 ? log.unallocatedAmount / log.amount : 0;
            final unallocatedDiff = diff * ratio;
            unsortedBalance = (unsortedBalance + unallocatedDiff).clamp(0.0, double.infinity);
            log.unallocatedAmount += unallocatedDiff;
          }
        }
      } else {
        if (log.unit == 'Unsorted') {
          unsortedBalance = (unsortedBalance - diff).clamp(0.0, double.infinity);
        } else {
          final unit = units.firstWhere((u) => u.name == log.unit, orElse: () => Unit(name: '', percent: 0, balance: 0));
          if (unit.name.isNotEmpty) {
            unit.balance = (unit.balance - diff).clamp(0.0, double.infinity);
          }
        }
      }
      log.amount = updatedAmount;
    });
    _saveData();
  }

  void _fullReset() {
    showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Full Factory Reset'),
          content: const Text('This will delete all data permanently.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete Everything'),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          units.clear();
          logs.clear();
        });
        _saveData();
      }
    });
  }

  List<LedgerLog> get _recentLogs => logs.reversed.toList();

  double get monthlyIncome {
    final now = DateTime.now();
    return logs
        .where((log) => log.type == LedgerType.income && _isSameMonth(log.timestamp, now))
        .fold(0.0, (sum, log) => sum + log.amount);
  }

  double get monthlyExpenses {
    final now = DateTime.now();
    return logs
        .where((log) => log.type == LedgerType.expense && _isSameMonth(log.timestamp, now))
        .fold(0.0, (sum, log) => sum + log.amount);
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault Ledger Pro'),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildPageTabs(),
                  const SizedBox(height: 16),
                  Expanded(child: selectedPageIndex == 0 ? _buildDashboard() : _buildHistoryPage()),
                ],
              ),
            ),
      floatingActionButton: selectedPageIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _showIncomeDialog,
              label: const Text('Deposit Income'),
              icon: const Icon(Icons.attach_money),
            )
          : null,
    );
  }

  Widget _buildPageTabs() {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: selectedPageIndex == 0 ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () => setState(() => selectedPageIndex = 0),
            child: const Text('Dashboard'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: selectedPageIndex == 1 ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () => setState(() => selectedPageIndex = 1),
            child: const Text('History & Report'),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildBalanceCard(),
          const SizedBox(height: 16),
          if (units.isEmpty)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: const [
                    Text('No storage units yet.'),
                    SizedBox(height: 8),
                    Text('Add a unit to begin allocating income.'),
                  ],
                ),
              ),
            ),
          ...units.asMap().entries.map((entry) => _buildUnitCard(entry.key, entry.value)),
          if (hasUnsorted) _buildUnsortedCard(),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _showUnitDialog(),
            child: const Text('+ New Storage Unit'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Current Total Balance', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              '\u0024${totalBalance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _showIncomeDialog,
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
              child: const Text('Deposit Income'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsortedCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Unsorted${remainingPercent > 0 ? ' (${remainingPercent.toStringAsFixed(0)}%)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('\u0024${unsortedBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: unsortedBalance > 0 ? () => _showExpenseDialog(-1) : null,
                    child: const Text('Log Expense'),
                  ),
                ),
                const SizedBox(width: 12),
                const SizedBox(width: 72),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitCard(int index, Unit unit) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${unit.name} (${unit.percent.toStringAsFixed(0)}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('\u0024${unit.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _showUnitIncomeDialog(index),
                    child: const Text('Add Income'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showExpenseDialog(index),
                    child: const Text('Log Expense'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _showUnitDialog(index: index),
                  child: const Text('Edit Unit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Monthly Report (This Month)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildReportBox('Income', monthlyIncome, true)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildReportBox('Expenses', monthlyExpenses, false)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_recentLogs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No transactions recorded yet.', textAlign: TextAlign.center),
                    )
                  else
                    ..._recentLogs.asMap().entries.map((entry) => _buildLogItem(entry.key, entry.value)),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade100, foregroundColor: Colors.red.shade900),
                    onPressed: _fullReset,
                    child: const Text('Full Factory Reset'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportBox(String label, double amount, bool isPositive) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Text(
            '\u0024${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isPositive ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(int index, LedgerLog log) {
    final date = log.timestamp;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.type == LedgerType.income
                        ? (log.unit != null ? 'Income to ${log.unit}' : 'Income Split')
                        : log.unit ?? 'Expense',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${date.month}/${date.day}/${date.year}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${log.type == LedgerType.income ? '+' : '-'}\u0024${log.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: log.type == LedgerType.income ? Colors.green : Colors.red,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _editLog(logs.length - 1 - index),
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: () => _confirmDeleteLog(logs.length - 1 - index),
                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class Unit {
  Unit({required this.name, required this.percent, required this.balance});

  String name;
  double percent;
  double balance;

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      name: json['name'] as String,
      percent: (json['percent'] as num).toDouble(),
      balance: (json['balance'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'percent': percent,
      'balance': balance,
    };
  }
}

enum LedgerType { income, expense }

class LedgerLog {
  LedgerLog({
    required this.type,
    required this.amount,
    this.unit,
    required this.timestamp,
    this.unallocatedAmount = 0,
    this.unitAllocations,
  });

  LedgerType type;
  double amount;
  String? unit;
  DateTime timestamp;
  double unallocatedAmount;
  Map<String, double>? unitAllocations;

  factory LedgerLog.fromJson(Map<String, dynamic> json) {
    return LedgerLog(
      type: json['type'] == 'income' ? LedgerType.income : LedgerType.expense,
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      unallocatedAmount: (json['unallocatedAmount'] as num?)?.toDouble() ?? 0,
      unitAllocations: json['unitAllocations'] != null
          ? Map<String, double>.from(json['unitAllocations'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type == LedgerType.income ? 'income' : 'expense',
      'amount': amount,
      'unit': unit,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'unallocatedAmount': unallocatedAmount,
      if (unitAllocations != null) 'unitAllocations': unitAllocations,
    };
  }
}
