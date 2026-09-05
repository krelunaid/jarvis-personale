import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'core.dart';

class Realtime {
  final OpenAI api;
  final Memories memory;
  final void Function() changed;
  final void Function(String, String, String) transcript;
  final Future<String> Function(String, bool) consult;
  Realtime(this.api, this.memory, this.changed, this.transcript, this.consult);
  RTCPeerConnection? _peer;
  RTCDataChannel? _channel;
  MediaStream? _mic;
  RTCVideoRenderer? _remote;
  Timer? _limit;
  bool active = false, connecting = false, muted = false, speaking = false;
  String status = 'Pronto a conversare', error = '', voice = 'cedar';
  int _generation = 0, _expertCalls = 0;
  final _handled = <String>{};
  String? _observation;
  bool _responding = false;
  Future<void> _tools = Future.value();
  DateTime _lastInput = DateTime.now();
  Timer? _idle;

  Future<void> start(List<ChatEntry> history) async {
    if (active || connecting) return;
    if (api.key.isEmpty) {
      throw JarvisError('Collega la tua chiave API nelle impostazioni.');
    }
    await stop();
    final token = _generation;
    connecting = true;
    error = '';
    status = 'Collego la voce…';
    changed();
    try {
      final mic = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      if (token != _generation) {
        for (final t in mic.getTracks()) {
          await t.stop();
        }
        await mic.dispose();
        return;
      }
      _mic = mic;
      final peer = await createPeerConnection({
        'iceServers': <Map<String, dynamic>>[],
      });
      if (token != _generation) {
        await peer.close();
        return;
      }
      _peer = peer;
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remote = renderer;
      peer.onTrack = (event) {
        if (token == _generation && event.streams.isNotEmpty) {
          renderer.srcObject = event.streams.first;
        }
      };
      peer.onConnectionState = (state) {
        if (token == _generation &&
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(_fail('Connessione vocale interrotta. Riprova.'));
        }
      };
      for (final track in mic.getAudioTracks()) {
        await peer.addTrack(track, mic);
      }
      final dc = await peer.createDataChannel(
        'oai-events',
        RTCDataChannelInit(),
      );
      _channel = dc;
      final ready = Completer<void>();
      dc.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !ready.isCompleted) {
          ready.complete();
        }
      };
      dc.onMessage = (message) {
        if (token != _generation || message.isBinary) return;
        try {
          _handle(jsonDecode(message.text) as Map<String, dynamic>);
        } catch (_) {
          unawaited(_fail('Risposta vocale non leggibile. Riprova.'));
        }
      };
      final offer = await peer.createOffer({'offerToReceiveAudio': true});
      await peer.setLocalDescription(offer);
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('https://api.openai.com/v1/realtime/calls'),
            )
            ..headers['Authorization'] = 'Bearer ${api.key}'
            ..fields['sdp'] = offer.sdp!
            ..fields['session'] = jsonEncode(
              liveSession(memory.context, voice),
            );
      final response = await http.Response.fromStream(
        await api.client.send(request),
      ).timeout(const Duration(seconds: 25));
      OpenAI.check(response.statusCode);
      if (token != _generation) return;
      await peer.setRemoteDescription(
        RTCSessionDescription(response.body, 'answer'),
      );
      if (dc.state == RTCDataChannelState.RTCDataChannelOpen &&
          !ready.isCompleted) {
        ready.complete();
      }
      await ready.future.timeout(const Duration(seconds: 15));
      if (token != _generation) return;
      await Helper.setSpeakerphoneOn(true);
      connecting = false;
      active = true;
      status = 'Ti ascolto';
      _lastInput = DateTime.now();
      for (final m in history.skip(
        history.length > 6 ? history.length - 6 : 0,
      )) {
        send({
          'type': 'conversation.item.create',
          'item': {
            'type': 'message',
            'role': m.role,
            'content': [
              {
                'type': m.role == 'user' ? 'input_text' : 'output_text',
                'text': m.text,
              },
            ],
          },
        });
      }
      send({
        'type': 'response.create',
        'response': {
          'instructions':
              'Saluta brevemente in italiano. Non inventare di vedere o sentire qualcosa.',
        },
      });
      _limit = Timer(const Duration(minutes: 25), () => unawaited(stop()));
      _idle = Timer.periodic(const Duration(seconds: 15), (_) {
        if (DateTime.now().difference(_lastInput) > const Duration(minutes: 3)) {
          unawaited(stop());
        }
      });
      changed();
    } catch (e) {
      if (token == _generation) {
        await _fail(
          e is JarvisError
              ? e.message
              : 'Non riesco ad avviare la voce. Controlla rete e permesso microfono.',
        );
      }
    }
  }

  void send(Map<String, dynamic> value) {
    if (_channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      unawaited(
        _channel!.send(RTCDataChannelMessage(jsonEncode(value))).catchError((
          Object _,
        ) {
          unawaited(_fail('Invio vocale interrotto.'));
        }),
      );
    }
  }

  void updateMemory() {
    if (active) {
      send({
        'type': 'session.update',
        'session': liveSession(memory.context, voice),
      });
    }
  }

  void pauseMic() {
    muted = !muted;
    for (final track in _mic?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    if (muted) send({'type': 'input_audio_buffer.clear'});
    status = muted ? 'Microfono in pausa' : 'Ti ascolto';
    changed();
  }

  void interrupt() {
    if (_responding) send({'type': 'response.cancel'});
    send({'type': 'output_audio_buffer.clear'});
    speaking = false;
    changed();
  }

  void sayText(String text, {Uint8List? photo}) {
    if (!active) return;
    interrupt();
    _expertCalls = 0;
    _lastInput = DateTime.now();
    send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': text},
          if (photo != null)
            {
              'type': 'input_image',
              'image_url': 'data:image/jpeg;base64,${base64Encode(photo)}',
            },
        ],
      },
    });
    transcript('u${DateTime.now().microsecondsSinceEpoch}', 'user', text);
    send({'type': 'response.create'});
  }

  void observe(Uint8List image) {
    if (!active) return;
    clearObservation();
    final id = 'v${DateTime.now().microsecondsSinceEpoch}';
    _observation = id;
    send({
      'type': 'conversation.item.create',
      'item': {
        'id': id,
        'type': 'message',
        'role': 'user',
        'content': [
          {
            'type': 'input_text',
            'text':
                'Foto automatica aggiornata adesso. Usala per le prossime domande, senza commentarla spontaneamente.',
          },
          {
            'type': 'input_image',
            'image_url': 'data:image/jpeg;base64,${base64Encode(image)}',
          },
        ],
      },
    });
  }

  void clearObservation() {
    if (_observation != null) {
      send({'type': 'conversation.item.delete', 'item_id': _observation});
    }
    _observation = null;
  }

  void _handle(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'input_audio_buffer.speech_started':
        _lastInput = DateTime.now();
        _expertCalls = 0;
        status = 'Ti ascolto';
      case 'conversation.item.input_audio_transcription.completed':
        transcript(
          event['item_id'] as String,
          'user',
          event['transcript'] as String? ?? '',
        );
      case 'response.output_audio_transcript.done':
      case 'response.output_text.done':
        transcript(
          event['item_id'] as String,
          'assistant',
          (event['transcript'] ?? event['text']) as String? ?? '',
        );
      case 'response.created':
        _responding = true;
      case 'output_audio_buffer.started':
        speaking = true;
        status = 'JARVIS parla';
      case 'output_audio_buffer.stopped':
      case 'output_audio_buffer.cleared':
        speaking = false;
        status = muted ? 'Microfono in pausa' : 'Ti ascolto';
      case 'response.done':
        _responding = false;
        final response = event['response'] as Map<String, dynamic>? ?? {};
        if (response['status'] == 'failed') {
          unawaited(
            _fail(
              'Il servizio vocale non ha completato la risposta. Verifica credito e accesso al modello.',
            ),
          );
          return;
        }
        if (response['status'] == 'cancelled') return;
        final calls = (response['output'] as List? ?? [])
            .where((v) => v['type'] == 'function_call')
            .cast<Map<String, dynamic>>()
            .toList();
        if (calls.isNotEmpty) {
          final token = _generation;
          _tools = _tools.then((_) => _runTools(calls, token)).catchError((
            Object _,
          ) {
            if (token == _generation) {
              error = 'Strumento non riuscito. Riprova.';
              changed();
            }
          });
        }
      case 'error':
        final code = (event['error'] as Map?)?['code'];
        if (code != 'response_cancel_not_active' &&
            code != 'output_audio_buffer_empty') {
          unawaited(
            _fail(
              'Errore del servizio vocale. Riprova o controlla il credito API.',
            ),
          );
        }
    }
    changed();
  }

  Future<void> _runTools(List<Map<String, dynamic>> calls, int token) async {
    bool produced = false;
    for (final call in calls) {
      if (token != _generation) return;
      final id = call['call_id'] as String?;
      if (id == null || !_handled.add(id)) continue;
      String result;
      try {
        final args =
            jsonDecode(call['arguments'] as String) as Map<String, dynamic>;
        switch (call['name']) {
          case 'remember_memory':
            result = await memory.remember(args['note'] as String);
            updateMemory();
          case 'search_web':
          case 'consult_expert':
            final query = args['query'] as String;
            if (query.trim().isEmpty || query.length > 6000) {
              throw JarvisError('Richiesta non valida.');
            }
            final expert = call['name'] == 'consult_expert';
            if (expert && ++_expertCalls > 2) {
              throw JarvisError(
                'Limite di approfondimenti raggiunto per questa domanda.',
              );
            }
            status = expert
                ? 'Consulto il modello potente…'
                : 'Cerco su internet…';
            changed();
            result = await consult(query, !expert);
          default:
            result = 'Strumento non disponibile.';
        }
      } catch (e) {
        result =
            'Operazione non riuscita. Non inventare un risultato. ${e is JarvisError ? e.message : ''}';
      }
      if (token != _generation) return;
      send({
        'type': 'conversation.item.create',
        'item': {
          'type': 'function_call_output',
          'call_id': id,
          'output': result,
        },
      });
      produced = true;
    }
    if (produced && token == _generation && !_responding) {
      send({'type': 'response.create'});
    }
  }

  Future<void> _fail(String message) async {
    await stop();
    error = message;
    changed();
  }

  Future<void> stop() async {
    _generation++;
    _limit?.cancel();
    _idle?.cancel();
    active = false;
    connecting = false;
    speaking = false;
    muted = false;
    _tools = Future.value();
    _handled.clear();
    _observation = null;
    _expertCalls = 0;
    _responding = false;
    final mic = _mic;
    _mic = null;
    final peer = _peer;
    _peer = null;
    final channel = _channel;
    _channel = null;
    final remote = _remote;
    _remote = null;
    status = 'Pronto a conversare';
    changed();
    for (final track in mic?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await mic?.dispose();
    await channel?.close();
    await peer?.close();
    await remote?.dispose();
  }
}
