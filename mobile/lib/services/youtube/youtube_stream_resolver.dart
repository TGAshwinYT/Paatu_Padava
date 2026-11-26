part of '../youtube_client.dart';

Future<bool> _probeStreamUrlImpl(String url) async {
  if (url.isEmpty) return false;
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    final isGoogleVideo = host.contains('googlevideo.com');
    final isHls = url.contains('.m3u8') || url.contains('hls_variant');
    final Map<String, String> headers;
    if (isGoogleVideo) {
      final ua = YouTubeClient.userAgentForUrl(url);
      headers = isHls
          ? {'User-Agent': ua, 'Accept': '*/*'}
          : {'Range': 'bytes=0-1024', 'User-Agent': ua, 'Accept': '*/*'};
    } else {
      headers = {'Range': 'bytes=0-1024', 'Accept': '*/*'};
    }
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));
    final isValid = response.statusCode == 200 || response.statusCode == 206;
    if (!isValid) {
      AppLogger.log('YouTubeClient', 'Stream probe rejected URL: HTTP ${response.statusCode} for $url');
    }
    return isValid;
  } catch (e) {
    AppLogger.log('YouTubeClient', 'Stream probe network/timeout error: $e');
    return false;
  }
}

Future<String?> _resolveDirectInnertubeStreamImpl(String cleanId) async {
  final configs = InnerTubeConfigService.healthyClientConfigs;
  if (configs.isEmpty) return null;

  final futures = configs.map((config) async {
    try {
      final uri = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');
      final payload = jsonEncode({
        'context': {'client': config['client']},
        'videoId': cleanId,
      });

      final response = await http
          .post(uri, headers: Map<String, String>.from(config['headers']), body: payload)
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 403 ||
          response.body.contains('LOGIN_REQUIRED') ||
          response.body.contains("Sign in to confirm you're not a bot")) {
        final clientName = config['name']?.toString() ?? '';
        if (clientName.isNotEmpty) {
          final reason = response.statusCode == 403 ? 'HTTP 403 Forbidden' : 'Bot challenge / login required';
          DynamicScraperConfigService.reportClientFailure(clientName, reason);
        }
        return null;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        if (data == null) return null;

        final playability = data['playabilityStatus'] as Map<String, dynamic>?;
        final playStatus = playability?['status']?.toString() ?? '';
        if (playStatus == 'LOGIN_REQUIRED' ||
            playStatus == 'AGE_CHECK_REQUIRED' ||
            playStatus == 'AGE_VERIFICATION_REQUIRED' ||
            playStatus == 'UNPLAYABLE' ||
            playStatus == 'VIDEO_UNAVAILABLE' ||
            playStatus == 'ERROR') {
          final reason = playability?['reason']?.toString() ?? playStatus;
          YouTubeClient.markPermanentlyUnplayable(cleanId, reason);
          AppLogger.log('YouTubeClient',
              'InnerTube ${config['name']}: playabilityStatus=$playStatus ($reason) for $cleanId');
          return null;
        }

        final streamingData = data['streamingData'] as Map<String, dynamic>?;
        if (streamingData == null) return null;

        final hlsUrl = streamingData['hlsManifestUrl']?.toString();
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          AppLogger.log('YouTubeClient', 'Method A: Returned native HLS .m3u8 URL from ${config['name']} for $cleanId');
          return hlsUrl;
        }

        final formats = (streamingData['adaptiveFormats'] as List<dynamic>?) ?? [];
        final audioFormats = formats.where((f) {
          final mime = f['mimeType']?.toString().toLowerCase() ?? '';
          return mime.startsWith('audio/');
        }).toList();

        final candidateUrls = <String>[];
        String prepareStreamUrl(Map<dynamic, dynamic> f) => f['url']?.toString() ?? '';

        if (audioFormats.isNotEmpty) {
          final quality = SettingsManager.effectiveStreamingQuality;
          if (quality == '96kbps') {
            for (final f in audioFormats) {
              final bitrate = (f['bitrate'] as num?)?.toInt() ?? 0;
              if (bitrate > 0 && bitrate <= 100000) {
                final url = prepareStreamUrl(f);
                if (url.isNotEmpty && !candidateUrls.contains(url)) candidateUrls.add(url);
              }
            }
          }
          for (final tag in [140, 251, 250, 249]) {
            for (final f in audioFormats) {
              if (f['itag'] == tag) {
                final url = prepareStreamUrl(f);
                if (url.isNotEmpty && !candidateUrls.contains(url)) candidateUrls.add(url);
              }
            }
          }
          final sorted = List.from(audioFormats)
            ..sort((a, b) => ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0));
          for (final f in sorted) {
            final url = prepareStreamUrl(f);
            if (url.isNotEmpty && !candidateUrls.contains(url)) candidateUrls.add(url);
          }
        }

        for (final candidate in candidateUrls.take(2)) {
          if (await _probeStreamUrlImpl(candidate)) {
            AppLogger.log('YouTubeClient', 'InnerTube ${config['name']} direct stream verified for $cleanId');
            return candidate;
          }
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'InnerTube ${config['name']} direct resolution notice for $cleanId: $e');
    }
    return null;
  });

  try {
    final results = await Future.wait(futures).timeout(const Duration(milliseconds: 2500));
    for (final r in results) {
      if (r != null && r.isNotEmpty) return r;
    }
  } catch (e) {
    AppLogger.debug('YoutubeClient', 'Handled exception: $e');
  }
  return null;
}

Future<String?> _resolveAndVerifyStreamImpl(String cleanId) async {
  if (YouTubeClient.isKnownUnplayable(cleanId)) {
    AppLogger.log('YouTubeClient',
        'Skipping stream resolution for $cleanId — permanently unplayable (${YouTubeClient.unplayableReason(cleanId)}).');
    return null;
  }

  try {
    final directUrl = await _resolveDirectInnertubeStreamImpl(cleanId)
        .timeout(const Duration(milliseconds: 2500), onTimeout: () => null);
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;
  } catch (e) {
    AppLogger.debug('YoutubeClient', 'Handled exception: $e');
  }

  for (int attempt = 1; attempt <= 2; attempt++) {
    try {
      final manifest = await YouTubeClient._yt.videos.streamsClient
          .getManifest(cleanId)
          .timeout(const Duration(seconds: 22));

      final audioStreams = manifest.audioOnly;
      if (audioStreams.isNotEmpty) {
        final candidates = <AudioStreamInfo>[];
        final quality = SettingsManager.effectiveStreamingQuality;

        void addStream(AudioStreamInfo s) {
          if (!candidates.contains(s)) candidates.add(s);
        }

        if (quality == '96kbps') {
          for (final s in audioStreams) {
            if (s.bitrate.kiloBitsPerSecond <= 100) addStream(s);
          }
        }
        for (final tag in [140, 251, 250, 249]) {
          for (final s in audioStreams) {
            if (s.tag == tag) addStream(s);
          }
        }
        final sortedStreams = List<AudioStreamInfo>.from(audioStreams)
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
        for (final s in sortedStreams) {
          addStream(s);
        }

        for (final candidate in candidates) {
          final url = candidate.url.toString();
          if (await _probeStreamUrlImpl(url)) {
            AppLogger.log('YouTubeClient', 'YouTubeExplode stream verified for $cleanId (itag ${candidate.tag})');
            return url;
          }
        }

        if (manifest.muxed.isNotEmpty) {
          final sortedMuxed = List.from(manifest.muxed)..sort((a, b) => b.bitrate.compareTo(a.bitrate));
          for (final muxed in sortedMuxed) {
            final url = muxed.url.toString();
            if (await _probeStreamUrlImpl(url)) return url;
          }
        }
      }
    } catch (e) {
      AppLogger.log('YouTubeClient', 'YouTubeExplode attempt $attempt notice for $cleanId: $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('videounavailable') ||
          errStr.contains('videorequirespurchase') ||
          errStr.contains('videoprivated') ||
          errStr.contains('unplayable')) {
        YouTubeClient.markPermanentlyUnplayable(cleanId, e.toString());
        break;
      }
      if (e.toString().contains('HttpClientClosedException')) {
        YouTubeClient.refreshClient();
      }
    }
  }
  return null;
}
