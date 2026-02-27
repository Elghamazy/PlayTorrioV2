import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../api/tmdb_api.dart';
import '../api/stream_extractor.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../api/stream_providers.dart';
import '../api/debrid_api.dart';
import '../api/torr_server_service.dart';
import '../utils/app_theme.dart';
import '../widgets/loading_overlay.dart';
import 'player_screen.dart';

class StreamingDetailsScreen extends StatefulWidget {
  final Movie movie;

  const StreamingDetailsScreen({super.key, required this.movie});

  @override
  State<StreamingDetailsScreen> createState() => _StreamingDetailsScreenState();
}

class _StreamingDetailsScreenState extends State<StreamingDetailsScreen> {
  bool _isExtracting = false;
  String? _statusMessage;
  final StreamExtractor _extractor = StreamExtractor();
  final SettingsService _settings = SettingsService();
  final StremioService _stremio = StremioService();
  final TmdbApi _api = TmdbApi();
  late Movie _movie;
  bool _isLoading = true;

  // Source Selection
  String _selectedSourceId = 'playtorrio';
  List<Map<String, dynamic>> _streamAddons = [];
  List<dynamic> _stremioStreams = [];
  bool _isStremioFetching = false;

  // TV State
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  Map<String, dynamic>? _seasonData;
  bool _isLoadingSeason = false;
  
  final ScrollController _episodeScrollController = ScrollController();
  final ScrollController _seasonScrollController = ScrollController();

  final Map<String, dynamic> _providers = StreamProviders.providers;

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final Movie fullDetails;
      if (_movie.mediaType == 'tv') {
        fullDetails = await _api.getTvDetails(widget.movie.id);
        await _fetchSeason(1);
      } else {
        fullDetails = await _api.getMovieDetails(widget.movie.id);
      }

      // Fetch addons that support "stream"
      final streamAddons = await _stremio.getAddonsForResource('stream');
      
      if (mounted) {
        setState(() {
          _movie = fullDetails;
          _streamAddons = streamAddons;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSeason(int seasonNumber) async {
    setState(() => _isLoadingSeason = true);
    try {
      final data = await _api.getTvSeasonDetails(_movie.id, seasonNumber);
      if (mounted) {
        setState(() {
          _seasonData = data;
          _isLoadingSeason = false;
          _selectedSeason = seasonNumber;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSeason = false);
    }
  }

  @override
  void dispose() {
    _extractor.dispose();
    _episodeScrollController.dispose();
    _seasonScrollController.dispose();
    super.dispose();
  }

  Future<void> _startExtraction() async {
    if (_selectedSourceId == 'playtorrio') {
      _startPlayTorrioExtraction();
    } else {
      _startStremioExtraction();
    }
  }

  Future<void> _startStremioExtraction() async {
    final addon = _streamAddons.firstWhere((a) => a['baseUrl'] == _selectedSourceId);
    final baseUrl = addon['baseUrl'];
    
    setState(() {
      _isStremioFetching = true;
      _stremioStreams = [];
      _statusMessage = 'Fetching from ${addon['name']}...';
    });

    try {
      String stremioId = _movie.imdbId ?? '';
      if (_movie.mediaType == 'tv') {
        stremioId = '$stremioId:$_selectedSeason:$_selectedEpisode';
      }

      final type = _movie.mediaType == 'tv' ? 'series' : 'movie';
      final streams = await _stremio.getStreams(baseUrl: baseUrl, type: type, id: stremioId);

      if (mounted) {
        setState(() {
          _stremioStreams = streams;
          if (streams.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No streams found for this content.')));
          }
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isStremioFetching = false);
    }
  }

  void _playStremioStream(Map<String, dynamic> stream) async {
    final useDebrid = await _settings.useDebridForStreams();
    final debridService = await _settings.getDebridService();

    if (stream['url'] != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            streamUrl: stream['url'],
            title: _movie.title,
            headers: Map<String, String>.from(stream['behaviorHints']?['proxyHeaders']?['request'] ?? {}),
            movie: _movie,
            selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
            selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
          ),
        ),
      );
    } else if (stream['infoHash'] != null) {
      final hash = stream['infoHash'];
      final magnet = 'magnet:?xt=urn:btih:$hash';
      
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black,
        builder: (context) => LoadingOverlay(
          movie: _movie,
          message: useDebrid && debridService != 'None' 
              ? 'Resolving with $debridService...' 
              : 'Starting Torrent Engine...',
        ),
      );

      String? finalStreamUrl;

      try {
        if (useDebrid && debridService != 'None') {
          final debrid = DebridApi();
          List<DebridFile> files;
          if (debridService == 'Real-Debrid') {
            files = await debrid.resolveRealDebrid(magnet);
          } else {
            files = await debrid.resolveTorBox(magnet);
          }

          if (files.isNotEmpty) {
            if (_movie.mediaType == 'tv') {
              final seasonStr = 'S${_selectedSeason.toString().padLeft(2, '0')}';
              final episodeStr = 'E${_selectedEpisode.toString().padLeft(2, '0')}';
              final match = files.where((f) => 
                f.filename.toUpperCase().contains(seasonStr) && 
                f.filename.toUpperCase().contains(episodeStr)
              ).toList();
              
              if (match.isNotEmpty) {
                finalStreamUrl = match.first.downloadUrl;
              } else {
                files.sort((a, b) => b.filesize.compareTo(a.filesize));
                finalStreamUrl = files.first.downloadUrl;
              }
            } else {
              files.sort((a, b) => b.filesize.compareTo(a.filesize));
              finalStreamUrl = files.first.downloadUrl;
            }
          }
        } else {
          final service = TorrServerService();
          await service.start();
          finalStreamUrl = await service.streamTorrent(
            magnet,
            season: _movie.mediaType == 'tv' ? _selectedSeason : null,
            episode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
          );
        }
      } catch (e) {
        debugPrint('Stremio Hash Resolution Error: $e');
      }

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Close overlay
      }

      if (mounted && finalStreamUrl != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              streamUrl: finalStreamUrl!,
              title: _movie.title,
              magnetLink: magnet,
              movie: _movie,
              selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
              selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
            ),
          ),
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to resolve Stremio torrent.')));
      }
    }
  }

  Future<void> _startPlayTorrioExtraction() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      builder: (context) => LoadingOverlay(movie: _movie),
    );

    setState(() {
      _isExtracting = true;
      _statusMessage = 'Initializing Stream Extractor...';
    });

    bool found = false;

    // ── Try Amri first ──────────────────────────────────────────────────────
    try {
      setState(() => _statusMessage = 'Trying Amri.gg...');
      debugPrint('[StreamExtractor] Trying Amri provider');
      
      final amriResult = await _extractor.extractWithAmri(
        tmdbId: _movie.id.toString(),
        isMovie: _movie.mediaType != 'tv',
        season: _movie.mediaType == 'tv' ? _selectedSeason : null,
        episode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
      );
      
      debugPrint('[StreamExtractor] Amri result: ${amriResult != null ? "SUCCESS" : "NULL"}');
      
      if (amriResult != null) {
        debugPrint('[StreamExtractor] Amri URL: ${amriResult.url}');
        debugPrint('[StreamExtractor] Amri sources count: ${amriResult.sources?.length ?? 0}');
        
        found = true;
        if (mounted) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlayerScreen(
                streamUrl: amriResult.url,
                audioUrl: amriResult.audioUrl,
                title: _movie.mediaType == 'tv' 
                    ? '${_movie.title} - S$_selectedSeason E$_selectedEpisode' 
                    : _movie.title,
                headers: amriResult.headers,
                movie: _movie,
                providers: _providers,
                activeProvider: 'amri',
                selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
                selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
                sources: amriResult.sources,
              ),
            ),
          );
        }
        setState(() {
          _isExtracting = false;
          _statusMessage = null;
        });
        return;
      } else {
        debugPrint('[StreamExtractor] Amri returned null, falling back');
      }
    } catch (e) {
      debugPrint('[Amri] Error: $e');
    }

    // ── Fallback to other providers ─────────────────────────────────────────
    final providerKeys = _providers.keys.toList();

    for (var key in providerKeys) {
      if (!mounted) break;
      
      final provider = _providers[key];
      final String url;
      if (_movie.mediaType == 'tv') {
        url = provider['tv'](
          widget.movie.id.toString(),
          _selectedSeason.toString(),
          _selectedEpisode.toString(),
        );
      } else {
        url = provider['movie'](widget.movie.id.toString());
      }
      
      setState(() => _statusMessage = 'Searching ${provider['name']}...');
      debugPrint('[StreamExtractor] Trying ${provider['name']} source: $url');

      try {
        var result = await _extractor.extract(url, timeout: const Duration(seconds: 5));
        if (result != null) {
          found = true;
          if (mounted) {
            if (Navigator.canPop(context)) Navigator.pop(context); // Close loading overlay
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlayerScreen(
                  streamUrl: result.url,
                  audioUrl: result.audioUrl,
                  title: _movie.mediaType == 'tv' 
                      ? '${_movie.title} - S$_selectedSeason E$_selectedEpisode' 
                      : _movie.title,
                  headers: result.headers,
                  movie: _movie,
                  providers: _providers,
                  activeProvider: key,
                  selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
                  selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
                ),
              ),
            );
          }
          break;
        }
      } catch (e) {
        debugPrint('Error extracting from $key: $e');
      }
    }

    if (mounted) {
      if (!found && Navigator.canPop(context)) Navigator.pop(context); // Close loading overlay on failure
      setState(() {
        _isExtracting = false;
        _statusMessage = found ? null : 'No streams found. Try again later.';
      });
      if (!found) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to find a working stream.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: AppTheme.backgroundDecoration,
          child: const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent && _movie.mediaType == 'tv' && _seasonData != null) {
          final episodes = _seasonData!['episodes'] as List?;
          if (episodes == null || episodes.isEmpty) return;
          
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // Previous episode
            if (_selectedEpisode > 1) {
              setState(() => _selectedEpisode--);
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            // Next episode
            if (_selectedEpisode < episodes.length) {
              setState(() => _selectedEpisode++);
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            // Previous season
            if (_selectedSeason > 1) {
              _fetchSeason(_selectedSeason - 1);
              setState(() => _selectedEpisode = 1);
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            // Next season
            if (_selectedSeason < _movie.numberOfSeasons) {
              _fetchSeason(_selectedSeason + 1);
              setState(() => _selectedEpisode = 1);
            }
          } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select) {
            // Play selected episode
            if (!_isExtracting) {
              _startExtraction();
            }
          }
        } else if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
          // Play movie
          if (!_isExtracting) {
            _startExtraction();
          }
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: FocusableControl(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: 50,
              child: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ),
        body: Container(
          decoration: AppTheme.backgroundDecoration,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.3,
                  child: CachedNetworkImage(
                    imageUrl: TmdbApi.getImageUrl(_movie.posterPath),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xFF0F0F2D), Color(0xFF000000)],
                      stops: [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Hero(
                            tag: 'movie-poster-${_movie.id}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: CachedNetworkImage(
                                imageUrl: TmdbApi.getImageUrl(_movie.posterPath),
                                height: isMobile ? 300 : 450,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          Text(
                            _movie.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.primaryColor),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_sync, color: AppTheme.primaryColor, size: 20),
                                SizedBox(width: 8),
                                Text('Direct Streaming Mode', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 32),

                          if (_movie.mediaType == 'tv') ...[
                            _buildSeasonSelector(),
                            const SizedBox(height: 16),
                            _buildEpisodeSelector(),
                            const SizedBox(height: 16),
                            const Text(
                              '← → Navigate Episodes  |  ↑ ↓ Change Season  |  Enter to Play',
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                          ],

                          _buildSourceSelector(),
                          const SizedBox(height: 32),

                          if (_selectedSourceId == 'playtorrio')
                            _buildPlayTorrioButton()
                          else if (_isStremioFetching)
                            const Column(
                              children: [
                                CircularProgressIndicator(color: AppTheme.primaryColor),
                                SizedBox(height: 16),
                                Text('Fetching from Addon...', style: TextStyle(color: Colors.white70)),
                              ],
                            )
                          else
                            _buildStremioStreamList(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayTorrioButton() {
    if (_isExtracting) {
      return Column(
        children: [
          const CircularProgressIndicator(color: AppTheme.primaryColor),
          const SizedBox(height: 16),
          Text(_statusMessage ?? 'Processing...', style: const TextStyle(color: Colors.white70)),
        ],
      );
    }
    return FocusableControl(
      onTap: _startExtraction,
      borderRadius: 16,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 32, color: Colors.white),
            const SizedBox(width: 12),
            const Text('Play Now', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildStremioStreamList() {
    if (_stremioStreams.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _stremioStreams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final s = _stremioStreams[index];
        final title = s['title'] ?? s['name'] ?? 'Unknown Stream';
        final description = s['description'] ?? '';

        return FocusableControl(
          onTap: () => _playStremioStream(s),
          borderRadius: 12,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.extension, color: AppTheme.primaryColor, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title, 
                        maxLines: 4, 
                        overflow: TextOverflow.visible, 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, height: 1.3),
                      ),
                      if (description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white38)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SOURCE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButton<String>(
            value: _selectedSourceId,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: const Color(0xFF1A0B2E),
            items: [
              const DropdownMenuItem(
                value: 'playtorrio',
                child: Row(
                  children: [
                    Icon(Icons.play_circle_filled, color: AppTheme.primaryColor, size: 20),
                    SizedBox(width: 12),
                    Text('PlayTorrio (Default)', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              ..._streamAddons.map((addon) => DropdownMenuItem(
                value: addon['baseUrl'],
                child: Row(
                  children: [
                    const Icon(Icons.extension, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 12),
                    Text(addon['name'], style: const TextStyle(color: Colors.white)),
                  ],
                ),
              )),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedSourceId = val);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeasonSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('SEASONS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white54)),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 20),
                  onPressed: () {
                    _seasonScrollController.animateTo(
                      _seasonScrollController.offset - 150,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
                  onPressed: () {
                    _seasonScrollController.animateTo(
                      _seasonScrollController.offset + 150,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: ListView.separated(
            controller: _seasonScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: _movie.numberOfSeasons,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final seasonNum = index + 1;
              final isSelected = _selectedSeason == seasonNum;
              return FocusableControl(
                onTap: () => _fetchSeason(seasonNum),
                borderRadius: 25,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor : Colors.white10,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    'Season $seasonNum',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeSelector() {
    if (_isLoadingSeason) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor));
    if (_seasonData == null || _seasonData!['episodes'] == null) return const SizedBox.shrink();

    final episodes = _seasonData!['episodes'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('EPISODES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white54)),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 20),
                  onPressed: () {
                    _episodeScrollController.animateTo(
                      _episodeScrollController.offset - 250,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
                  onPressed: () {
                    _episodeScrollController.animateTo(
                      _episodeScrollController.offset + 250,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView.separated(
            controller: _episodeScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: episodes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final ep = episodes[index];
              final epNum = ep['episode_number'];
              final isSelected = _selectedEpisode == epNum;
              return FocusableControl(
                onTap: () => setState(() => _selectedEpisode = epNum),
                borderRadius: 12,
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? AppTheme.primaryColor : Colors.transparent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                          child: ep['still_path'] != null 
                            ? CachedNetworkImage(imageUrl: TmdbApi.getImageUrl(ep['still_path']), fit: BoxFit.cover, width: double.infinity)
                            : Container(color: Colors.black26, child: const Center(child: Icon(Icons.movie, color: Colors.white24))),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('E${ep['episode_number']}', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(ep['name'] ?? 'Episode ${ep['episode_number']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
