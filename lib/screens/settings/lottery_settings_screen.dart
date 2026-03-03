import 'package:flutter/material.dart';
import '../../models/prize_pool.dart';
import '../../models/prize.dart';
import '../../services/lottery_service.dart';

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
      } catch (e) {
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('奖池已存在')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('编辑奖池失败')),
      );
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
      } catch (e) {
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('抽奖设置'),
      ),
      body: _isLoading
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
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击右下角 + 按钮创建新奖池',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _prizePools.length,
                  itemBuilder: (context, index) {
                    final pool = _prizePools[index];
                    final prizes = _poolPrizes[pool.name] ?? [];
                    final prizeCount = prizes.where((p) => p.exist).length;
                    final totalCount = _lotteryService.getPrizeTotalCount(pool, prizes);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
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
                        trailing: SizedBox(
                          width: 96,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _renamePrizePool(pool),
                                tooltip: '编辑',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _deletePrizePool(pool),
                                tooltip: '删除',
                              ),
                            ],
                          ),
                        ),
                        onTap: () => _editPrizePool(pool),
                      ),
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
  State<PrizePoolSettingsScreen> createState() => _PrizePoolSettingsScreenState();
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
    } catch (e) {
    }
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

  Future<void> _editPrize(Prize prize) async {
    final nameController = TextEditingController(text: prize.name);
    final weightController = TextEditingController(text: prize.weight.toString());
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
              decoration: const InputDecoration(
                labelText: '奖品名称',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightController,
              decoration: const InputDecoration(
                labelText: '权重',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countController,
              decoration: const InputDecoration(
                labelText: '数量',
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
      appBar: AppBar(
        title: Text(_pool.name),
      ),
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
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击右下角 + 按钮添加奖品',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _prizes.length,
                  itemBuilder: (context, index) {
                    final prize = _prizes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                          prize.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: prize.exist ? null : TextDecoration.lineThrough,
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
                                    _prizes[index] = prize.copyWith(exist: value);
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
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPrize,
        tooltip: '添加奖品',
        child: const Icon(Icons.add),
      ),
    );
  }
}
