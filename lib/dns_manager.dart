import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DnsManager {
  static const _sourcesKey = 'dns_sources';
  static const _masterPoolKey = 'master_dns_pool';
  static const _displayListKey = 'display_dns_list';

  final List<String> premiumGamingDns = const [
    '78.157.42.100', '176.119.1.1', '10.202.10.10', '119.29.29.29',
    '223.5.5.5', '8.26.56.26', '209.244.0.3', '1.1.1.1', '8.8.8.8',
  ];

  bool isValidIp(String ip) {
    final value = ip.trim();
    final address = InternetAddress.tryParse(value);
    if (address == null) return false;
    if (address.type != InternetAddressType.IPv4 && address.type != InternetAddressType.IPv6) return false;
    if (address.type == InternetAddressType.IPv6) return true;

    final octets = value.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((e) => e == null || e < 0 || e > 255)) return false;

    final a = octets[0]!;
    final b = octets[1]!;
    final isPrivate = a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || a == 127 || (a == 169 && b == 254);
    return !isPrivate;
  }

  Future<void> saveSources(List<String> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sourcesKey, sources.toSet().toList());
  }

  Future<List<String>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final sources = prefs.getStringList(_sourcesKey);
    
    // استفاده از CDN های جهانی و بدون فیلتر برای اتصال مستقیم به گیت‌هاب بدون ارور
    return sources == null || sources.isEmpty
        ? const [
            'https://cdn.jsdelivr.net/gh/smokeme/Public-DNS-Collector@main/lists/ipv4.txt',
            'https://fastly.jsdelivr.net/gh/smokeme/Public-DNS-Collector@main/lists/ipv4.txt',
            'https://gcore.jsdelivr.net/gh/smokeme/Public-DNS-Collector@main/lists/ipv4.txt',
            'https://raw.kkgithub.com/smokeme/Public-DNS-Collector/main/lists/ipv4.txt'
          ]
        : sources;
  }

  Future<void> saveMasterPool(List<String> ips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_masterPoolKey, ips.toSet().toList());
  }

  Future<List<String>> loadMasterPool() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_masterPoolKey) ?? <String>[];
  }

  Future<void> saveDisplayList(List<String> ips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_displayListKey, ips.toSet().toList());
  }

  Future<List<String>> loadDisplayList() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_displayListKey) ?? <String>[];
  }

  List<String> extractIpsFromText(String text) {
    final found = <String>{};
    final candidates = RegExp(r'(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)').allMatches(text);
    for (final match in candidates) {
      final ip = match.group(0)!;
      if (isValidIp(ip)) found.add(ip);
    }
    return found.toList();
  }

  Future<Map<String, dynamic>> fetchFromNetwork() async {
    final sources = await loadSources();
    final masterPool = (await loadMasterPool()).toSet();
    int initialSize = masterPool.length;
    bool success = false;

    for (final rawUrl in sources) {
      final url = rawUrl.trim();
      if (url.isEmpty) continue;
      try {
        // اختصاص ۲۰ ثانیه زمان برای دانلود فایل‌های عظیم چند هزار خطی
        final response = await http
            .get(Uri.parse(url), headers: const {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 20));
        
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          success = true;
          final extracted = extractIpsFromText(response.body);
          masterPool.addAll(extracted);
          
          // دریافت هزاران دی‌ان‌اس با یک اتصال موفق
          if (extracted.length > 500) break; 
        }
      } catch (_) {
        // اگر یک CDN مسدود بود، بدون خطا دادن سراغ سرور بعدی می‌رود
      }
    }

    int newAdded = masterPool.length - initialSize;

    if (success || newAdded > 0) {
      await saveMasterPool(masterPool.toList());
      return {'status': 'success', 'count': newAdded};
    }

    return {'status': 'error', 'count': 0};
  }

  Future<File?> generateExportFile() async {
    try {
      final pool = await loadMasterPool();
      final allDns = <String>{...premiumGamingDns, ...pool};
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Gaming_DNS_Backup.txt');
      await file.writeAsString('${allDns.join('\n')}\n');
      return file;
    } catch (_) {
      return null;
    }
  }
}
