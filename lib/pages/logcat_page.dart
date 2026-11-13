import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb_connector/theme/vaulta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum LogcatFilterPreset { all, flutter, appPid, errors, crash }

class LogLine {
  LogLine({
    required this.raw,
    required this.priority,
    required this.tag,
    this.pid,
  });

  final String raw;
  final String priority; // V, D, I, W, E, F
  final String tag;
  final String? pid;

  static LogLine parse(String raw) {
    // threadtime format:
    // 05-08 11:28:00.000  1234  5678 I TAG     : message
    final regex = RegExp(
      r'^\d+-\d+\s+\d+:\d+:\d+\.\d+\s+(\d+)\s+\d+\s+([VDIWEF])\s+([^:]+):',
    );
    final match = regex.firstMatch(raw);
    return LogLine(
      raw: raw,
      pid: match?.group(1),
      priority: match?.group(2) ?? '',
      tag: match?.group(3)?.trim() ?? '',
    );
  }
}

class LogcatPage extends StatefulWidget {
  const LogcatPage({
    super.key,
    required this.deviceName,
    required this.processFactory,
    required this.resolvePackagePid,
    this.onClearBuffer,
    this.standaloneWindow = false,
  });

  final String deviceName;
  final Future<Process> Function() processFactory;
  final Future<String?> Function(String packageName) resolvePackagePid;
  final Future<void> Function()? onClearBuffer;
  final bool standaloneWindow;

  @override
  State<LogcatPage> createState() => _LogcatPageState();
}

class _LogcatPageState extends State<LogcatPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _filterController = TextEditingController();

  final List<LogLine> _logs = [];
  static const int _maxLogs = 5000;

  Process? _process;
  bool _closing = false;
  static const _windowChannel = MethodChannel('adb_connector/log_window');
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  bool _isPaused = false;
  bool _autoScroll = true;
  String _filterText = '';
  LogcatFilterPreset _preset = LogcatFilterPreset.all;
  String? _packageName;
  String? _appPid;
  final Set<String> _priorityFilter = {'V', 'D', 'I', 'W', 'E', 'F'};

  @override
  void initState() {
    super.initState();
    if (widget.standaloneWindow) {
      _windowChannel.setMethodCallHandler((call) async {
        if (call.method == 'windowClosing') {
          _closing = true;
          _stopLogcat();
        }
      });
    }
    _scrollController.addListener(_onScroll);
    _startLogcat();
  }

  @override
  void dispose() {
    if (widget.standaloneWindow) _windowChannel.setMethodCallHandler(null);
    _closing = true;
    _stopLogcat();
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50;
    if (_autoScroll != atBottom) {
      setState(() => _autoScroll = atBottom);
    }
  }

  Future<void> _startLogcat() async {
    try {
      final process = await widget.processFactory();
      if (!mounted || _closing) {
        process.kill();
        return;
      }
      _process = process;
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLogLine);
      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLogLine);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('로그 실행 실패: $e'),
            backgroundColor: Vaulta.danger,
          ),
        );
      }
    }
  }

  void _stopLogcat() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process?.kill();
    _process = null;
  }

  void _onLogLine(String line) {
    if (!mounted) return;
    if (_isPaused) return;
    if (line.isEmpty) return;

    final log = LogLine.parse(line);
    setState(() {
      _logs.add(log);
      if (_logs.length > _maxLogs) {
        _logs.removeRange(0, _logs.length - _maxLogs);
      }
    });

    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  void _clearLogs() {
    setState(() => _logs.clear());
  }

  Future<void> _clearDeviceBuffer() async {
    try {
      await widget.onClearBuffer?.call();
      if (!mounted) return;
      setState(() => _logs.clear());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('기기 로그 버퍼를 비웠습니다')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('기기 로그 버퍼를 비우지 못했습니다: $error')));
    }
  }

  void _copyAll() {
    final text = _filteredLogs.map((l) => l.raw).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${_filteredLogs.length}줄 복사됨')));
  }

  void _togglePriority(String p) {
    setState(() {
      if (_priorityFilter.contains(p)) {
        _priorityFilter.remove(p);
      } else {
        _priorityFilter.add(p);
      }
    });
  }

  Future<void> _selectPreset(LogcatFilterPreset preset) async {
    String? packageName;
    if (preset == LogcatFilterPreset.appPid) {
      final controller = TextEditingController(text: _packageName);
      packageName = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('앱 PID 필터'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '패키지명',
              hintText: 'com.example.myapp',
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('적용'),
            ),
          ],
        ),
      );
      if (packageName == null || packageName.isEmpty) return;
      try {
        final pid = await widget.resolvePackagePid(packageName);
        if (pid == null || pid.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('실행 중인 앱 PID를 찾을 수 없습니다: $packageName')),
            );
          }
          return;
        }
        _appPid = pid;
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('앱 PID 조회 실패: $error')));
        }
        return;
      }
    }
    setState(() {
      _preset = preset;
      if (preset == LogcatFilterPreset.appPid) _packageName = packageName;
    });
  }

  List<LogLine> get _filteredLogs {
    return _logs.where((log) {
      switch (_preset) {
        case LogcatFilterPreset.flutter:
          if (log.tag.toLowerCase() != 'flutter') return false;
        case LogcatFilterPreset.appPid:
          if (log.pid != _appPid) return false;
        case LogcatFilterPreset.errors:
          if (log.priority != 'E' && log.priority != 'F') return false;
        case LogcatFilterPreset.crash:
          if (log.priority != 'F' &&
              !log.tag.toLowerCase().contains('crash') &&
              log.tag != 'AndroidRuntime')
            return false;
        case LogcatFilterPreset.all:
          break;
      }
      if (log.priority.isNotEmpty && !_priorityFilter.contains(log.priority)) {
        return false;
      }
      if (_filterText.isNotEmpty &&
          !log.raw.toLowerCase().contains(_filterText.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  Color _colorForPriority(String p) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (p) {
      case 'V':
        return dark ? Vaulta.textSecondary : Vaulta.lightTextSecondary;
      case 'D':
        return dark ? Vaulta.accentBright : Vaulta.actionCircle;
      case 'I':
        return Vaulta.success;
      case 'W':
        return Vaulta.warning;
      case 'E':
      case 'F':
        return Vaulta.danger;
      default:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: Text('로그 - ${widget.deviceName}'),
        actions: [
          IconButton(
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
            tooltip: _isPaused ? '재개' : '일시정지',
            onPressed: _togglePause,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '화면 비우기',
            onPressed: _clearLogs,
          ),
          if (widget.onClearBuffer != null)
            IconButton(
              icon: const Icon(Icons.cleaning_services),
              tooltip: '기기 버퍼 비우기',
              onPressed: _clearDeviceBuffer,
            ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '전체 복사',
            onPressed: _copyAll,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Vaulta.surface
                    : Vaulta.lightSurface,
                borderRadius: BorderRadius.circular(Vaulta.radiusCard),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Vaulta.stroke
                      : Vaulta.lightStroke,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Vaulta.radiusCard),
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 40,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Vaulta.textMuted
                                  : Vaulta.lightTextSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '로그가 없습니다',
                              style: TextStyle(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Vaulta.textMuted
                                    : Vaulta.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Scrollbar(
                        controller: _scrollController,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final log = filtered[index];
                            return SelectableText(
                              log.raw,
                              style: TextStyle(
                                fontFamily: 'Menlo',
                                fontSize: 12,
                                color: _colorForPriority(log.priority),
                                height: 1.4,
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ),
          _buildStatusBar(filtered.length),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? Vaulta.surface : Vaulta.lightSurface,
        border: Border(
          bottom: BorderSide(color: dark ? Vaulta.stroke : Vaulta.lightStroke),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    hintText: '검색 필터 (태그, 메시지 등)',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _filterText.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _filterController.clear();
                              setState(() => _filterText = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _filterText = v),
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<LogcatFilterPreset>(
                tooltip: '추천 필터',
                initialValue: _preset,
                onSelected: _selectPreset,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: LogcatFilterPreset.all,
                    child: Text('전체 로그'),
                  ),
                  PopupMenuItem(
                    value: LogcatFilterPreset.flutter,
                    child: Text('Flutter 로그'),
                  ),
                  PopupMenuItem(
                    value: LogcatFilterPreset.appPid,
                    child: Text('앱 PID (패키지명)'),
                  ),
                  PopupMenuItem(
                    value: LogcatFilterPreset.errors,
                    child: Text('오류 이상 (*:E)'),
                  ),
                  PopupMenuItem(
                    value: LogcatFilterPreset.crash,
                    child: Text('크래시/치명 로그'),
                  ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.filter_list, size: 18),
                  label: Text(
                    _preset == LogcatFilterPreset.appPid
                        ? (_packageName ?? '앱 PID')
                        : switch (_preset) {
                            LogcatFilterPreset.all => '전체 로그',
                            LogcatFilterPreset.flutter => 'Flutter 로그',
                            LogcatFilterPreset.appPid => '앱 PID',
                            LogcatFilterPreset.errors => '오류 이상',
                            LogcatFilterPreset.crash => '크래시/치명 로그',
                          },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['V', 'D', 'I', 'W', 'E', 'F']
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(p),
                        labelStyle: TextStyle(
                          color: _priorityFilter.contains(p)
                              ? _colorForPriority(p)
                              : Vaulta.textMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        selected: _priorityFilter.contains(p),
                        onSelected: (_) => _togglePriority(p),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(int filteredCount) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? Vaulta.surface : Vaulta.lightSurface,
        border: Border(
          top: BorderSide(color: dark ? Vaulta.stroke : Vaulta.lightStroke),
        ),
      ),
      child: Row(
        children: [
          if (_isPaused) VaultaStatusPill.paused() else VaultaStatusPill.live(),
          const SizedBox(width: 12),
          Text(
            '$filteredCount / ${_logs.length}',
            style: TextStyle(
              fontSize: 11,
              color: dark ? Vaulta.textMuted : Vaulta.lightTextSecondary,
            ),
          ),
          const Spacer(),
          if (!_autoScroll)
            TextButton.icon(
              onPressed: () {
                setState(() => _autoScroll = true);
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(
                    _scrollController.position.maxScrollExtent,
                  );
                }
              },
              icon: const Icon(Icons.arrow_downward, size: 16),
              label: const Text('맨 아래로', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
        ],
      ),
    );
  }
}
