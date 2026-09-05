import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'core.dart';
import 'face_detect.dart';
import 'faces.dart';
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
  late final FaceBook faces;
  late final OpenAI api;
  late final Realtime live;
  final FaceFinder? _finder;
  final List<ChatEntry> messages = [];
  CameraController? camera;
  bool ready = false, busy = false, cameraStarting = false, watching = true;
  String error = '',
      visionStatus = 'Fotocamera spenta',
      voice = 'cedar',
      faceStatus = '';
  int _generation = 0, _cameraGeneration = 0;
  Timer? _visionTimer;
  bool _observing = false, _disposed = false;
  img.Image? _previous;
  String _scene = '';
  FaceFinder? _activeFinder;
  AppModel({LocalStore? storage, http.Client? client, this._finder})
    : store = storage ?? SecureLocalStore() {
    memory = Memories(store);
    faces = FaceBook(store);
    api = OpenAI(client ?? http.Client());
    live = Realtime(api, memory, faces, refresh, upsert, (query, search) async {
      final token = _generation;
      final frame = search ? null : await capture();
      final result = await api.respond(
        query,
        memory.context,
        history: List.of(messages),
        photo: frame?.photo,
        faceNote: frame?.note ?? '',
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
    }, enrollFromCamera);
  }

  FaceFinder get finder => _activeFinder ??= _finder ?? MlKitFaceFinder();
  void refresh() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      await memory.load();
      await faces.load();
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

  Future<void> forgetFace(String name) async {
    await faces.forget(name);
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
      final frame = await capture();
      live.sayText(text, photo: frame?.photo, faceNote: frame?.note ?? '');
      return;
    }
    final face = FaceBook.command(text);
    if (face != null) {
      add('user', text);
      await runFace(face);
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
      final frame = await capture();
      final result = await api.respond(
        text,
        memory.context,
        history: history,
        photo: frame?.photo,
        faceNote: frame?.note ?? '',
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

  Future<void> runFace(FaceCommand command) async {
    try {
      final result = switch (command.action) {
        'enroll' => await enrollFromCamera(command.name ?? ''),
        'forget' => await faces.forget(command.name ?? ''),
        _ => faces.listText(),
      };
      add('assistant', result);
    } catch (e) {
      error = e.toString();
      refresh();
    }
  }

  Future<String> enrollFromCamera(String name) async {
    final shot = await takeShot(force: true);
    if (shot == null) {
      throw JarvisError(
        'Accendi la fotocamera e inquadra un volto per iscriverlo.',
      );
    }
    try {
      final boxes = await finder.locate(shot.path);
      final usable = boxes.where((b) => !b.tiny).toList()
        ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
      if (usable.isEmpty) {
        throw JarvisError(
          'Non vedo un volto abbastanza vicino. Avvicinati e riprova.',
        );
      }
      final decoded = img.decodeImage(await shot.readAsBytes());
      if (decoded == null) {
        throw JarvisError('Immagine non leggibile. Riprova.');
      }
      final result = await faces.enroll(
        name,
        FacePrint.fromImage(decoded, usable.first),
      );
      faceStatus = usable.length > 1
          ? 'Iscritto il volto più grande come ${name.trim()}.'
          : 'Volto iscritto.';
      refresh();
      return result;
    } on JarvisError {
      rethrow;
    } catch (_) {
      throw JarvisError(
        'Riconoscimento volti non disponibile. Controlla che la fotocamera sia accesa.',
      );
    } finally {
      try {
        await File(shot.path).delete();
      } catch (_) {}
    }
  }

  Future<VisionFrame?> capture() async {
    final shot = await takeShot();
    if (shot == null) return null;
    try {
      final bytes = await shot.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      var note = '';
      try {
        final boxes = await finder.locate(shot.path);
        final sight = faces.identify(decoded, boxes);
        note = sight.note;
        faceStatus = sight.known.isEmpty
            ? (sight.unknown == 0
                  ? 'Nessun volto nel riquadro'
                  : sight.unknown == 1
                  ? 'Persona non in rubrica volti'
                  : '${sight.unknown} persone non in rubrica volti')
            : 'Riconosciuto: ${sight.known.join(', ')}';
      } catch (_) {
        note =
            'Riconoscimento volti locale non disponibile in questo scatto. Non inventare identità.';
      }
      final scaled = decoded.width > decoded.height
          ? img.copyResize(decoded, width: 768)
          : img.copyResize(decoded, height: 768);
      return VisionFrame(
        Uint8List.fromList(img.encodeJpg(scaled, quality: 72)),
        note,
      );
    } finally {
      try {
        await File(shot.path).delete();
      } catch (_) {}
    }
  }

  Future<XFile?> takeShot({bool force = false}) async {
    final current = camera;
    if ((!force && !watching) ||
        current == null ||
        !current.value.isInitialized ||
        current.value.isTakingPicture) {
      return null;
    }
    final token = _cameraGeneration;
    final shot = await current.takePicture();
    if (token != _cameraGeneration) {
      try {
        await File(shot.path).delete();
      } catch (_) {}
      return null;
    }
    return shot;
  }

  Future<Uint8List?> snapshot() async => (await capture())?.photo;

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
      final frame = await capture();
      if (frame == null || token != _cameraGeneration) return;
      final photo = frame.photo;
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
        live.observe(photo, faceNote: frame.note);
      } else {
        final response = await api.respond(
          'Descrivi in una frase i cambiamenti visibili rispetto a: $_scene. Se invariato rispondi solo INVARIATO.',
          '',
          photo: photo,
          faceNote: frame.note,
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
    faceStatus = '';
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
    unawaited(_activeFinder?.close() ?? Future.value());
    api.client.close();
    super.dispose();
  }
}

class VisionFrame {
  final Uint8List photo;
  final String note;
  const VisionFrame(this.photo, this.note);
}
