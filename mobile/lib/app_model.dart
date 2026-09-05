import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'core.dart';
import 'realtime.dart';

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
  Timer? _visionTimer;
  bool _observing = false, _disposed = false;
  img.Image? _previous;
  String _scene = '';
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

  Future<void> saveSettings(String newKey, String newVoice) async {
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
      _generation++;
      await live.stop();
    } else {
      try {
        await live.start(messages);
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

  Future<void> newChat() async {
    _generation++;
    await live.stop();
    messages.clear();
    error = '';
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
      final selected =
          choices
              .where((c) => c.lensDirection == CameraLensDirection.front)
              .firstOrNull ??
          choices.first;
      next = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await next.initialize();
      if (token != _cameraGeneration) {
        await next.dispose();
        return;
      }
      camera = next;
      _previous = null;
      _scene = '';
      visionStatus = 'Vista automatica pronta';
      _visionTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(observe()),
      );
      unawaited(observe());
    } catch (e) {
      await next?.dispose();
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

  Future<Uint8List?> snapshot() async {
    final current = camera;
    if (!watching ||
        current == null ||
        !current.value.isInitialized ||
        current.value.isTakingPicture) {
      return null;
    }
    final token = _cameraGeneration;
    final shot = await current.takePicture();
    try {
      final bytes = await shot.readAsBytes();
      if (token != _cameraGeneration) return null;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final scaled = decoded.width > decoded.height
          ? img.copyResize(decoded, width: 768)
          : img.copyResize(decoded, height: 768);
      return Uint8List.fromList(img.encodeJpg(scaled, quality: 72));
    } finally {
      try {
        await File(shot.path).delete();
      } catch (_) {}
    }
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
    if (!live.active &&
        DateTime.now().difference(_lastAnalysis) < const Duration(seconds: 15)) {
      return;
    }
    _observing = true;
    final token = _cameraGeneration;
    try {
      final photo = await snapshot();
      if (photo == null || token != _cameraGeneration) return;
      final decoded = img.decodeImage(photo)!;
      final tiny = img.copyResize(decoded, width: 16, height: 16);
      double difference = 255;
      if (_previous != null) {
        double sum = 0;
        for (var y = 0; y < 16; y++) {
          for (var x = 0; x < 16; x++) {
            sum +=
                (tiny.getPixel(x, y).luminance -
                        _previous!.getPixel(x, y).luminance)
                    .abs();
          }
        }
        difference = sum / 256;
      }
      // Periodic refresh avoids indefinitely stale context after small movements.
      if (difference < 7 &&
          DateTime.now().difference(_lastAnalysis) <
              const Duration(seconds: 30)) {
        visionStatus = 'Vista attiva • scena stabile';
        return;
      }
      _previous = tiny;
      _lastAnalysis = DateTime.now();
      visionStatus = 'Invio una nuova immagine a OpenAI';
      refresh();
      if (live.active) {
        live.observe(photo);
      } else {
        final response = await api.respond(
          'Descrivi in una frase i cambiamenti visibili rispetto a: $_scene. Se invariato rispondi solo INVARIATO.',
          '',
          photo: photo,
          visionOnly: true,
        );
        if (token != _cameraGeneration) return;
        if (response.trim() != 'INVARIATO') {
          _scene = response;
          add('assistant', 'Vista automatica\n$response');
        }
      }
      visionStatus =
          'Vista aggiornata • ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    } catch (_) {
      if (token == _cameraGeneration) {
        visionStatus = 'Vista in pausa: riprova con la fotocamera';
        _visionTimer?.cancel();
      }
    } finally {
      _observing = false;
      refresh();
    }
  }

  void setWatching(bool value) {
    watching = value;
    if (!value) live.clearObservation();
    _previous = null;
    visionStatus = value ? 'Vista automatica pronta' : 'Solo anteprima locale';
    refresh();
  }

  Future<void> stopCamera() async {
    _cameraGeneration++;
    _visionTimer?.cancel();
    _visionTimer = null;
    final current = camera;
    camera = null;
    cameraStarting = false;
    live.clearObservation();
    visionStatus = 'Fotocamera spenta';
    refresh();
    await current?.dispose();
  }

  Future<void> shutdown() async {
    _generation++;
    await live.stop();
    await stopCamera();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    api.client.close();
    super.dispose();
  }
}
