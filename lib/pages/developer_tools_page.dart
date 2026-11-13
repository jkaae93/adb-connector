import 'package:adb_connector/services/adb_service.dart';
import 'package:adb_connector/theme/vaulta.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum DevToolTab { app, display, port }

class DeveloperToolsPage extends StatefulWidget {
  const DeveloperToolsPage({super.key, required this.serial});
  final String serial;

  @override
  State<DeveloperToolsPage> createState() => _DeveloperToolsPageState();
}

class _DeveloperToolsPageState extends State<DeveloperToolsPage> {
  final adb = AdbService();
  DevToolTab _selectedTab = DevToolTab.app;
  String result = '';
  bool busy = false;

  // 패키지 목록 캐시
  List<String> _packages = [];
  bool _loadingPackages = false;

  // 딥링크 컨트롤러
  final _deepLinkUriController = TextEditingController();
  final _deepLinkPkgController = TextEditingController();

  // 앱 상태 관리 컨트롤러
  final _appPkgController = TextEditingController();

  // 권한 관리 컨트롤러
  final _permPkgController = TextEditingController();
  String _selectedPerm = 'android.permission.POST_NOTIFICATIONS';
  final _customPermController = TextEditingController();

  // 화면 설정 컨트롤러 & 현재 상태
  final _densityController = TextEditingController();
  final _sizeController = TextEditingController();
  String _currentDensity = '-';
  String _currentSize = '-';

  // 텍스트 입력 컨트롤러
  final _inputTextController = TextEditingController();

  // 포트 포워딩 컨트롤러 & 목록
  final _revDevicePortController = TextEditingController();
  final _revMacPortController = TextEditingController();
  final _fwdMacPortController = TextEditingController();
  final _fwdDevicePortController = TextEditingController();
  List<String> _reverseRules = [];
  List<String> _forwardRules = [];

  // APK 설치 옵션
  List<String> _selectedApkPaths = [];
  bool _apkReplace = true;
  bool _apkTest = true;
  bool _apkDowngrade = false;
  bool _apkGrant = true;

  static const _commonPermissions = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.CAMERA',
    'android.permission.RECORD_AUDIO',
    'android.permission.READ_MEDIA_IMAGES',
    'android.permission.READ_MEDIA_VIDEO',
    'android.permission.READ_EXTERNAL_STORAGE',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _deepLinkUriController.dispose();
    _deepLinkPkgController.dispose();
    _appPkgController.dispose();
    _permPkgController.dispose();
    _customPermController.dispose();
    _densityController.dispose();
    _sizeController.dispose();
    _inputTextController.dispose();
    _revDevicePortController.dispose();
    _revMacPortController.dispose();
    _fwdMacPortController.dispose();
    _fwdDevicePortController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    _refreshDisplayInfo();
    _refreshPortRules();
    _loadThirdPartyPackages();
  }

  Future<void> _runCommand(List<String> args, {String? actionDescription}) async {
    setState(() => busy = true);
    final response = await adb.command([
      '-s',
      widget.serial,
      ...args,
    ], limit: const Duration(minutes: 5));

    if (!mounted) return;
    setState(() {
      final out = '${response.stdout}${response.stderr}'.trim();
      final prefix = actionDescription != null ? '[$actionDescription]\n' : '';
      result = '$prefix${out.isEmpty ? '✓ 명령이 성공적으로 실행되었습니다.' : out}';
      busy = false;
    });
  }

  Future<void> _loadThirdPartyPackages() async {
    setState(() => _loadingPackages = true);
    try {
      final response = await adb.command([
        '-s',
        widget.serial,
        'shell',
        'pm',
        'list',
        'packages',
        '-3',
      ]);
      final lines = '${response.stdout}'.split('\n');
      final pkgs = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('package:')) {
          pkgs.add(trimmed.substring('package:'.length));
        }
      }
      pkgs.sort();
      if (mounted) {
        setState(() {
          _packages = pkgs;
          _loadingPackages = false;
          if (pkgs.isNotEmpty) {
            if (_appPkgController.text.isEmpty) _appPkgController.text = pkgs.first;
            if (_permPkgController.text.isEmpty) _permPkgController.text = pkgs.first;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPackages = false);
    }
  }

  Future<void> _refreshDisplayInfo() async {
    final dRes = await adb.command(['-s', widget.serial, 'shell', 'wm', 'density']);
    final sRes = await adb.command(['-s', widget.serial, 'shell', 'wm', 'size']);
    if (mounted) {
      setState(() {
        _currentDensity = '${dRes.stdout}'.trim();
        _currentSize = '${sRes.stdout}'.trim();
      });
    }
  }

  Future<void> _refreshPortRules() async {
    final revRes = await adb.command(['-s', widget.serial, 'reverse', '--list']);
    final fwdRes = await adb.command(['-s', widget.serial, 'forward', '--list']);
    if (mounted) {
      setState(() {
        _reverseRules = '${revRes.stdout}'
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        _forwardRules = '${fwdRes.stdout}'
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      });
    }
  }

  // --- Actions ---

  Future<void> _pickApkFiles() async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
      allowMultiple: true,
    );
    if (selection != null) {
      setState(() {
        _selectedApkPaths = selection.files
            .map((f) => f.path)
            .whereType<String>()
            .toList();
      });
    }
  }

  Future<void> _installApk() async {
    if (_selectedApkPaths.isEmpty) return;
    final options = [
      if (_apkReplace) '-r',
      if (_apkTest) '-t',
      if (_apkDowngrade) '-d',
      if (_apkGrant) '-g',
    ];
    await _runCommand([
      _selectedApkPaths.length == 1 ? 'install' : 'install-multiple',
      ...options,
      ..._selectedApkPaths,
    ], actionDescription: 'APK 설치');
    _loadThirdPartyPackages();
  }

  Future<void> _executeDeepLink() async {
    final uri = _deepLinkUriController.text.trim();
    if (uri.isEmpty) return;
    final pkg = _deepLinkPkgController.text.trim();
    await _runCommand([
      'shell',
      'am',
      'start',
      '-W',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      uri,
      if (pkg.isNotEmpty) pkg,
    ], actionDescription: '딥링크 실행');
  }

  Future<void> _clearAppData() async {
    final pkg = _appPkgController.text.trim();
    if (pkg.isEmpty) return;
    await _runCommand(['shell', 'pm', 'clear', pkg], actionDescription: '데이터 초기화 ($pkg)');
  }

  Future<void> _forceStopApp() async {
    final pkg = _appPkgController.text.trim();
    if (pkg.isEmpty) return;
    await _runCommand(['shell', 'am', 'force-stop', pkg], actionDescription: '강제 종료 ($pkg)');
  }

  Future<void> _grantPermission() async {
    final pkg = _permPkgController.text.trim();
    final perm = _customPermController.text.trim().isNotEmpty
        ? _customPermController.text.trim()
        : _selectedPerm;
    if (pkg.isEmpty || perm.isEmpty) return;
    await _runCommand(['shell', 'pm', 'grant', pkg, perm], actionDescription: '권한 부여 ($perm)');
  }

  Future<void> _revokePermission() async {
    final pkg = _permPkgController.text.trim();
    final perm = _customPermController.text.trim().isNotEmpty
        ? _customPermController.text.trim()
        : _selectedPerm;
    if (pkg.isEmpty || perm.isEmpty) return;
    await _runCommand(['shell', 'pm', 'revoke', pkg, perm], actionDescription: '권한 회수 ($perm)');
  }

  Future<void> _applyDensity(String val) async {
    await _runCommand(['shell', 'wm', 'density', val], actionDescription: 'DPI 설정 ($val)');
    _refreshDisplayInfo();
  }

  Future<void> _resetDensity() async {
    await _runCommand(['shell', 'wm', 'density', 'reset'], actionDescription: 'DPI 초기화');
    _refreshDisplayInfo();
  }

  Future<void> _applySize(String val) async {
    await _runCommand(['shell', 'wm', 'size', val], actionDescription: '해상도 설정 ($val)');
    _refreshDisplayInfo();
  }

  Future<void> _resetSize() async {
    await _runCommand(['shell', 'wm', 'size', 'reset'], actionDescription: '해상도 초기화');
    _refreshDisplayInfo();
  }

  Future<void> _resetAllDisplay() async {
    await _runCommand(['shell', 'wm', 'density', 'reset'], actionDescription: '화면 전체 초기화');
    await adb.command(['-s', widget.serial, 'shell', 'wm', 'size', 'reset']);
    _refreshDisplayInfo();
  }

  Future<void> _sendInputText() async {
    final text = _inputTextController.text;
    if (text.isEmpty) return;
    final escaped = text.replaceAll(' ', '%s');
    await _runCommand(['shell', 'input', 'text', escaped], actionDescription: '텍스트 전송');
    _inputTextController.clear();
  }

  Future<void> _addPortRule(bool reverse) async {
    final local = reverse ? _revDevicePortController.text.trim() : _fwdMacPortController.text.trim();
    final remote = reverse ? _revMacPortController.text.trim() : _fwdDevicePortController.text.trim();
    if (local.isEmpty || remote.isEmpty) return;

    await _runCommand([
      reverse ? 'reverse' : 'forward',
      '--no-rebind',
      'tcp:$local',
      'tcp:$remote',
    ], actionDescription: '${reverse ? 'Reverse' : 'Forward'} 규칙 추가');

    _refreshPortRules();
  }

  Future<void> _deletePortRule(bool reverse, String portSpec) async {
    await _runCommand([
      reverse ? 'reverse' : 'forward',
      '--remove',
      portSpec,
    ], actionDescription: '${reverse ? 'Reverse' : 'Forward'} 규칙 삭제');

    _refreshPortRules();
  }

  // --- UI Components ---

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                VaultaListIcon(icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Vaulta.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  // 1. 앱 디버깅 탭
  Widget _buildAppTab() {
    return Column(
      children: [
        // 딥링크 테스트
        _sectionCard(
          icon: Icons.link,
          title: '딥링크 / 앱링크 테스트',
          subtitle: 'URI 스키마를 기기에 직접 전달하여 화면 라우팅을 검증합니다.',
          child: Column(
            children: [
              TextField(
                controller: _deepLinkUriController,
                decoration: const InputDecoration(
                  labelText: 'URI / URL',
                  hintText: '예: myapp://details?id=42 또는 https://myapp.com/item/1',
                  prefixIcon: Icon(Icons.http, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _deepLinkPkgController,
                      decoration: const InputDecoration(
                        labelText: '타깃 패키지명 (선택)',
                        hintText: 'com.example.myapp',
                        prefixIcon: Icon(Icons.filter_none, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : _executeDeepLink,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('실행'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 앱 상태 관리 (초기화 & 종료)
        _sectionCard(
          icon: Icons.cleaning_services_rounded,
          title: '앱 데이터 초기화 및 강제 종료',
          subtitle: '로컬 DB(SharedPreferences, SQLite) 초기화 및 프로세스를 재시작합니다.',
          trailing: IconButton(
            tooltip: '설치된 사용자 앱 목록 새로고침',
            icon: _loadingPackages
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            onPressed: _loadingPackages ? null : _loadThirdPartyPackages,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _packages.isNotEmpty
                        ? DropdownButtonFormField<String>(
                            initialValue: _packages.contains(_appPkgController.text)
                                ? _appPkgController.text
                                : _packages.first,
                            decoration: const InputDecoration(
                              labelText: '대상 패키지 선택',
                              prefixIcon: Icon(Icons.android, size: 18),
                            ),
                            items: _packages
                                .map((pkg) => DropdownMenuItem(
                                      value: pkg,
                                      child: Text(pkg, style: const TextStyle(fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _appPkgController.text = val;
                                  _permPkgController.text = val;
                                });
                              }
                            },
                          )
                        : TextField(
                            controller: _appPkgController,
                            decoration: const InputDecoration(
                              labelText: '패키지명 직접 입력',
                              hintText: 'com.example.myapp',
                              prefixIcon: Icon(Icons.android, size: 18),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _forceStopApp,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('강제 종료'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Vaulta.danger,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: busy ? null : _clearAppData,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('데이터 초기화'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 런타임 권한 제어
        _sectionCard(
          icon: Icons.security_rounded,
          title: '런타임 권한 제어 (Grant / Revoke)',
          subtitle: '개별 권한을 허용하거나 회수하여 권한 요청 흐름을 테스트합니다.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedPerm,
                      decoration: const InputDecoration(
                        labelText: '자주 쓰이는 주요 권한',
                        prefixIcon: Icon(Icons.shield_outlined, size: 18),
                      ),
                      items: _commonPermissions
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(
                                  p.replaceAll('android.permission.', ''),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedPerm = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _revokePermission,
                    icon: const Icon(Icons.block, size: 16),
                    label: const Text('권한 회수'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: busy ? null : _grantPermission,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('권한 부여'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // APK 설치
        _sectionCard(
          icon: Icons.install_mobile_rounded,
          title: 'APK 빌드 파일 설치',
          subtitle: '로컬 APK 파일을 선택하여 기기에 배포합니다.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickApkFiles,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(
                      _selectedApkPaths.isEmpty
                          ? 'APK 파일 선택...'
                          : '${_selectedApkPaths.length}개 파일 선택됨',
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_selectedApkPaths.isNotEmpty)
                    FilledButton.icon(
                      onPressed: busy ? null : _installApk,
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('지금 설치'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('기존 앱 교체 (-r)'),
                    selected: _apkReplace,
                    onSelected: (v) => setState(() => _apkReplace = v),
                  ),
                  FilterChip(
                    label: const Text('테스트 APK 허용 (-t)'),
                    selected: _apkTest,
                    onSelected: (v) => setState(() => _apkTest = v),
                  ),
                  FilterChip(
                    label: const Text('런타임 권한 일괄 부여 (-g)'),
                    selected: _apkGrant,
                    onSelected: (v) => setState(() => _apkGrant = v),
                  ),
                  FilterChip(
                    label: const Text('다운그레이드 허용 (-d)'),
                    selected: _apkDowngrade,
                    onSelected: (v) => setState(() => _apkDowngrade = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2. 화면 & 디바이스 제어 탭
  Widget _buildDisplayTab() {
    return Column(
      children: [
        // 화면 DPI 조절
        _sectionCard(
          icon: Icons.aspect_ratio_rounded,
          title: '화면 밀도 (DPI 조절)',
          subtitle: 'UI 크기 및 반응형 레이아웃 대응을 위해 가상 DPI를 변경합니다.',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Vaulta.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _currentDensity,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Vaulta.accentBright,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('빠른 DPI 프리셋', style: TextStyle(fontSize: 12, color: Vaulta.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [240, 320, 400, 480, 560].map((dpi) {
                  return ActionChip(
                    label: Text('$dpi DPI'),
                    onPressed: () => _applyDensity('$dpi'),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _densityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'DPI 수치 직접 입력',
                        hintText: '예: 360',
                        prefixIcon: Icon(Icons.tune, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            final val = _densityController.text.trim();
                            if (val.isNotEmpty) _applyDensity(val);
                          },
                    child: const Text('적용'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: busy ? null : _resetDensity,
                    child: const Text('DPI 기본값 복구'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 해상도 조절
        _sectionCard(
          icon: Icons.screenshot_monitor_rounded,
          title: '화면 해상도 (Resolution)',
          subtitle: '다양한 디바이스 해상도비 테스트용 (Width x Height).',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Vaulta.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _currentSize,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Vaulta.accentBright,
              ),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sizeController,
                      decoration: const InputDecoration(
                        labelText: '해상도 입력 (WxH)',
                        hintText: '예: 1080x1920 또는 720x1280',
                        prefixIcon: Icon(Icons.fullscreen, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            final val = _sizeController.text.trim();
                            if (val.isNotEmpty) _applySize(val);
                          },
                    child: const Text('적용'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: busy ? null : _resetSize,
                    child: const Text('해상도 복구'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: busy ? null : _resetAllDisplay,
                    child: const Text('전체 원복 (Reset All)'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 텍스트 전송
        _sectionCard(
          icon: Icons.keyboard_alt_rounded,
          title: '디바이스 텍스트 직접 전송',
          subtitle: 'Mac에서 타이핑하여 기기의 현재 포커스된 입력창으로 텍스트를 전달합니다.',
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputTextController,
                  decoration: const InputDecoration(
                    labelText: '전송할 텍스트',
                    hintText: '긴 비밀번호, 복잡한 인증 토큰, 이메일 주소 등',
                    prefixIcon: Icon(Icons.edit_note, size: 18),
                  ),
                  onSubmitted: (_) => _sendInputText(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: busy ? null : _sendInputText,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('기기로 전송'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. 포트 포워딩 탭
  Widget _buildPortTab() {
    return Column(
      children: [
        // Reverse 포워딩
        _sectionCard(
          icon: Icons.swap_calls_rounded,
          title: 'Reverse 포워딩 (기기 localhost ➔ Mac)',
          subtitle: '기기에서 Mac의 로컬 백엔드 서버(localhost:8080 등)를 호출할 때 필수적입니다.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_reverseRules.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Vaulta.surfaceElevated
                        : Vaulta.lightBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '현재 활성화된 Reverse 규칙이 없습니다.',
                    style: TextStyle(fontSize: 12, color: Vaulta.textSecondary),
                  ),
                )
              else
                Column(
                  children: _reverseRules.map((rule) {
                    final parts = rule.split(RegExp(r'\s+'));
                    final spec = parts.length >= 2 ? parts[1] : rule;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Vaulta.surfaceElevated
                            : Vaulta.lightBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link, size: 16, color: Vaulta.accentBright),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              rule,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Vaulta.danger),
                            tooltip: '규칙 제거',
                            onPressed: () => _deletePortRule(true, spec),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _revDevicePortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '기기 포트 (Device)',
                        hintText: '8080',
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.arrow_forward, size: 16, color: Vaulta.textSecondary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _revMacPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Mac 포트 (Host)',
                        hintText: '8080',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _addPortRule(true),
                    icon: const Icon(Icons.add_link, size: 16),
                    label: const Text('규칙 추가'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Forward 포워딩
        _sectionCard(
          icon: Icons.alt_route_rounded,
          title: 'Forward 포워딩 (Mac localhost ➔ 기기)',
          subtitle: 'Mac의 포트를 기기의 내부 포트로 전달합니다.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_forwardRules.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Vaulta.surfaceElevated
                        : Vaulta.lightBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '현재 활성화된 Forward 규칙이 없습니다.',
                    style: TextStyle(fontSize: 12, color: Vaulta.textSecondary),
                  ),
                )
              else
                Column(
                  children: _forwardRules.map((rule) {
                    final parts = rule.split(RegExp(r'\s+'));
                    final spec = parts.length >= 2 ? parts[1] : rule;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Vaulta.surfaceElevated
                            : Vaulta.lightBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link, size: 16, color: Vaulta.accentBright),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              rule,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Vaulta.danger),
                            tooltip: '규칙 제거',
                            onPressed: () => _deletePortRule(false, spec),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fwdMacPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Mac 포트 (Host)',
                        hintText: '8080',
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.arrow_forward, size: 16, color: Vaulta.textSecondary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _fwdDevicePortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '기기 포트 (Device)',
                        hintText: '8080',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _addPortRule(false),
                    icon: const Icon(Icons.add_link, size: 16),
                    label: const Text('규칙 추가'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('개발 도구 (Developer Tools)'),
        actions: [
          IconButton(
            tooltip: '디스플레이 및 포트 정보 새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _refreshDisplayInfo();
              _refreshPortRules();
              _loadThirdPartyPackages();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: VaultaPageWidth(
        maxWidth: 820,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // 대상 기기 카드
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const VaultaListIcon(Icons.phone_android),
                title: Text(
                  widget.serial,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text('ADB 대상 기기', style: TextStyle(fontSize: 12)),
                trailing: VaultaStatusPill.connected(),
              ),
            ),
            const SizedBox(height: 20),

            // 상단 세그먼트 네비게이션
            Center(
              child: SegmentedButton<DevToolTab>(
                segments: const [
                  ButtonSegment(
                    value: DevToolTab.app,
                    label: Text('앱 디버깅 & 테스트'),
                    icon: Icon(Icons.apps_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: DevToolTab.display,
                    label: Text('화면 & 제어'),
                    icon: Icon(Icons.devices_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: DevToolTab.port,
                    label: Text('포트 포워딩'),
                    icon: Icon(Icons.sync_alt_rounded, size: 18),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (set) => setState(() => _selectedTab = set.first),
              ),
            ),
            const SizedBox(height: 20),

            // 탭별 콘텐츠
            if (_selectedTab == DevToolTab.app) _buildAppTab(),
            if (_selectedTab == DevToolTab.display) _buildDisplayTab(),
            if (_selectedTab == DevToolTab.port) _buildPortTab(),

            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],

            // 실행 결과 콘솔창
            if (result.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: VaultaSectionTitle('터미널 실행 결과'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => result = ''),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('지우기'),
                  ),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: result)),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('복사'),
                  ),
                ],
              ),
              Card(
                margin: EdgeInsets.zero,
                color: dark ? Vaulta.bg : Vaulta.lightSurface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    result,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: dark ? Vaulta.textSecondary : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }
}


