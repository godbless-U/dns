import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dns_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GamingDnsApp());
}

class DnsServer {
  String ip;
  int ping;
  bool isPremium;
  DnsServer({required this.ip, this.ping = 9999, this.isPremium = false});
}

class GamingDnsApp extends StatelessWidget {
  const GamingDnsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurpleAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.deepPurpleAccent, centerTitle: true),
      ),
      home: const DnsScreen(),
    );
  }
}

class DnsScreen extends StatefulWidget {
  const DnsScreen({super.key});

  @override
  State<DnsScreen> createState() => _DnsScreenState();
}

class _DnsScreenState extends State<DnsScreen> {
  static const platform = MethodChannel('com.example.gaming_dns/vpn');
  final DnsManager _dnsManager = DnsManager();
  
  List<DnsServer> displayList = [];
  bool isLoading = false;
  bool isTestingPing = false;
  String? connectedDns;
  int selectedBatchSize = 100; // پیش‌فرض برای دیدن لیست طولانی
  int totalPoolSize = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    setState(() => isLoading = true);
    
    List<String> savedIps = await _dnsManager.loadDisplayList();
    List<String> pool = await _dnsManager.loadMasterPool();
    List<DnsServer> initialList = [];
    
    for (var ip in _dnsManager.premiumGamingDns) {
      initialList.add(DnsServer(ip: ip, isPremium: true));
    }

    for (var ip in savedIps) {
      if (!_dnsManager.premiumGamingDns.contains(ip)) {
        initialList.add(DnsServer(ip: ip, isPremium: false));
      }
    }

    if (!mounted) return;
    setState(() {
      displayList = initialList;
      totalPoolSize = pool.length;
      isLoading = false;
    });

    if (displayList.isNotEmpty) testAllPingsAndSort();
  }

  Future<void> huntNewDns() async {
    setState(() => isLoading = true);

    // اتصال قدرتمند و مستقیم به گیت‌هاب 
    final result = await _dnsManager.fetchFromNetwork();
    if (!mounted) return;

    final status = result['status'];
    final count = result['count'];

    if (status == 'success' && count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$count دی‌ان‌اس جدید از گیت‌هاب شکار شد!", textDirection: TextDirection.rtl), backgroundColor: Colors.green));
    } else if (status == 'success' && count == 0) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("گیت‌هاب چک شد. سرورها آپدیت هستند.", textDirection: TextDirection.rtl), backgroundColor: Colors.blue));
    } else {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("خطای اینترنت. لطفاً دسترسی شبکه را بررسی کنید.", textDirection: TextDirection.rtl), backgroundColor: Colors.redAccent));
    }

    List<String> masterPool = await _dnsManager.loadMasterPool();
    masterPool.shuffle(); // بر زدن سرورها برای نمایش دی‌ان‌اس‌های جدید در هر بار کلیک

    List<DnsServer> batch = [];
    List<String> displayStrings = [];

    for (var ip in _dnsManager.premiumGamingDns) {
      batch.add(DnsServer(ip: ip, isPremium: true));
      displayStrings.add(ip);
    }

    int addedCount = 0;
    for (var ip in masterPool) {
      if (addedCount >= selectedBatchSize) break;
      if (!_dnsManager.premiumGamingDns.contains(ip) && !displayList.any((srv) => srv.ip == ip)) {
        batch.add(DnsServer(ip: ip, isPremium: false));
        displayStrings.add(ip);
        addedCount++;
      }
    }

    await _dnsManager.saveDisplayList(displayStrings);

    if (!mounted) return;
    setState(() {
      displayList = batch;
      totalPoolSize = masterPool.length;
      isLoading = false;
    });

    testAllPingsAndSort();
  }

  Future<void> testAllPingsAndSort() async {
    if (!mounted) return;
    setState(() => isTestingPing = true);

    // تست همزمان 25 دی‌ان‌اس برای افزایش چشمگیر سرعت پینگ‌گیری
    int chunkSize = 25; 
    for (int i = 0; i < displayList.length; i += chunkSize) {
      int end = (i + chunkSize < displayList.length) ? i + chunkSize : displayList.length;
      var chunk = displayList.sublist(i, end);

      await Future.wait(chunk.map((server) async {
        final stopwatch = Stopwatch()..start();
        try {
          final socket = await Socket.connect(server.ip, 53, timeout: const Duration(milliseconds: 1500));
          socket.destroy();
          server.ping = stopwatch.elapsedMilliseconds;
        } catch (e) {
          server.ping = 9999;
        }
      }));
      
      // آپدیت زنده رابط کاربری حین پینگ گرفتن
      if (mounted) setState(() {}); 
    }

    if (!mounted) return;
    setState(() {
      displayList.sort((a, b) => a.ping.compareTo(b.ping));
      isTestingPing = false;
    });
  }

  Future<void> pickAndImportFile() async {
    final PlatformFile? pickedFile = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['txt']);
    if (pickedFile != null && pickedFile.path != null) {
      final File file = File(pickedFile.path!);
      String contents = await file.readAsString();
      if (!mounted) return;
      
      List<String> newIps = _dnsManager.extractIpsFromText(contents);
      if (newIps.isNotEmpty) {
        List<String> masterPool = await _dnsManager.loadMasterPool();
        masterPool.addAll(newIps);
        await _dnsManager.saveMasterPool(masterPool.toSet().toList());
        if (!mounted) return;
        
        setState(() => totalPoolSize = masterPool.toSet().length);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${newIps.length} دی‌ان‌اس استخراج شد.", textDirection: TextDirection.rtl), backgroundColor: Colors.green));
      }
    }
  }

  Future<void> exportDnsDatabase() async {
    setState(() => isLoading = true);
    File? exportFile = await _dnsManager.generateExportFile();
    if (!mounted) return;
    setState(() => isLoading = false);

    if (exportFile != null) {
      await SharePlus.instance.share(ShareParams(files: [XFile(exportFile.path)], text: 'بکاپ DNS های من'));
    }
  }

  void _showAddOptionsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(leading: const Icon(Icons.dns, color: Colors.greenAccent), title: const Text("افزودن DNS تکی", style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); _showAddSingleDnsDialog(); }),
              ListTile(leading: const Icon(Icons.link, color: Colors.orangeAccent), title: const Text("افزودن لینک سورس", style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); _showAddSourceDialog(); }),
            ],
          ),
        );
      }
    );
  }

  void _showAddSingleDnsDialog() {
    final TextEditingController ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("افزودن DNS جدید", style: TextStyle(fontSize: 16)),
        content: TextField(controller: ipController, decoration: const InputDecoration(hintText: "مثال: 8.8.8.8"), keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("لغو")),
          ElevatedButton(
            onPressed: () async {
              String ip = ipController.text.trim();
              if (_dnsManager.isValidIp(ip)) {
                List<String> displayStrings = displayList.map((e) => e.ip).toList();
                if (!displayStrings.contains(ip)) {
                  displayStrings.add(ip);
                  await _dnsManager.saveDisplayList(displayStrings);
                  setState(() => displayList.add(DnsServer(ip: ip, ping: 0)));
                  testAllPingsAndSort();
                }
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text("ذخیره"),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog() {
    final TextEditingController urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("افزودن لینک منبع", style: TextStyle(fontSize: 16)),
        content: TextField(controller: urlController, decoration: const InputDecoration(hintText: "https://..."), keyboardType: TextInputType.url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("لغو")),
          ElevatedButton(
            onPressed: () async {
              String url = urlController.text.trim();
              if (url.startsWith('http')) {
                List<String> sources = await _dnsManager.loadSources();
                if (!sources.contains(url)) {
                  sources.add(url);
                  await _dnsManager.saveSources(sources);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("سورس افزوده شد. حالا شکار کنید."), backgroundColor: Colors.green));
                }
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text("ذخیره"),
          ),
        ],
      ),
    );
  }

  Future<void> connectDns(String dns) async {
    try {
      await platform.invokeMethod('startVpn', {'dns_ip': dns});
      if (!mounted) return;
      setState(() => connectedDns = dns);
    } on PlatformException catch (e) {
      debugPrint("Error: '${e.message}'.");
    }
  }

  Future<void> disconnectDns() async {
    try {
      await platform.invokeMethod('stopVpn');
      if (!mounted) return;
      setState(() => connectedDns = null);
    } on PlatformException catch (e) {
      debugPrint("Error: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS Hunter PRO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.upload_file), tooltip: "ایمپورت", onPressed: pickAndImportFile),
          IconButton(icon: const Icon(Icons.ios_share), tooltip: "اکسپورت", onPressed: exportDnsDatabase),
          if (displayList.isNotEmpty)
            IconButton(
              icon: isTestingPing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: isTestingPing ? null : testAllPingsAndSort,
            )
        ],
      ),
      floatingActionButton: FloatingActionButton(backgroundColor: Colors.deepPurpleAccent, onPressed: _showAddOptionsModal, child: const Icon(Icons.add, color: Colors.white)),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E1E1E),
            child: Row(
              children: [
                Text("استخر: $totalPoolSize", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const Spacer(),
                const Text("تعداد نمایش:", style: TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                DropdownButton<int>(
                  value: selectedBatchSize, dropdownColor: const Color(0xFF2C2C2C), underline: Container(),
                  // قابلیت انتخاب تا 500 دی‌ان‌اس به صورت همزمان
                  items: [50, 100, 200, 500].map((int value) => DropdownMenuItem<int>(value: value, child: Text("$value"))).toList(),
                  onChanged: (int? newValue) { if (newValue != null) setState(() => selectedBatchSize = newValue); },
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: isLoading || isTestingPing ? null : huntNewDns,
                  icon: const Icon(Icons.radar),
                  label: const Text("شکار جدید", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
                : displayList.isEmpty
                    ? const Center(child: Text("جهت دانلود سرورها روی دکمه شکار کلیک کنید.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final server = displayList[index];
                          final isConnected = server.ip == connectedDns;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            color: isConnected ? Colors.deepPurple.withValues(alpha: 0.3) : const Color(0xFF252525),
                            shape: RoundedRectangleBorder(side: BorderSide(color: isConnected ? Colors.deepPurpleAccent : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              title: Text(server.ip, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: Row(
                                children: [
                                  Text(
                                    server.ping == 9999 ? "TimeOut" : "${server.ping} ms",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: server.ping < 100 ? Colors.greenAccent : (server.ping == 9999 ? Colors.redAccent : Colors.amberAccent)),
                                  ),
                                  const SizedBox(width: 10),
                                  if (server.isPremium) const Text("🎮 پرمیوم", style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                                ],
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: isConnected ? Colors.redAccent : Colors.deepPurpleAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                onPressed: () => isConnected ? disconnectDns() : connectDns(server.ip),
                                child: Text(isConnected ? 'قطع' : 'اتصال', style: const TextStyle(color: Colors.white)),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
