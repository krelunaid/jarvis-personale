import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'video_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'core.dart';
import 'realtime.dart';
import 'vision.dart';

class SecureLocalStore implements LocalStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
}

class AppModel extends ChangeNotifier {
  final LocalStore store;
  late final Memories memory;
  late final OpenAI api;
  late final Realtime live;
  final List<ChatEntry> messages = [];
  CameraController? camera;
  bool ready = false, busy = false, cameraStarting = false, watching = true;
  String error = '', visionStatus = 'Fotocamera spenta', voice = 'cedar';
  int _generation = 0, _cameraGeneration = 0;
  CameraLensDirection lensDirection = CameraLensDirection.front;
  int cameraCount = 0;
  Uint8List? _latestFrame;
  List<double>? _latestHint;
  List<double>? _previousHint;
  DateTime? _frameTime;
  bool _convertingFrame = false;
  DateTime _lastFrameAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _observing = false, _disposed = false;
  VideoFrame? _pendingPacket;
  int _pendingToken = 0;
  String _scene = '';
  bool continueWhenLocked = true;
  bool get supportsBackgroundVoice =>
      defaultTargetPlatform == TargetPlatform.iOS;
  AppModel({LocalStore? storage, http.Client? client})
    : store = storage ?? SecureLocalStore() {
    memory = Memories(store);
    api = OpenAI(client ?? http.Client());
    live = Realtime(api, memory, refresh, upsert, (query, search) async {
      final token = _generation;
      final photo = search ? null : await snapshot();
      final result = await api.respond(
        query,
        memory.context,
        history: List.of(messages),
        photo: photo,
        search: search,
      );
      if (token != _generation || !live.active) {
        throw JarvisError('Operazione interrotta.');
      }
      add(
        'assistant',
        '${search ? 'Ricerca web' : 'Approfondimento • modello potente'}\n\n$result',
      );
      return result;
    });
  }
  void refresh() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      await memory.load();
      continueWhenLocked = await store.read('continue_when_locked') != 'false';
      api.key = await store.read('openai_key') ?? '';
      final saved = await store.read('voice');
      if (voices.contains(saved)) voice = saved!;
      live.voice = voice;
    } catch (_) {
      error =
          'Non riesco a leggere i dati protetti. Non sono stati cancellati. Riprova.';
    }
    ready = true;
    refresh();
  }

  Future<void> saveSettings(
    String newKey,
    String newVoice, {
    bool? backgroundVoice,
  }) async {
    if (backgroundVoice != null) {
      await store.write('continue_when_locked', backgroundVoice.toString());
      continueWhenLocked = backgroundVoice;
    }
    if (newKey.trim().isNotEmpty) {
      await store.write('openai_key', newKey.trim());
      api.key = newKey.trim();
    }
    await store.write('voice', newVoice);
    voice = newVoice;
    live.voice = voice;
    refresh();
  }

  Future<void> forgetKey() async {
    await shutdown();
    await store.write('openai_key', '');
    api.key = '';
    refresh();
  }

  void add(String role, String text) {
    upsert(DateTime.now().microsecondsSinceEpoch.toString(), role, text);
  }

  void upsert(String id, String role, String text) {
    final found = messages.where((m) => m.id == id).firstOrNull;
    if (found == null) {
      messages.add(ChatEntry(id, role, text));
    } else {
      found.text = text;
    }
    if (messages.length > 200) messages.removeRange(0, messages.length - 200);
    refresh();
  }

  Future<void> remember(String text) async {
    try {
      final result = await memory.remember(text);
      live.updateMemory();
      add('assistant', result);
    } catch (e) {
      error = e.toString();
      refresh();
    }
  }

  Future<void> editMemory(List<String> notes) async {
    await memory.replace(notes);
    live.updateMemory();
    refresh();
  }

  Future<void> importMemory(String text) async {
    await memory.importText(text);
    live.updateMemory();
    refresh();
  }

  Future<void> startStop() async {
    error = '';
    if (live.active || live.connecting) {
      await newChat();
    } else {
      try {
        if (api.key.isNotEmpty) _clearConversation();
        await live.start();
      } catch (e) {
        error = e.toString();
      }
    }
    refresh();
  }

  Future<void> send(String text) async {
    if (busy || text.trim().isEmpty) return;
    if (live.active) {
      live.sayText(text, photo: await snapshot());
      return;
    }
    final note = Memories.command(text);
    if (note != null) {
      add('user', text);
      await remember(note);
      return;
    }
    if (api.key.isEmpty) {
      error = 'Apri Impostazioni e inserisci la tua chiave API.';
      refresh();
      return;
    }
    busy = true;
    error = '';
    final token = _generation;
    final history = List<ChatEntry>.of(messages);
    add('user', text);
    try {
      final result = await api.respond(
        text,
        memory.context,
        history: history,
        photo: await snapshot(),
      );
      if (token == _generation) add('assistant', result);
    } catch (e) {
      if (token == _generation) {
        error = e is JarvisError
            ? e.message
            : 'Connessione non riuscita. Riprova.';
      }
    } finally {
      busy = false;
      refresh();
    }
  }

  void _clearConversation() {
    _generation++;
    messages.clear();
    _scene = '';
    _previousHint = null;
    error = '';
    refresh();
  }

  Future<void> newChat() async {
    _clearConversation();
    final cameraStopped = stopCamera();
    await live.stop();
    await cameraStopped;
    refresh();
  }

  Future<void> toggleCamera() async {
    if (camera != null || cameraStarting) {
      await stopCamera();
      return;
    }
    final token = ++_cameraGeneration;
    cameraStarting = true;
    error = '';
    refresh();
    CameraController? next;
    try {
      final choices = await availableCameras();
      if (choices.isEmpty) throw JarvisError('Nessuna fotocamera disponibile.');
      cameraCount = choices.length;
      final selected =
          choices.where((c) => c.lensDirection == lensDirection).firstOrNull ??
          choices.first;
      next = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await next.initialize();
      if (token != _cameraGeneration) {
        await next.dispose();
        return;
      }
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (token != _cameraGeneration) {
        await next.dispose();
        return;
      }
      camera = next;
      lensDirection = selected.lensDirection;
      _previousHint = null;
      _latestHint = null;
      _scene = '';
      visionStatus = 'Avvio flusso fotocamera…';
      final rotation = Platform.isIOS ? 0 : selected.sensorOrientation;
      await next.startImageStream(
        (frame) => _acceptFrame(frame, token, rotation),
      );
    } catch (e) {
      await next?.dispose();
      if (token == _cameraGeneration) camera = null;
      if (token == _cameraGeneration) {
        error = e is JarvisError
            ? e.message
            : 'Fotocamera non disponibile. Controlla il permesso nelle impostazioni del telefono.';
      }
    } finally {
      if (token == _cameraGeneration) {
        cameraStarting = false;
        refresh();
      }
    }
  }

  Future<void> switchCamera() async {
    if (cameraStarting || cameraCount < 2) return;
    await stopCamera();
    lensDirection = lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    await toggleCamera();
  }

  VideoFrame _copyFrame(CameraImage frame, int rotation) {
    return VideoFrame(
      frame.width,
      frame.height,
      frame.format.group == ImageFormatGroup.bgra8888,
      frame.planes.map((p) => Uint8List.fromList(p.bytes)).toList(),
      frame.planes.map((p) => p.bytesPerRow).toList(),
      frame.planes
          .map(
            (p) =>
                p.bytesPerPixel ??
                (frame.format.group == ImageFormatGroup.bgra8888 ? 4 : 1),
          )
          .toList(),
      rotation: rotation,
    );
  }

  void _acceptFrame(CameraImage frame, int token, int rotation) {
    if (token != _cameraGeneration || !watching) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAttempt) < VisionPace.acceptGap) return;
    _lastFrameAttempt = now;
    final packet = _copyFrame(frame, rotation);
    if (_convertingFrame) {
      _pendingPacket = packet;
      _pendingToken = token;
      return;
    }
    _encodeFrame(packet, token);
  }

  void _encodeFrame(VideoFrame packet, int token) {
    _convertingFrame = true;
    unawaited(
      compute(encodeVisionFrame, packet)
          .then((encoded) {
            if (token != _cameraGeneration || !watching) return;
            _latestFrame = encoded.jpeg;
            _latestHint = encoded.hint;
            _frameTime = DateTime.now();
            live.latestPhoto = encoded.jpeg;
            unawaited(observe());
          })
          .catchError((Object _) {
            if (token == _cameraGeneration) {
              visionStatus =
                  'Immagine video non disponibile: riprovo automaticamente';
              refresh();
            }
          })
          .whenComplete(() {
            _convertingFrame = false;
            final pending = _pendingPacket;
            final pendingToken = _pendingToken;
            _pendingPacket = null;
            if (pending != null &&
                pendingToken == _cameraGeneration &&
                watching) {
              _encodeFrame(pending, pendingToken);
            }
          }),
    );
  }

  Future<Uint8List?> snapshot() async {
    if (!watching ||
        camera == null ||
        _frameTime == null ||
        DateTime.now().difference(_frameTime!) > VisionPace.snapshotFreshness) {
      return null;
    }
    return _latestFrame;
  }

  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> observe() async {
    if (_observing ||
        !watching ||
        camera == null ||
        api.key.isEmpty ||
        busy ||
        live.connecting) {
      return;
    }
    final now = DateTime.now();
    if (!VisionPace.readyToSend(
      live: live.active,
      last: _lastAnalysis,
      now: now,
    )) {
      return;
    }
    _observing = true;
    final token = _cameraGeneration;
    try {
      final photo = await snapshot();
      final hint = _latestHint;
      if (photo == null || hint == null || token != _cameraGeneration) return;
      final delta = compareHints(_previousHint, hint);
      // Refresh at least twice a second in live mode so a "still" scene cannot freeze.
      if (!VisionPace.sceneMoved(
        delta.mean,
        peak: delta.peak,
        live: live.active,
        last: _lastAnalysis,
        now: now,
      )) {
        visionStatus = 'Vista attiva • scena stabile';
        return;
      }
      visionStatus = 'Invio una nuova immagine a OpenAI';
      refresh();
      var sent = false;
      if (live.active) {
        sent = await live.observe(photo);
      } else {
        final response = await api.respond(
          'Descrivi in una frase i cambiamenti visibili rispetto a: $_scene. Se invariato rispondi solo INVARIATO.',
          '',
          photo: photo,
          visionOnly: true,
        );
        if (token != _cameraGeneration) return;
        sent = true;
        if (response.trim() != 'INVARIATO') {
          _scene = response;
          add('assistant', 'Vista automatica\n$response');
        }
      }
      if (!sent || token != _cameraGeneration || !watching) return;
      _previousHint = hint;
      _lastAnalysis = DateTime.now();
      visionStatus =
          'Vista aggiornata • ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    } catch (_) {
      if (token == _cameraGeneration) {
        visionStatus = 'Vista in pausa: riprova con la fotocamera';
      }
    } finally {
      _observing = false;
      refresh();
    }
  }

  void setWatching(bool value) {
    watching = value;
    if (!value) live.clearObservation();
    _previousHint = null;
    _latestHint = null;
    _latestFrame = null;
    live.latestPhoto = null;
    _pendingPacket = null;
    _frameTime = null;
    _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
    visionStatus = value ? 'Vista automatica pronta' : 'Solo anteprima locale';
    refresh();
  }

  Future<void> stopCamera() async {
    _cameraGeneration++;
    _latestFrame = null;
    _latestHint = null;
    _previousHint = null;
    live.latestPhoto = null;
    _pendingPacket = null;
    _frameTime = null;
    _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
    final current = camera;
    camera = null;
    cameraStarting = false;
    live.clearObservation();
    visionStatus = 'Fotocamera spenta';
    refresh();
    if (current != null) {
      try {
        if (current.value.isStreamingImages) await current.stopImageStream();
      } catch (_) {}
      await current.dispose();
    }
  }

  Future<void> enterBackground() async {
    final keepVoice =
        supportsBackgroundVoice && continueWhenLocked && live.active;
    // Cancel camera captures before awaiting disposal; never restart it silently.
    final cameraStopped = stopCamera();
    if (!keepVoice) {
      _clearConversation();
      await live.stop();
    }
    await cameraStopped;
  }

  Future<void> shutdown() => newChat();

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    api.client.close();
    super.dispose();
  }
}
