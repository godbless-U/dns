import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DnsManager {
  static const _sourcesKey = 'dns_sources';
  static const _masterPoolKey = 'master_dns_pool';
  static const _displayListKey = 'display_dns_list';

  // سرورهای پرمیوم پایه و ثابت (بهترین‌های پابلیک)
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
    // حذف آی‌پی‌های لوکال و نامعتبر
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
    
    // ادغام دیتابیس‌های Luna-Dns (مخصوص گیم) و Public-DNS با مسیرهای ضدتحریم
    return sources == null || sources.isEmpty
        ? const [
            // مخزن Luna-Dns (تخصصی برای PUBG, CoD Mobile, Mobile Legends)
            'https://fastly.jsdelivr.net/gh/Luna-Dns/Luna-Dns@main/dns.txt',
            'https://raw.kkgithub.com/Luna-Dns/Luna-Dns/main/dns.txt',
            
            // مخزن Public DNS Directory (لیست جهانی و عظیم)
            'https://fastly.jsdelivr.net/gh/public-dns/public-dns-directory@master/nameservers.txt',
            'https://raw.kkgithub.com/public-dns/public-dns-directory/master/nameservers.txt',
            
            // مخزن کمکی و پشتیبان
            'https://fastly.jsdelivr.net/gh/smokeme/Public-DNS-Collector@main/lists/ipv4.txt'
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
    // این موتور به صورت هوشمند آی‌پی‌ها را از بین کدهای HTML، فایل‌های CSV یا متون ساده بیرون می‌کشد
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
        final response = await http
            .get(Uri.parse(url), headers: const {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          success = true;
          final extracted = extractIpsFromText(response.body);
          masterPool.addAll(extracted);
          
          // محدودیت دانلود برای جلوگیری از اشغال حافظه رم گوشی (توقف پس از شکار 800 دی‌ان‌اس)
          if (extracted.length > 800) break; 
        }
      } catch (_) {
        // نادیده گرفتن خطا و پرش به لینک جایگزین بعدی
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
