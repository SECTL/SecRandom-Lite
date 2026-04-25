import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../models/prize_pool.dart';
import '../../models/prize.dart';
import '../../providers/app_provider.dart';
import '../../services/lottery_service.dart';
import '../../widgets/responsive_grid.dart';

enum _EntryAction { edit, delete }

class LotterySettingsScreen extends StatefulWidget {
  const LotterySettingsScreen({super.key});

  @override
  State<LotterySettingsScreen> createState() => _LotterySettingsScreenState();
}

class _LotterySettingsScreenState extends State<LotterySettingsScreen> {
  final LotteryService _lotteryService = LotteryService();
  List<PrizePool> _prizePools = [];
  Map<String, List<Prize>> _poolPrizes = {};
  bool _isLoading = true;
  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _loadPrizePools();
  }

  Future<void> _loadPrizePools() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final pools = await _lotteryService.loadPrizePools();
      final Map<String, List<Prize>> prizesMap = {};

      for (var pool in pools) {
        final prizes = await _lotteryService.loadPrizes(pool.name);
        prizesMap[pool.name] = prizes;
      }

      if (mounted) {
        setState(() {
          _prizePools = pools;
          _poolPrizes = prizesMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addPrizePool() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建奖池'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '奖池名称',
            hintText: '请输入奖池名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final newPool = PrizePool(name: result);
      try {
        await _lotteryService.savePrizePool(newPool);
        await _loadPrizePools();
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PrizePoolSettingsScreen(pool: newPool),
            ),
          ).then((_) {
            if (mounted) _loadPrizePools();
          });
        }
      } catch (e) {}
    }
  }

  Future<void> _editPrizePool(PrizePool pool) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PrizePoolSettingsScreen(pool: pool),
      ),
    );
    if (mounted) _loadPrizePools();
  }

  Future<void> _renamePrizePool(PrizePool pool) async {
    final nameController = TextEditingController(text: pool.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑奖池'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '奖池名称',
            hintText: '请输入奖池名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == pool.name) return;
    if (_prizePools.any((p) => p.name == result)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('奖池已存在')));
      return;
    }

    try {
      final prizes = await _lotteryService.loadPrizes(pool.name);
      final renamedPool = pool.copyWith(name: result);
      await _lotteryService.savePrizePool(renamedPool);
      await _lotteryService.savePrizes(result, prizes);
      await _lotteryService.deletePrizePool(pool.name);
      await _loadPrizePools();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('编辑奖池失败')));
    }
  }

  Future<void> _deletePrizePool(PrizePool pool) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除奖池"${pool.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _lotteryService.deletePrizePool(pool.name);
        await _loadPrizePools();
      } catch (e) {}
    }
  }

  Future<void> _handlePoolAction(PrizePool pool, _EntryAction action) async {
    switch (action) {
      case _EntryAction.edit:
        await _renamePrizePool(pool);
        break;
      case _EntryAction.delete:
        await _deletePrizePool(pool);
        break;
    }
  }

  Future<void> _showPoolActionMenuAtPosition(
    PrizePool pool,
    Offset globalPosition,
  ) async {
    final action = await showMenu<_EntryAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem<_EntryAction>(
          value: _EntryAction.edit,
          child: Text('编辑'),
        ),
        PopupMenuItem<_EntryAction>(
          value: _EntryAction.delete,
          child: Text('删除'),
        ),
      ],
    );

    if (action == null || !mounted) return;
    await _handlePoolAction(pool, action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('抽奖设置')),
      body: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
          return Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _prizePools.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.card_giftcard_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '暂无奖池',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击右下角 + 按钮创建新奖池',
                              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : ResponsiveGrid(
                        padding: const EdgeInsets.all(16),
                        children: _prizePools.map((pool) {
                          final prizes = _poolPrizes[pool.name] ?? [];
                          final prizeCount = prizes.where((p) => p.exist).length;
                          final totalCount = _lotteryService.getPrizeTotalCount(
                            pool,
                            prizes,
                          );

                          return Card(
                            child: GestureDetector(
                              onLongPressStart: _isMobilePlatform
                                  ? (details) async {
                                      await _showPoolActionMenuAtPosition(
                                        pool,
                                        details.globalPosition,
                                      );
                                    }
                                  : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    pool.name[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  pool.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('奖品数量: $prizeCount | 总数: $totalCount'),
                                trailing: _isMobilePlatform
                                    ? null
                                    : PopupMenuButton<_EntryAction>(
                                        tooltip: '更多',
                                        onSelected: (action) =>
                                            _handlePoolAction(pool, action),
                                        itemBuilder: (context) => const [
                                          PopupMenuItem<_EntryAction>(
                                            value: _EntryAction.edit,
                                            child: Text('编辑'),
                                          ),
                                          PopupMenuItem<_EntryAction>(
                                            value: _EntryAction.delete,
                                            child: Text('删除'),
                                          ),
                                        ],
                                        icon: const Icon(Icons.more_vert),
                                      ),
                                onTap: () => _editPrizePool(pool),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPrizePool,
        tooltip: '新建奖池',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class PrizePoolSettingsScreen extends StatefulWidget {
  final PrizePool pool;

  const PrizePoolSettingsScreen({super.key, required this.pool});

  @override
  State<PrizePoolSettingsScreen> createState() =>
      _PrizePoolSettingsScreenState();
}

class _PrizePoolSettingsScreenState extends State<PrizePoolSettingsScreen> {
  final LotteryService _lotteryService = LotteryService();
  late PrizePool _pool;
  List<Prize> _prizes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pool = widget.pool;
    _loadPrizes();
  }

  Future<void> _loadPrizes() async {
    try {
      final prizes = await _lotteryService.loadPrizes(_pool.name);
      if (mounted) {
        setState(() {
          _prizes = prizes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePool() async {
    if (!mounted) return;

    try {
      await _lotteryService.savePrizePool(_pool);
      await _lotteryService.savePrizes(_pool.name, _prizes);
    } catch (e) {}
  }

  Future<void> _addPrize() async {
    final nameController = TextEditingController();
    final weightController = TextEditingController(text: '1.0');
    final countController = TextEditingController(text: '1');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加奖品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '奖品名称',
                hintText: '请输入奖品名称',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightController,
              decoration: const InputDecoration(
                labelText: '权重',
                hintText: '权重越大，中奖概率越高',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countController,
              decoration: const InputDecoration(
                labelText: '数量',
                hintText: '奖品数量',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final weight = double.tryParse(weightController.text) ?? 1.0;
              final count = int.tryParse(countController.text) ?? 1;
              if (name.isNotEmpty) {
                Navigator.pop(context, {
                  'name': name,
                  'weight': weight,
                  'count': count,
                });
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      final newPrize = Prize(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result['name'],
        weight: result['weight'],
        count: result['count'],
      );
      setState(() {
        _prizes.add(newPrize);
      });
      await _savePool();
    }
  }

  Future<void> _openQuickImport() async {
    final result = await Navigator.push<List<Prize>>(
      context,
      MaterialPageRoute(
        builder: (context) => PrizeImportScreen(poolName: _pool.name),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      _prizes.addAll(result);
    });
    await _savePool();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('成功导入 ${result.length} 个奖品')));
  }

  Future<void> _editPrize(Prize prize) async {
    final nameController = TextEditingController(text: prize.name);
    final weightController = TextEditingController(
      text: prize.weight.toString(),
    );
    final countController = TextEditingController(text: prize.count.toString());

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑奖品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '奖品名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightController,
              decoration: const InputDecoration(labelText: '权重'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countController,
              decoration: const InputDecoration(labelText: '数量'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final weight = double.tryParse(weightController.text) ?? 1.0;
              final count = int.tryParse(countController.text) ?? 1;
              if (name.isNotEmpty) {
                Navigator.pop(context, {
                  'name': name,
                  'weight': weight,
                  'count': count,
                });
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {
        final index = _prizes.indexWhere((p) => p.id == prize.id);
        if (index >= 0) {
          _prizes[index] = prize.copyWith(
            name: result['name'],
            weight: result['weight'],
            count: result['count'],
          );
        }
      });
      await _savePool();
    }
  }

  Future<void> _deletePrize(Prize prize) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除奖品"${prize.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _prizes.removeWhere((p) => p.id == prize.id);
      });
      await _savePool();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_pool.name)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _prizes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.card_giftcard_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无奖品',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右下角 + 按钮添加奖品',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ResponsiveGrid(
              children: _prizes.map((prize) {
                return Card(
                  child: ListTile(
                    title: Text(
                      prize.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: prize.exist
                            ? null
                            : TextDecoration.lineThrough,
                        color: prize.exist ? null : Colors.grey,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Checkbox(
                          value: prize.exist,
                          visualDensity: VisualDensity.compact,
                          onChanged: (value) {
                            if (value != null && mounted) {
                              setState(() {
                                final index = _prizes.indexWhere((p) => p.id == prize.id);
                                if (index >= 0) {
                                  _prizes[index] = prize.copyWith(exist: value);
                                }
                              });
                              _savePool();
                            }
                          },
                        ),
                        Expanded(
                          child: Text(
                            '权重: ${prize.weight} | 数量: ${prize.count}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: prize.exist ? null : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: SizedBox(
                      width: 96,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editPrize(prize),
                            tooltip: '编辑',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deletePrize(prize),
                            tooltip: '删除',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _openQuickImport,
            tooltip: '快速导入',
            heroTag: 'quick-import-${_pool.name}',
            child: const Icon(Icons.upload_file),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: _addPrize,
            tooltip: '添加奖品',
            heroTag: 'add_prize_${_pool.name}',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class ParsedPrizeData {
  final String name;
  final String weightText;
  final String countText;
  final bool isValid;
  final double? parsedWeight;
  final int? parsedCount;

  const ParsedPrizeData({
    required this.name,
    required this.weightText,
    required this.countText,
    required this.isValid,
    required this.parsedWeight,
    required this.parsedCount,
  });
}

class PrizeImportScreen extends StatefulWidget {
  final String poolName;

  const PrizeImportScreen({super.key, required this.poolName});

  @override
  State<PrizeImportScreen> createState() => _PrizeImportScreenState();
}

class _PrizeImportScreenState extends State<PrizeImportScreen> {
  final _namesController = TextEditingController();
  final _weightsController = TextEditingController();
  final _countsController = TextEditingController();

  List<ParsedPrizeData> _parsedData = [];
  bool _showPreview = false;
  bool _isImporting = false;
  double _importProgress = 0.0;
  int _importedCount = 0;
  int _totalCount = 0;

  @override
  void dispose() {
    _namesController.dispose();
    _weightsController.dispose();
    _countsController.dispose();
    super.dispose();
  }

  List<String> _parseLines(String text) {
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  void _parseData() {
    final names = _parseLines(_namesController.text);
    final weights = _parseLines(_weightsController.text);
    final counts = _parseLines(_countsController.text);

    _parsedData = [];

    for (int i = 0; i < names.length; i++) {
      final name = names[i].trim();
      final weightText = i < weights.length ? weights[i].trim() : '';
      final countText = i < counts.length ? counts[i].trim() : '';
      final parsedWeight = weightText.isEmpty ? 1.0 : double.tryParse(weightText);
      final parsedCount = countText.isEmpty ? 1 : int.tryParse(countText);
      final isWeightValid = parsedWeight != null && parsedWeight > 0;
      final isCountValid = parsedCount != null && parsedCount > 0;

      _parsedData.add(
        ParsedPrizeData(
          name: name,
          weightText: weightText,
          countText: countText,
          isValid: name.isNotEmpty && isWeightValid && isCountValid,
          parsedWeight: parsedWeight,
          parsedCount: parsedCount,
        ),
      );
    }

    setState(() {
      _showPreview = true;
    });
  }

  Future<void> _importPrizes() async {
    if (_parsedData.isEmpty) return;

    final validData = _parsedData.where((d) => d.isValid).toList();
    final invalidCount = _parsedData.length - validData.length;
    if (validData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有有效的奖品数据可导入')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
      _importedCount = 0;
      _totalCount = validData.length;
    });

    final importedPrizes = <Prize>[];
    var successCount = 0;
    var failCount = invalidCount;
    const chunkSize = 200;

    for (int i = 0; i < validData.length; i++) {
      final item = validData[i];
      try {
        importedPrizes.add(
          Prize(
            id: '${DateTime.now().microsecondsSinceEpoch}_$i',
            name: item.name,
            weight: item.parsedWeight!,
            count: item.parsedCount!,
          ),
        );
        successCount++;
      } catch (_) {
        failCount++;
      }

      if ((i + 1) % chunkSize == 0 || i == validData.length - 1) {
        await Future<void>.delayed(Duration.zero);
      }

      if (!mounted) return;
      setState(() {
        _importedCount = i + 1;
        _totalCount = validData.length;
        _importProgress = (i + 1) / validData.length;
      });
    }

    if (!mounted) return;
    setState(() {
      _isImporting = false;
    });

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text('成功导入: $successCount 个奖品'),
              ],
            ),
            if (failCount > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Text('导入失败: $failCount 条记录'),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(importedPrizes);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快速导入奖品'),
        actions: [
          if (_showPreview && !_isImporting)
            TextButton.icon(
              onPressed: _importPrizes,
              icon: const Icon(Icons.upload, color: Colors.white),
              label: const Text('确认导入', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _isImporting
          ? _buildImportingView()
          : _showPreview
          ? _buildPreviewView()
          : _buildInputView(),
      bottomNavigationBar: !_showPreview || _isImporting
          ? null
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _showPreview = false;
                        });
                      },
                      child: const Text('返回修改'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _importPrizes,
                      child: const Text('确认导入'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInputView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '导入说明',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• 每行输入一个奖品的信息\n'
                    '• 奖品名称为必填项，权重和数量可留空\n'
                    '• 权重默认值为 1，需为大于 0 的数字\n'
                    '• 数量默认值为 1，需为大于 0 的整数\n'
                    '• 三个输入框的行数需一一对应\n'
                    '• 建议从 WPS Office 或 Excel 直接复制完整表格列',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            '奖品名称（必填）',
            _namesController,
            '一等奖\n二等奖\n三等奖',
            Icons.card_giftcard,
            true,
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            '权重（可选）',
            _weightsController,
            '10\n5\n1',
            Icons.balance,
            false,
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            '数量（可选）',
            _countsController,
            '1\n2\n5',
            Icons.format_list_numbered,
            false,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_namesController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请至少输入一个奖品名称')),
                  );
                  return;
                }
                _parseData();
              },
              icon: const Icon(Icons.preview),
              label: const Text('预览数据'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(
    String label,
    TextEditingController controller,
    String hint,
    IconData icon,
    bool isRequired,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (isRequired)
                  Text(
                    ' *',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                const Spacer(),
                Text(
                  '${_parseLines(controller.text).length} 行',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    final validCount = _parsedData.where((d) => d.isValid).length;
    final invalidCount = _parsedData.length - validCount;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('总行数', _parsedData.length, Icons.list),
              _buildStatItem('有效数据', validCount, Icons.check_circle, Colors.green),
              if (invalidCount > 0)
                _buildStatItem('无效数据', invalidCount, Icons.error, Colors.red),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _parsedData.length,
            itemBuilder: (context, index) {
              final data = _parsedData[index];
              final displayWeight = data.parsedWeight?.toString() ?? data.weightText;
              final displayCount = data.parsedCount?.toString() ?? data.countText;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: data.isValid
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    data.name.isEmpty ? '(空奖品名称)' : data.name,
                    style: TextStyle(
                      color: data.isValid ? null : Colors.grey,
                      decoration: data.isValid ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  subtitle: Text(
                    '权重: ${displayWeight.isEmpty ? "1" : displayWeight} | 数量: ${displayCount.isEmpty ? "1" : displayCount}',
                  ),
                  trailing: Icon(
                    data.isValid ? Icons.check_circle : Icons.cancel,
                    color: data.isValid ? Colors.green : Colors.red,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon, [Color? color]) {
    return Column(
      children: [
        Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildImportingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            '正在导入奖品数据...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              children: [
                LinearProgressIndicator(value: _importProgress),
                const SizedBox(height: 8),
                Text(
                  '$_importedCount / $_totalCount',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
