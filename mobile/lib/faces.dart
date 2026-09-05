import 'dart:convert';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'core.dart';

class FaceBox {
  final int left, top, width, height;
  final double? leftEyeX, leftEyeY, rightEyeX, rightEyeY;
  const FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.leftEyeX,
    this.leftEyeY,
    this.rightEyeX,
    this.rightEyeY,
  });
  bool get tiny => width < 40 || height < 40;
}

class FacePerson {
  final String id;
  final String name;
  final List<List<double>> prints;
  const FacePerson(this.id, this.name, this.prints);
}

class FaceSighting {
  final List<String> known;
  final int unknown;
  const FaceSighting({this.known = const [], this.unknown = 0});
  String get note {
    if (known.isEmpty && unknown == 0) {
      return 'Riconoscimento volti locale: nessun volto rilevato. Non inventare identità.';
    }
    final parts = <String>[];
    if (known.isNotEmpty) {
      parts.add('Persone iscritte nel riquadro: ${known.join(', ')}.');
    }
    if (unknown == 1) {
      parts.add(
        'C’è 1 persona non in rubrica volti: dilla così, senza inventare un nome.',
      );
    } else if (unknown > 1) {
      parts.add(
        'Ci sono $unknown persone non in rubrica volti: non inventare nomi.',
      );
    }
    return 'Riconoscimento volti locale (solo iscritti). ${parts.join(' ')}';
  }
}

class FaceCommand {
  final String action;
  final String? name;
  const FaceCommand(this.action, [this.name]);
}

abstract class FaceFinder {
  Future<List<FaceBox>> locate(String imagePath);
  Future<void> close() async {}
}

/// Compact on-device descriptor: equalized crop + cell tones + oriented gradients.
/// Conservative cosine match; unknown faces stay unnamed.
class FacePrint {
  static const size = 64;
  static const cells = 8;
  static const bins = 8;
  static const threshold = 0.82;
  static const margin = 0.05;
  static List<double> fromImage(img.Image source, FaceBox box) {
    final crop = _aligned(source, box);
    final gray = img.grayscale(
      img.copyResize(crop, width: size, height: size),
    );
    final eq = _equalize(gray);
    final tones = List<double>.filled(cells * cells, 0);
    final hog = List<double>.filled(cells * cells * bins, 0);
    final pixels = List<double>.filled(16 * 16, 0);
    final cell = size ~/ cells;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final lum = eq.getPixel(x, y).luminance.toDouble();
        final cy = y ~/ cell;
        final cx = x ~/ cell;
        tones[cy * cells + cx] += lum;
        pixels[(y ~/ 4) * 16 + (x ~/ 4)] += lum;
        if (x == 0 || y == 0 || x == size - 1 || y == size - 1) continue;
        final gx =
            eq.getPixel(x + 1, y).luminance - eq.getPixel(x - 1, y).luminance;
        final gy =
            eq.getPixel(x, y + 1).luminance - eq.getPixel(x, y - 1).luminance;
        final mag = math.sqrt(gx * gx + gy * gy);
        if (mag < 1) continue;
        var angle = math.atan2(gy, gx);
        if (angle < 0) angle += math.pi;
        final bin = math.min(bins - 1, (angle / math.pi * bins).floor());
        hog[(cy * cells + cx) * bins + bin] += mag;
      }
    }
    final area = (cell * cell).toDouble();
    for (var i = 0; i < tones.length; i++) {
      tones[i] = tones[i] / area / 255;
    }
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] = pixels[i] / 16 / 255;
    }
    return _l2([...tones, ...pixels, ...hog]);
  }

  static double cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static img.Image _aligned(img.Image source, FaceBox box) {
    final padX = math.max(4, (box.width * 0.18).round());
    final padY = math.max(4, (box.height * 0.18).round());
    final left = (box.left - padX).clamp(0, source.width - 1);
    final top = (box.top - padY).clamp(0, source.height - 1);
    final right = (box.left + box.width + padX).clamp(left + 1, source.width);
    final bottom = (box.top + box.height + padY).clamp(top + 1, source.height);
    var crop = img.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
    final lx = box.leftEyeX;
    final ly = box.leftEyeY;
    final rx = box.rightEyeX;
    final ry = box.rightEyeY;
    if (lx != null && ly != null && rx != null && ry != null) {
      final angle = math.atan2(ry - ly, rx - lx) * 180 / math.pi;
      if (angle.abs() > 2 && angle.abs() < 35) {
        crop = img.copyRotate(crop, angle: -angle);
      }
    }
    return crop;
  }

  static img.Image _equalize(img.Image gray) {
    final hist = List<int>.filled(256, 0);
    for (var y = 0; y < gray.height; y++) {
      for (var x = 0; x < gray.width; x++) {
        hist[gray.getPixel(x, y).luminance.round().clamp(0, 255)]++;
      }
    }
    final total = gray.width * gray.height;
    if (total <= 1) return gray;
    final map = List<int>.filled(256, 0);
    var cdf = 0;
    var started = false;
    var cdfMin = 0;
    for (var i = 0; i < 256; i++) {
      if (hist[i] == 0) continue;
      if (!started) {
        cdfMin = hist[i];
        started = true;
      }
      cdf += hist[i];
      final span = total - cdfMin;
      map[i] = span <= 0
          ? i
          : (((cdf - cdfMin) / span) * 255).round().clamp(0, 255);
    }
    final out = img.Image(width: gray.width, height: gray.height);
    for (var y = 0; y < gray.height; y++) {
      for (var x = 0; x < gray.width; x++) {
        final v = map[gray.getPixel(x, y).luminance.round().clamp(0, 255)];
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  static List<double> _l2(List<double> values) {
    var sum = 0.0;
    for (final v in values) {
      sum += v * v;
    }
    final norm = math.sqrt(sum);
    if (norm < 1e-9) return values;
    return [for (final v in values) v / norm];
  }
}

class FaceBook {
  final LocalStore storage;
  List<FacePerson> people = [];
  FaceBook(this.storage);
  static const _key = 'faces';
  static const _maxPeople = 20;
  static const _maxPrints = 5;

  Future<void> load() async {
    final raw = await storage.read(_key);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw JarvisError(
        'Rubrica volti non leggibile. Il contenuto salvato non è stato modificato.',
      );
    }
    people = [for (final item in decoded) _parse(item)];
  }

  String get names => people.map((p) => p.name).join(', ');

  String listText() {
    if (people.isEmpty) return 'Nessun volto in rubrica.';
    return 'In rubrica volti: ${people.map((p) => p.name).join(', ')}.';
  }

  FaceSighting identify(img.Image photo, List<FaceBox> boxes) {
    final known = <String>[];
    var unknown = 0;
    for (final box in boxes) {
      if (box.tiny) {
        unknown++;
        continue;
      }
      final name = match(FacePrint.fromImage(photo, box));
      if (name == null) {
        unknown++;
      } else if (!known.contains(name)) {
        known.add(name);
      }
    }
    return FaceSighting(known: known, unknown: unknown);
  }

  String? match(List<double> print) {
    if (people.isEmpty) return null;
    String? bestName;
    var best = 0.0;
    var second = 0.0;
    for (final person in people) {
      var score = 0.0;
      for (final sample in person.prints) {
        score = math.max(score, FacePrint.cosine(print, sample));
      }
      if (score > best) {
        second = best;
        best = score;
        bestName = person.name;
      } else if (score > second) {
        second = score;
      }
    }
    if (bestName == null ||
        best < FacePrint.threshold ||
        best - second < FacePrint.margin) {
      return null;
    }
    return bestName;
  }

  Future<String> enroll(String name, List<double> print) async {
    final clean = _cleanName(name);
    final existing = people
        .where((p) => p.name.toLowerCase() == clean.toLowerCase())
        .firstOrNull;
    if (existing != null) {
      if (existing.prints.length >= _maxPrints) {
        throw JarvisError(
          'Ho già abbastanza scatti di $clean. Eliminalo dalla rubrica se vuoi ricominciare.',
        );
      }
      await _save([
        for (final p in people)
          p.id == existing.id
              ? FacePerson(p.id, p.name, [...p.prints, print])
              : p,
      ]);
      return 'Ho aggiunto un altro scatto di ${existing.name} nella rubrica volti.';
    }
    if (people.length >= _maxPeople) {
      throw JarvisError(
        'Rubrica volti piena (massimo $_maxPeople persone). Eliminane una dalle impostazioni.',
      );
    }
    await _save([
      ...people,
      FacePerson(DateTime.now().microsecondsSinceEpoch.toString(), clean, [
        print,
      ]),
    ]);
    return 'Volto iscritto sul telefono come $clean. Lo nominerò solo se lo riconosco.';
  }

  Future<String> forget(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw JarvisError('Dimmi quale volto dimenticare.');
    final next = people
        .where((p) => p.name.toLowerCase() != clean.toLowerCase())
        .toList();
    if (next.length == people.length) {
      throw JarvisError('«$clean» non è in rubrica volti.');
    }
    await _save(next);
    return 'Ho rimosso $clean dalla rubrica volti.';
  }

  Future<void> _save(List<FacePerson> next) async {
    await storage.write(
      _key,
      jsonEncode([
        for (final p in next)
          {'id': p.id, 'name': p.name, 'prints': p.prints},
      ]),
    );
    people = next;
  }

  static FacePerson _parse(Object? item) {
    if (item is! Map) {
      throw JarvisError(
        'Rubrica volti non leggibile. Il contenuto salvato non è stato modificato.',
      );
    }
    final id = item['id'];
    final name = item['name'];
    final prints = item['prints'];
    if (id is! String ||
        name is! String ||
        prints is! List ||
        prints.any((p) {
          if (p is! List) return true;
          return p.any((n) => n is! num);
        })) {
      throw JarvisError(
        'Rubrica volti non leggibile. Il contenuto salvato non è stato modificato.',
      );
    }
    return FacePerson(id, name, [
      for (final p in prints) [for (final n in p as List) (n as num).toDouble()],
    ]);
  }

  static String _cleanName(String value) {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.length > 40) {
      throw JarvisError('Usa un nome tra 1 e 40 caratteri.');
    }
    return name;
  }

  static FaceCommand? command(String value) {
    final text = value.trim().replaceFirst(
      RegExp(r'^jarvis[\s,:.]*', caseSensitive: false),
      '',
    );
    final enroll = RegExp(
      r'^(?:ricorda questo (?:volto|viso)|iscrivi questo (?:volto|viso)|memorizza questo (?:volto|viso))\s+come\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (enroll != null) return FaceCommand('enroll', enroll.group(1)?.trim());
    if (RegExp(
      r'^(?:chi hai in rubrica volti|elenca i volti(?: iscritti)?|quali volti (?:ricordi|conosci)|mostra la rubrica volti|rubrica volti)\??$',
      caseSensitive: false,
    ).hasMatch(text)) {
      return const FaceCommand('list');
    }
    final forget = RegExp(
      r'^(?:dimentica|scorda|cancella|elimina|togli)(?: il (?:volto|viso) di)?\s+(.+?)\s+dalla rubrica volti$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (forget != null) return FaceCommand('forget', forget.group(1)?.trim());
    final forgetNamed = RegExp(
      r'^(?:dimentica|scorda|cancella|elimina) il (?:volto|viso) di\s+(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (forgetNamed != null) {
      return FaceCommand('forget', forgetNamed.group(1)?.trim());
    }
    return null;
  }
}
