import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_model.dart';
import 'core.dart';
import 'reactor.dart';

const cyan = Color(0xff32d9ee);
const surface = Color(0xff101f2b);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'JARVIS',
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff07121c),
      colorScheme: ColorScheme.fromSeed(
        seedColor: cyan,
        brightness: Brightness.dark,
        primary: cyan,
        surface: surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    ),
    home: const JarvisHome(),
  );
}

class JarvisHome extends StatefulWidget {
  final AppModel? model;
  const JarvisHome({super.key, this.model});
  @override
  State<JarvisHome> createState() => _JarvisHomeState();
}

class _JarvisHomeState extends State<JarvisHome> with WidgetsBindingObserver {
  late final AppModel model;
  final draft = TextEditingController();
  int tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model = widget.model ?? AppModel();
    unawaited(model.load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(model.enterBackground());
    } else if (state == AppLifecycleState.detached) {
      unawaited(model.shutdown());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    draft.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is JarvisError
                  ? e.message
                  : 'Operazione non riuscita. Riprova.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'J.A.R.V.I.S.',
          style: TextStyle(
            letterSpacing: 4,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Impostazioni',
            onPressed: () => settings(),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !model.ready
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (model.error.isNotEmpty || model.live.error.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              model.error.isNotEmpty
                                  ? model.error
                                  : model.live.error,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: switch (tab) {
                      0 => voicePage(),
                      1 => chatPage(),
                      _ => memoryPage(),
                    },
                  ),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.graphic_eq),
            label: 'Conversazione',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            label: 'Memoria',
          ),
        ],
      ),
    ),
  );
  Widget tag(String label, IconData icon) => Chip(
    avatar: Icon(icon, size: 16, color: cyan),
    label: Text(label, style: const TextStyle(fontSize: 11)),
    side: BorderSide(color: cyan.withValues(alpha: .15)),
    backgroundColor: surface,
  );
  Widget voicePage() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
    children: [
      Wrap(
        spacing: 8,
        children: [
          tag('RISPARMIO AUTOMATICO', Icons.bolt),
          tag(
            '${model.memory.notes.length} ${model.memory.notes.length == 1 ? 'ricordo' : 'ricordi'}',
            Icons.psychology_outlined,
          ),
        ],
      ),
      const SizedBox(height: 18),
      const Text(
        'Al tuo servizio.',
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        model.live.status,
        style: const TextStyle(color: Color(0xff98aebe), fontSize: 16),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: JarvisReactor(
          active: model.live.active,
          speaking: model.live.speaking,
          thinking:
              model.busy ||
              model.live.connecting ||
              model.live.status.contains('Consulto') ||
              model.live.status.contains('Cerco'),
        ),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: model.live.active ? const Color(0xfffa5364) : cyan,
          foregroundColor: const Color(0xff07121c),
        ),
        onPressed: () =>
            model.api.key.isEmpty ? settings() : run(model.startStop),
        icon: Icon(
          model.live.active || model.live.connecting
              ? Icons.stop_rounded
              : Icons.mic_none_rounded,
        ),
        label: Text(
          model.live.active
              ? 'Termina conversazione'
              : model.live.connecting
              ? 'Annulla collegamento'
              : model.api.key.isEmpty
              ? 'Collega JARVIS'
              : 'Avvia conversazione',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      if (model.live.active)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: model.live.pauseMic,
              icon: Icon(model.live.muted ? Icons.mic_off : Icons.mic),
              label: Text(
                model.live.muted ? 'Riattiva microfono' : 'Pausa microfono',
              ),
            ),
            TextButton.icon(
              onPressed: model.live.interrupt,
              icon: const Icon(Icons.volume_off),
              label: const Text('Interrompi'),
            ),
          ],
        ),
      const SizedBox(height: 12),
      Text(
        model.supportsBackgroundVoice && model.continueWhenLocked
            ? 'Voce e microfono continuano anche a schermo bloccato dopo Avvia. Per fermarli premi Termina. Audio inviato a OpenAI; usa credito API.'
            : 'Voce AI • audio inviato a OpenAI durante la conversazione. Usa credito API.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Color(0xff98aebe)),
      ),
      const SizedBox(height: 24),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility_outlined, color: cyan),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'La mia vista',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    model.camera == null ? 'SPENTA' : 'ACCESA',
                    style: const TextStyle(
                      color: cyan,
                      fontSize: 11,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              if (model.camera != null && model.camera!.value.isInitialized)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: AspectRatio(
                      aspectRatio: model.camera!.value.aspectRatio,
                      child: CameraPreview(model.camera!),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                model.visionStatus,
                style: const TextStyle(color: Color(0xff98aebe), fontSize: 13),
              ),
              TextButton.icon(
                onPressed: () => run(model.toggleCamera),
                icon: Icon(
                  model.camera == null
                      ? Icons.videocam_outlined
                      : Icons.videocam_off_outlined,
                ),
                label: Text(
                  model.cameraStarting
                      ? 'Annulla apertura'
                      : model.camera == null
                      ? 'Accendi fotocamera'
                      : 'Spegni fotocamera',
                ),
              ),
              if (model.camera != null && model.cameraCount > 1)
                TextButton.icon(
                  onPressed: model.cameraStarting
                      ? null
                      : () => run(model.switchCamera),
                  icon: const Icon(Icons.cameraswitch_outlined),
                  label: const Text('Cambia fotocamera'),
                ),
              if (model.camera != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Guarda automaticamente',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: model.watching,
                  onChanged: model.setWatching,
                ),
              const Text(
                'Flusso senza scatti. Con vista automatica, circa 5 fotogrammi al secondo se la scena cambia; se è ferma si aggiorna comunque due volte al secondo. Non è un video continuo. Usa credito API.',
                style: TextStyle(fontSize: 11, color: Color(0xff98aebe)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'PROVA A DIRE',
        style: TextStyle(fontSize: 11, color: cyan, letterSpacing: 2),
      ),
      const SizedBox(height: 8),
      const Text(
        '“Ricorda che preferisco risposte brevi”\n“Cerca su internet…”\n“Usa il massimo e aiutami a…”',
        style: TextStyle(height: 1.7, color: Color(0xffb7c7d2)),
      ),
    ],
  );
  Widget chatPage() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                model.live.active
                    ? 'Stessa conversazione, anche scritta.'
                    : 'Chat con modello potente.',
                style: const TextStyle(color: Color(0xff98aebe), fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Nuova chat',
              onPressed: () => run(model.newChat),
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
      ),
      Expanded(
        child: model.messages.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(35),
                  child: Text(
                    'Da dove cominciamo?\n\nScrivi una domanda o avvia la voce. Qui ritrovi le risposte e le fonti.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff98aebe), height: 1.6),
                  ),
                ),
              )
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(18),
                itemCount: model.messages.length,
                itemBuilder: (context, index) {
                  final message =
                      model.messages[model.messages.length - 1 - index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.role == 'user' ? 'TU' : 'JARVIS',
                            style: const TextStyle(
                              color: cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          MarkdownBody(
                            data: message.text,
                            selectable: true,
                            onTapLink: (_, href, _) async {
                              final uri = Uri.tryParse(href ?? '');
                              if (uri != null &&
                                  ['https', 'http'].contains(uri.scheme)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      if (model.busy) const LinearProgressIndicator(minHeight: 2),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: draft,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Scrivi a JARVIS…'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Invia',
              onPressed: model.busy || model.live.connecting
                  ? null
                  : () {
                      final text = draft.text;
                      draft.clear();
                      unawaited(run(() => model.send(text)));
                    },
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    ],
  );
  Widget memoryPage() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Text(
        'Ti tengo a mente.',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Queste note restano su questo telefono anche dopo la chiusura. JARVIS le usa nelle conversazioni e le invia a OpenAI quando risponde.',
        style: TextStyle(color: Color(0xff98aebe), height: 1.5),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: () => editNote(),
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi un ricordo'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: importNotes,
        icon: const Icon(Icons.download_outlined),
        label: const Text('Importa note dal Mac'),
      ),
      if (model.memory.notes.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Text(
            'Nessun ricordo salvato.\nDi’ o scrivi: “Ricorda che…”',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xff98aebe), height: 1.8),
          ),
        ),
      for (var i = 0; i < model.memory.notes.length; i++)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            title: Text(model.memory.notes[i]),
            subtitle: const Text(
              'Salvato sul telefono',
              style: TextStyle(color: Color(0xff98aebe), fontSize: 11),
            ),
            onTap: () => editNote(i),
            trailing: IconButton(
              tooltip: 'Elimina ricordo',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => removeNote(i),
            ),
          ),
        ),
      const SizedBox(height: 14),
      const Text(
        'La chat è temporanea. I ricordi sono separati: vengono salvati solo quando lo chiedi. Nessuna sincronizzazione automatica tra Mac, iPhone e Android.',
        style: TextStyle(color: Color(0xff98aebe), fontSize: 12, height: 1.5),
      ),
    ],
  );
  Future<void> editNote([int? index]) async {
    final controller = TextEditingController(
      text: index == null ? '' : model.memory.notes[index],
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? 'Nuovo ricordo' : 'Modifica ricordo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 7,
          maxLength: 1800,
          decoration: const InputDecoration(
            hintText: 'Una preferenza o qualcosa da ricordare…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await run(() async {
        final notes = [...model.memory.notes];
        if (index == null) {
          notes.add(result);
        } else {
          notes[index] = result;
        }
        await model.editMemory(notes);
      });
    }
  }

  Future<void> removeNote(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare questo ricordo?'),
        content: Text(model.memory.notes[index]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await run(() async {
        final notes = [...model.memory.notes]..removeAt(index);
        await model.editMemory(notes);
      });
    }
  }

  Future<void> importNotes() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importa dal Mac'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Incolla le note di JARVIS o il contenuto del file memoria-da-mac.json. La chiave API non è inclusa.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 7,
              decoration: const InputDecoration(hintText: 'Note da importare'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Importa'),
          ),
        ],
      ),
    );
    if (value != null) await run(() => model.importMemory(value));
  }

  Future<void> settings() async {
    final key = TextEditingController();
    var selected = model.voice;
    var backgroundVoice = model.continueWhenLocked;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Il tuo JARVIS',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  model.api.key.isEmpty
                      ? 'Collega una volta la tua chiave OpenAI.'
                      : 'Chiave API salvata sul telefono.',
                  style: const TextStyle(color: cyan),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: model.api.key.isEmpty
                        ? 'Chiave API OpenAI'
                        : 'Nuova chiave (facoltativa)',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Conservata nell’archivio protetto del telefono. Inviata solo a OpenAI. Non usare questa app per distribuire la tua chiave ad altre persone.',
                  style: TextStyle(fontSize: 12, color: Color(0xff98aebe)),
                ),
                const SizedBox(height: 18),
                if (model.supportsBackgroundVoice)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Continua a schermo bloccato'),
                    subtitle: const Text(
                      'Solo dopo Avvia: voce e microfono restano attivi anche fuori dall’app. La fotocamera si spegne. Usa credito API. Stop dopo 3 minuti di inattività o 25 minuti di sessione.',
                    ),
                    value: backgroundVoice,
                    onChanged: (value) => update(() => backgroundVoice = value),
                  ),
                const Text('Voce della prossima conversazione'),
                Wrap(
                  spacing: 10,
                  children: voices
                      .map(
                        (v) => ChoiceChip(
                          label: Text(v[0].toUpperCase() + v.substring(1)),
                          selected: selected == v,
                          onSelected: (_) => update(() => selected = v),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Risparmio automatico attivo. Usa il massimo per un approfondimento. Webcam, chat e ricerche hanno costi aggiuntivi. La fotocamera si ferma fuori dall’app. Su iPhone la voce continua se abiliti l’opzione a schermo bloccato.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xff98aebe),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await run(
                        () => model.saveSettings(
                          key.text,
                          selected,
                          backgroundVoice: backgroundVoice,
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Salva'),
                  ),
                ),
                if (model.api.key.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await run(model.forgetKey);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Rimuovi chiave dal telefono'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
