import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DnsManager {
  static const _sourcesKey = 'dns_sources';
  static const _masterPoolKey = 'master_dns_pool';
  static const _displayListKey = 'display_dns_list';

  // دی‌ان‌اس‌های اصلی که همیشه در صفحه اول هستند
  final List<String> premiumGamingDns = const [
    '78.157.42.100', '176.119.1.1', '10.202.10.10', '119.29.29.29',
    '223.5.5.5', '8.26.56.26', '209.244.0.3', '1.1.1.1', '8.8.8.8',
  ];

  // تفکر انتزاعی: آرشیو پنهان برای دور زدن فیلترینگ گیت‌هاب
  final List<String> _deepArchiveDns = const [
    '1.0.0.1', '8.8.4.4', '9.9.9.9', '149.112.112.112', '208.67.222.222',
    '208.67.220.220', '8.20.247.20', '94.140.14.14', '94.140.15.15',
    '78.157.42.101', '10.202.10.11', '176.119.1.2', '114.114.114.114',
    '1.2.4.8', '210.2.4.8', '77.88.8.8', '77.88.8.1', '185.228.168.9',
    '185.228.169.9', '198.101.242.72', '23.253.163.53', '176.103.130.130',
    '176.103.130.131', '185.51.200.2', '178.22.122.100', '194.36.174.161',
    '1.1.1.2', '1.0.0.2', '208.67.222.123', '208.67.220.123', '10.202.10.202'
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
    // استفاده از پروکسی‌های قدرتمند برای دور زدن مسدودیت گیت‌هاب
    return sources == null || sources.isEmpty
        ? const [
            'https://mirror.ghproxy.com/https://raw.githubusercontent.com/smokeme/Public-DNS-Collector/main/lists/ipv4.txt',
            'https://ghproxy.net/https://raw.githubusercontent.com/smokeme/Public-DNS-Collector/main/lists/ipv4.txt',
            'https://raw.gitmirror.com/smokeme/Public-DNS-Collector/main/lists/ipv4.txt',
            'https://cdn.jsdelivr.net/gh/smokeme/Public-DNS-Collector@main/lists/ipv4.txt'
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
    var newAdded = 0;
    bool atLeastOneSuccess = false;

    // تلاش برای نفوذ به گیت‌هاب
    for (final rawUrl in sources) {
      final url = rawUrl.trim();
      if (url.isEmpty) continue;
      try {
        final response = await http
            .get(Uri.parse(url), headers: const {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 5)); // تست سریع برای جلوگیری از گیر کردن برنامه
        
        if (response.statusCode == 200) {
          atLeastOneSuccess = true;
          for (final ip in extractIpsFromText(response.body)) {
            if (masterPool.add(ip)) newAdded++;
          }
        }
      } catch (_) {}
    }

    if (atLeastOneSuccess) {
      if (newAdded > 0) await saveMasterPool(masterPool.toList());
      return {'status': 'github_success', 'count': newAdded};
    }

    // اگر گیت‌هاب مسدود بود، تزریق دی‌ان‌اس از آرشیو پنهان به صورت رندوم
    int offlineAdded = 0;
    final random = Random();
    List<String> shuffledArchive = List.from(_deepArchiveDns)..shuffle(random);
    
    for (var ip in shuffledArchive) {
      if (masterPool.add(ip)) {
        offlineAdded++;
        if (offlineAdded >= 12) break; // هر بار ۱۲ سرور جدید آزاد می‌کند
      }
    }

    if (offlineAdded > 0) {
      await saveMasterPool(masterPool.toList());
      return {'status': 'offline_injected', 'count': offlineAdded};
    }

    return {'status': 'exhausted', 'count': 0};
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
