import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// Fetches [uri] and returns its decoded JSON.
typedef WeatherFetcher = Future<Object?> Function(Uri uri);

/// Where a session's weather is.
enum SessionWeatherState {
  /// The recording has no time or no GPS fix, or the day keeps weather
  /// this app does not read.
  none,

  /// Weather lookup is off in settings.
  off,

  /// Waiting for, or asking, the weather service.
  fetching,

  /// Shown.
  ready,

  /// The service could not be reached or had nothing for the session.
  unavailable,
}

/// Asks the weather service over HTTPS; off in `flutter test`, where the
/// user guide's screenshot tool sets a recorded answer.
WeatherFetcher? defaultWeatherFetcher =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? null
    : fetchWeatherJson;

/// GETs [uri] and decodes its JSON, reading at most
/// [maximumOpenMeteoCharacters]. An error answer of the service (a JSON
/// object with its reason) is returned to be read as one.
Future<Object?> fetchWeatherJson(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'FlappedEar Telemetry';
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = StringBuffer();
    await for (final chunk
        in response
            .transform(utf8.decoder)
            .timeout(const Duration(seconds: 30))) {
      if (text.length + chunk.length > maximumOpenMeteoCharacters) {
        throw const HttpException('The weather answer is too long.');
      }
      text.write(chunk);
    }
    final Object? json;
    try {
      json = jsonDecode(text.toString());
    } on FormatException {
      throw HttpException(
        'The weather service answered ${response.statusCode}.',
      );
    }
    if (response.statusCode != HttpStatus.ok &&
        !(json is Map && json['error'] == true)) {
      throw HttpException(
        'The weather service answered ${response.statusCode}.',
      );
    }
    return json;
  } finally {
    client.close(force: true);
  }
}

/// The weather of a day's sessions: what the day's document keeps, and
/// what is fetched for sessions without it, one session at a time and only
/// while [enabled]. A failed lookup is not repeated until [retry] or the
/// day is opened again. The day's controller holds it and writes
/// [fetched] with the day.
final class DayWeather extends ChangeNotifier {
  DayWeather({this._fetcher, this._enabled, int Function()? clock})
    : _clock = clock ?? _now {
    _enabled?.addListener(_enabledChanged);
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  final WeatherFetcher? _fetcher;
  final ValueListenable<bool>? _enabled;
  final int Function() _clock;

  /// Called with a run id when its weather arrives.
  void Function(String runId)? onFetched;

  final Map<String, SessionWeather> _shown = {};
  final Map<String, SessionWeather> _fetched = {};
  final Map<String, SessionWeatherState> _states = {};
  // The recording each run's weather is wanted for, and what to ask.
  final Map<String, (String, WeatherRequest)> _wanted = {};
  // Runs whose lookup failed for that recording.
  final Map<String, String> _failed = {};
  final List<String> _queue = [];
  bool _running = false;
  bool _disposed = false;
  List<NamedRun> _runs = const [];
  List<Object?> _documentRuns = const [];

  bool get _on => _enabled?.value ?? true;

  /// [runId]'s weather, or null.
  SessionWeather? of(String runId) => _shown[runId];

  SessionWeatherState stateOf(String runId) =>
      _states[runId] ?? SessionWeatherState.none;

  /// The weather fetched here for the runs' current recordings, by run id:
  /// what the day's document does not hold yet.
  Map<String, SessionWeather> get fetched => Map.unmodifiable(_fetched);

  /// Whether any session shows weather (for the service's credit).
  bool get any => _shown.isNotEmpty;

  /// Takes the day's [runs] and the document's runs ([documentRuns]), and
  /// asks for the weather of sessions that have none for their recording.
  void sync(List<NamedRun> runs, List<Object?> documentRuns) {
    _runs = List.of(runs);
    _documentRuns = documentRuns;
    final stored = <String, Object?>{};
    final present = <String>{};
    for (final value in documentRuns) {
      if (value case final Map<String, Object?> run when run['id'] is String) {
        if (run.containsKey(sessionWeatherKey)) {
          present.add(run['id']! as String);
          stored[run['id']! as String] = run[sessionWeatherKey];
        }
      }
    }
    for (final named in runs) {
      final id = named.run.id;
      final revision = named.run.contentSha256;
      final fetched = _fetched[id];
      if (fetched != null && fetched.sourceRevision == revision) {
        _show(id, fetched);
        continue;
      }
      _fetched.remove(id);
      final saved = SessionWeather.fromJson(stored[id]);
      if (saved != null && saved.sourceRevision == revision) {
        _show(id, saved);
        continue;
      }
      _shown.remove(id);
      // Weather of a newer version is kept as it is, not replaced.
      if (saved == null && present.contains(id) && stored[id] != null) {
        _set(id, SessionWeatherState.none);
        continue;
      }
      if (_failed[id] == revision) {
        _set(id, SessionWeatherState.unavailable);
        continue;
      }
      final request = weatherRequest(named.run.telemetry);
      if (request == null || _fetcher == null) {
        _wanted.remove(id);
        _set(id, SessionWeatherState.none);
        continue;
      }
      _wanted[id] = (revision, request);
      if (!_on) {
        _set(id, SessionWeatherState.off);
        continue;
      }
      _set(id, SessionWeatherState.fetching);
      if (!_queue.contains(id)) _queue.add(id);
    }
    notifyListeners();
    unawaited(_next());
  }

  /// Asks again for [runId]'s weather after a failed lookup.
  void retry(String runId) {
    _failed.remove(runId);
    sync(_runs, _documentRuns);
  }

  void _show(String id, SessionWeather weather) {
    _shown[id] = weather;
    _wanted.remove(id);
    _set(id, SessionWeatherState.ready);
  }

  void _set(String id, SessionWeatherState state) => _states[id] = state;

  void _enabledChanged() {
    if (_disposed) return;
    if (_on) {
      sync(_runs, _documentRuns);
      return;
    }
    _queue.clear();
    for (final id in _wanted.keys) {
      if (_states[id] == SessionWeatherState.fetching) {
        _set(id, SessionWeatherState.off);
      }
    }
    notifyListeners();
  }

  Future<void> _next() async {
    final fetcher = _fetcher;
    if (_running || fetcher == null) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed && _on) {
        final id = _queue.removeAt(0);
        final wanted = _wanted[id];
        if (wanted == null) continue;
        final (revision, request) = wanted;
        SessionWeather? weather;
        try {
          weather = sessionWeatherFromOpenMeteo(
            await fetcher(request.openMeteoUri),
            request,
            sourceRevision: revision,
            fetchedMilliseconds: _clock(),
          );
        } on Exception catch (error) {
          debugPrint('Weather not fetched: $error');
        }
        if (_disposed) return;
        // The run's recording changed or the lookup was turned off meanwhile.
        if (_wanted[id]?.$1 != revision) continue;
        if (weather == null || weather.summary.isEmpty) {
          // Nothing for the session: not kept, so asked again next time
          // the day opens.
          _failed[id] = revision;
          _wanted.remove(id);
          _set(id, SessionWeatherState.unavailable);
          notifyListeners();
          continue;
        }
        _fetched[id] = weather;
        _show(id, weather);
        notifyListeners();
        onFetched?.call(id);
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _enabled?.removeListener(_enabledChanged);
    _queue.clear();
    super.dispose();
  }
}
