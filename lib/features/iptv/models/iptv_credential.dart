enum IptvLoginType { xtream, m3u }

class IptvCredential {
  final IptvLoginType type;
  final String? serverUrl;
  final String? username;
  final String? password;
  final String? m3uUrl;

  const IptvCredential({
    required this.type,
    this.serverUrl,
    this.username,
    this.password,
    this.m3uUrl,
  });

  /// Xtream constructor
  const IptvCredential.xtream({
    required String server,
    required String user,
    required String pass,
  })  : type = IptvLoginType.xtream,
        serverUrl = server,
        username = user,
        password = pass,
        m3uUrl = null;

  /// M3U constructor
  const IptvCredential.m3u({required String url})
      : type = IptvLoginType.m3u,
        m3uUrl = url,
        serverUrl = null,
        username = null,
        password = null;

  Map<String, dynamic> toJson() => {
        'type': type == IptvLoginType.xtream ? 'xtream' : 'm3u',
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'm3uUrl': m3uUrl,
      };

  factory IptvCredential.fromJson(Map<String, dynamic> json) {
    final type = json['type'] == 'xtream' ? IptvLoginType.xtream : IptvLoginType.m3u;
    return IptvCredential(
      type: type,
      serverUrl: json['serverUrl'],
      username: json['username'],
      password: json['password'],
      m3uUrl: json['m3uUrl'],
    );
  }
}
