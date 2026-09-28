import 'dart:io';
import 'dart:math';
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

  final List<String> _deepArchiveDns = const [
    '1.0.0.1', '8.8.4.4', '9.9.9.9', '149.112.112.112', '208.67.222.222',
    '208.67.220.220', '8.20.247.20', '94.140.14.14', '94.140.15.15',
    '114.114.114.114', '1.2.4.8', '77.88.8.8', '185.228.168.9',
    '198.101.242.72', '23.253.163.53', '176.103.130.130', '185.51.200.2',
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

  // تکنیک انتزاعی تولید لینک‌های ضد تحریم برای هر مخزن گیت‌هاب
  List<String> generateMirrors(String repoPath) {
    final parts = repoPath.split('/');
    if(parts.length < 4) return [];
    final owner = parts[0];
    final repo = parts[1];
    final branch = parts[2];
    final path = parts.sublist(3).join('/');
    
    return [
      'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path',
      'https://fastly.jsdelivr.net/gh/$owner/$repo@$branch/$path',
      'https://raw.githack.com/$owner/$repo/$branch/$path',
      'https://ghproxy.com/https://raw.githubusercontent.com/$owner/$repo/$branch/$path',
      'https://mirror.ghproxy.com/https://raw.githubusercontent.com/$owner/$repo/$branch/$path',
      'https://cdn.statically.io/gh/$owner/$repo/$branch/$path',
      'https://raw.kkgithub.com/$owner/$repo/$branch/$path',
    ];
  }

  Future<void> saveSources(List<String> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sourcesKey, sources.toSet().toList());
  }

  Future<List<String>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_sourcesKey) ?? <String>[];
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
    final masterPool = (await loadMasterPool()).toSet();
    int initialSize = masterPool.length;
    bool atLeastOneSuccess = false;

    // لیست مخازن درخواستی شما (گیمینگ و عمومی)
    final repos = [
      'Luna-Dns/Luna-Dns/main/dns.txt',
      'public-dns/public-dns-directory/master/nameservers.txt',
      'smokeme/Public-DNS-Collector/main/lists/ipv4.txt'
    ];

    // حمله موازی به CDNها برای دور زدن فایروال
    for (final repo in repos) {
      final mirrors = generateMirrors(repo);
      for (final url in mirrors) {
        try {
          final response = await http
              .get(Uri.parse(url), headers: const {'User-Agent': 'Mozilla/5.0'})
              .timeout(const Duration(seconds: 8)); 
          
          if (response.statusCode == 200 && response.body.isNotEmpty) {
            final extracted = extractIpsFromText(response.body);
            if (extracted.isNotEmpty) {
              masterPool.addAll(extracted);
              atLeastOneSuccess = true;
              break; // به محض موفقیت در یک مخزن، دیگر نیازی به تست بقیه آینه‌ها نیست
            }
          }
        } catch (_) {
          // در صورت قطعی اینترنت، به صورت سایلنت به سراغ آینه بعدی می‌رود
        }
      }
    }

    // دریافت از لینک‌های اضافه‌شده دستی توسط کاربر
    final customSources = await loadSources();
    for (final url in customSources) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          masterPool.addAll(extractIpsFromText(response.body));
          atLeastOneSuccess = true;
        }
      } catch (_) {}
    }

    int newAdded = masterPool.length - initialSize;

    if (atLeastOneSuccess) {
      await saveMasterPool(masterPool.toList());
      return {'status': 'success', 'count': newAdded};
    }

    // تزریق آفلاین در صورت قطع کامل اینترنت
    int offlineAdded = 0;
    final random = Random();
    List<String> shuffledArchive = List.from(_deepArchiveDns)..shuffle(random);
    for (var ip in shuffledArchive) {
      if (masterPool.add(ip)) {
        offlineAdded++;
        if (offlineAdded >= 10) break;
      }
    }

    if (offlineAdded > 0) {
      await saveMasterPool(masterPool.toList());
      return {'status': 'offline_injected', 'count': offlineAdded};
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
