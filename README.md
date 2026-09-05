# JARVIS Personale

Assistente personale in italiano per macOS, iPhone e Android: conversazione vocale, chat con fonti web, analisi della fotocamera su attivazione e memoria locale modificabile.

- `macos/`: app SwiftUI nativa, richiede un Mac Apple Silicon e gli strumenti Xcode.
- `mobile/`: app Flutter condivisa fra iOS e Android.

## Avvio

### Mac

Esegui `./macos/build.command`, poi apri `macos/Jarvis.app`. I controlli locali si eseguono con `./macos/verify.command`.

### iPhone e Android

Installa Flutter (versione usata: 3.47.2, Dart 3.13.2), Xcode per iOS oppure Android SDK e JDK per Android. Da `mobile/`:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Per un iPhone fisico seleziona il tuo team Apple in Xcode e un identificatore app disponibile. TestFlight richiede il tuo account sviluppatore e una build firmata. Gli identificatori inclusi sono esempi da personalizzare; nessun certificato o profilo privato è distribuito.

## Collegamento e memoria

Inserisci la tua chiave OpenAI nelle impostazioni dell’app. Le API richiedono credito e generano costi. Ogni installazione conserva la propria chiave nell’archivio protetto del sistema: il repository non include credenziali o ricordi personali.

Scrivi o pronuncia «Ricorda che…» per salvare una nota. I ricordi sono locali al dispositivo e vengono inclusi nelle richieste all’AI; non si sincronizzano automaticamente. Non viene archiviata automaticamente tutta la conversazione.

Microfono e fotocamera si attivano dai rispettivi controlli. La vista mobile legge fotogrammi dal flusso della fotocamera, senza scatti né file temporanei. Durante la voce invia al massimo circa un’immagine al secondo; fuori dalla voce mantiene analisi distanziate di almeno 15 secondi. Non analizza ogni fotogramma del video. Su iPhone l’opzione «Continua a schermo bloccato» mantiene voce e microfono di una conversazione già avviata anche fuori dall’app; è abilitata inizialmente e disattivabile nelle impostazioni. La fotocamera si spegne sempre in background. Con opzione disattivata, su Android o durante un collegamento non ancora completato, la voce si ferma. Restano i limiti di tre minuti di inattività e 25 minuti per sessione. Non è implementata l’identificazione delle persone dal volto.

Il comando AirDrop della versione Mac esporta esplicitamente un file temporaneo contenente la propria chiave: usarlo solo verso il proprio dispositivo ed eliminare la copia ricevuta dopo l’importazione. La copia temporanea viene rimossa dopo dieci minuti mentre l’app resta aperta.

## Stato delle verifiche

Build macOS e iOS compilate; tredici test Flutter e analisi statica superati durante lo sviluppo. Chat API provata nel simulatore iOS. Una build iOS è stata distribuita con TestFlight. La build Android non è ancora verificata. Microfono, audio e fotocamera richiedono prove sul dispositivo reale.

Le API e i modelli configurati nel codice richiedono disponibilità sul proprio account. Progetto personale indipendente, non affiliato a Marvel o ai produttori di Iron Man. Le dipendenze mantengono le rispettive licenze. Non è stata assegnata una licenza generale al codice del progetto.

## Versione 1.0.1

Filtro antirumore, soglia di rilevamento della voce più alta e attesa di 750 ms dopo il parlato. Audio iOS configurato per conversazione e uso a schermo bloccato. Analisi statica e dieci test superati, inclusi opt-out persistente, stop in fase di collegamento e spegnimento fotocamera in background. La qualità del microfono e la continuità a schermo bloccato richiedono conferma sul dispositivo reale.

## Versione 1.0.2

Flusso fotocamera con conversione BGRA/YUV su isolate e cambio obiettivo frontale/posteriore. Immagini in memoria, nessun takePicture o salvataggio fotografico. Frame limitati a 768 pixel; elaborazione singola senza coda e controllo del buffer di rete. Stop e cambio fotocamera invalidano le immagini precedenti. La cattura è orientata in verticale. Analisi statica e 13 test; qualità e fluidità da verificare sul telefono reale. Gli invii più frequenti aumentano i costi API.

## Aggiornamento 1.0.3 (4)

Ogni avvio vocale apre una conversazione nuova senza reinviare i vecchi messaggi. Termina azzera la chat e spegne la fotocamera; uscire dall’app senza una chiamata attiva azzera la chat. I ricordi salvati e le impostazioni restano. Una chiamata iOS attiva continua a schermo bloccato se abilitato. Analisi statica e 15 test superati.

## Aggiornamento 1.0.4 (5)

Soglia di rilevamento voce aumentata da 0.7 a 0.8 per ridurre le interruzioni causate da suoni deboli. Interruzione tramite parlato ancora abilitata; voce, modello e attesa a fine frase invariati. Da verificare su telefono reale con tono normale e rumori ambientali.

## Aggiornamento 1.0.5 (6)

Le interruzioni automatiche e le risposte al solo VAD sono disattivate: la risposta viene avviata dopo una trascrizione valida. I rumori senza parole e alcuni intercalari non interrompono; sì/ok durante la risposta non la tagliano. Aspetta/fermati restano validi. Il pulsante Interrompi agisce subito. La conferma può aggiungere attesa fino alla fine del breve intervento e alla trascrizione, e dipende dalla sua accuratezza. Analisi statica e 21 test superati; sensibilità reale da verificare su iPhone.
