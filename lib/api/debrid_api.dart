import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class DebridFile {
  final String filename;
  final int filesize;
  final String downloadUrl;

  DebridFile({required this.filename, required this.filesize, required this.downloadUrl});
}

class DebridApi {
  static final DebridApi _instance = DebridApi._internal();
  factory DebridApi() => _instance;
  DebridApi._internal();

  final _storage = const FlutterSecureStorage();
  final String _rdClientId = "X245A4XAIBGVM";

  // --- Real-Debrid OAuth ---

  Future<Map<String, dynamic>?> startRDLogin() async {
    final url = 'https://api.real-debrid.com/oauth/v2/device/code?client_id=$_rdClientId&new_credentials=yes';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final verifyUrl = data['verification_url'];
      if (await canLaunchUrl(Uri.parse(verifyUrl))) {
        await launchUrl(Uri.parse(verifyUrl), mode: LaunchMode.externalApplication);
      }
      return data;
    }
    return null;
  }

  Future<bool> pollRDCredentials(String deviceCode) async {
    final url = 'https://api.real-debrid.com/oauth/v2/device/credentials?client_id=$_rdClientId&code=$deviceCode';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _storage.write(key: 'rd_client_id', value: data['client_id']);
      await _storage.write(key: 'rd_client_secret', value: data['client_secret']);
      
      // Now exchange for token
      return await _exchangeRDToken(deviceCode, data['client_id'], data['client_secret']);
    }
    return false;
  }

  Future<bool> _exchangeRDToken(String deviceCode, String clientId, String clientSecret) async {
    final url = 'https://api.real-debrid.com/oauth/v2/token';
    final response = await http.post(
      Uri.parse(url),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': deviceCode,
        'grant_type': 'http://oauth.net/grant_type/device/1.0',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _saveRDToken(data);
      return true;
    }
    return false;
  }

  Future<void> _saveRDToken(Map<String, dynamic> data) async {
    await _storage.write(key: 'rd_access_token', value: data['access_token']);
    await _storage.write(key: 'rd_refresh_token', value: data['refresh_token']);
    final expiry = DateTime.now().add(Duration(seconds: data['expires_in']));
    await _storage.write(key: 'rd_token_expiry', value: expiry.toIso8601String());
  }

  Future<String?> getRDAccessToken() async {
    final token = await _storage.read(key: 'rd_access_token');
    final expiryStr = await _storage.read(key: 'rd_token_expiry');
    
    if (token == null || expiryStr == null) return null;

    final expiry = DateTime.parse(expiryStr);
    if (DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 5)))) {
      // Refresh token logic here if needed
      return token; // For now return current
    }
    return token;
  }

  Future<void> logoutRD() async {
    await _storage.delete(key: 'rd_access_token');
    await _storage.delete(key: 'rd_refresh_token');
    await _storage.delete(key: 'rd_token_expiry');
    await _storage.delete(key: 'rd_client_id');
    await _storage.delete(key: 'rd_client_secret');
  }

  // --- Real-Debrid Flow ---

  Future<List<DebridFile>> resolveRealDebrid(String magnet) async {
    final token = await getRDAccessToken();
    if (token == null) throw Exception("Real-Debrid not logged in");

    final headers = {'Authorization': 'Bearer $token'};

    // 1. Add Magnet
    final addRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/addMagnet'),
      headers: headers,
      body: {'magnet': magnet},
    );
    
    if (addRes.statusCode != 201) throw Exception("Failed to add magnet to RD");
    final torrentId = json.decode(addRes.body)['id'];

    // 2. Select all files
    await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
      headers: headers,
      body: {'files': 'all'},
    );

    // 3. Poll for status
    Map<String, dynamic>? info;
    int attempts = 0;
    while (attempts < 20) {
      final infoRes = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: headers,
      );
      info = json.decode(infoRes.body);
      if (info!['status'] == 'downloaded') break;
      if (info['status'] == 'error' || info['status'] == 'dead') throw Exception("RD Download failed");
      
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    if (info!['status'] != 'downloaded') throw Exception("RD Download timed out");

    // 4. Unrestrict links
    List<DebridFile> resolvedFiles = [];
    final List links = info['links'];
    for (final link in links) {
      final unRes = await http.post(
        Uri.parse('https://api.real-debrid.com/rest/1.0/unrestrict/link'),
        headers: headers,
        body: {'link': link},
      );
      final data = json.decode(unRes.body);
      resolvedFiles.add(DebridFile(
        filename: data['filename'],
        filesize: data['filesize'],
        downloadUrl: data['download'],
      ));
    }

    return resolvedFiles;
  }

  // --- TorBox Flow ---

  Future<void> saveTorBoxKey(String key) async {
    await _storage.write(key: 'torbox_api_key', value: key);
  }

  Future<String?> getTorBoxKey() async {
    return await _storage.read(key: 'torbox_api_key');
  }

  Future<List<DebridFile>> resolveTorBox(String magnet) async {
    final apiKey = await getTorBoxKey();
    if (apiKey == null) throw Exception("TorBox API Key not set");

    final headers = {'Authorization': 'Bearer $apiKey'};

    // 1. Create Torrent
    final createRes = await http.post(
      Uri.parse('https://api.torbox.app/v1/api/torrents/createtorrent'),
      headers: headers,
      body: {'magnet': magnet},
    );
    
    final createData = json.decode(createRes.body);
    if (createData['success'] == false) throw Exception("TorBox failed: ${createData['detail']}");
    
    final torrentId = createData['data']['torrent_id'];

    // 2. Poll status
    Map<String, dynamic>? info;
    int attempts = 0;
    while (attempts < 20) {
      final infoRes = await http.get(
        Uri.parse('https://api.torbox.app/v1/api/torrents/mylist?id=$torrentId&bypass_cache=true'),
        headers: headers,
      );
      final mylist = json.decode(infoRes.body)['data'];
      // TorBox returns a single object if ID is provided
      info = mylist;
      if (info!['download_finished'] == true || info['download_state'] == 'cached') break;
      if (info['download_state'] == 'error') throw Exception("TorBox Download failed");
      
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    // 3. Get Redirect Permalinks
    List<DebridFile> resolvedFiles = [];
    final List files = info!['files'];
    for (final file in files) {
      final permalink = 'https://api.torbox.app/v1/api/torrents/requestdl?token=$apiKey&torrent_id=$torrentId&file_id=${file['id']}&redirect=true';
      resolvedFiles.add(DebridFile(
        filename: file['name'],
        filesize: file['size'],
        downloadUrl: permalink,
      ));
    }

    return resolvedFiles;
  }
}
