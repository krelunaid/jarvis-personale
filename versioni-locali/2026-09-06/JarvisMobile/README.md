# JARVIS per iPhone e Android

App personale Flutter, in italiano, con grafica scura e azzurra. Il codice è condiviso tra iOS e Android. Non contiene la chiave API del Mac.

## Stato verificato

- Analisi statica senza problemi e 13 test superati per la versione 1.0.2.
- Build iOS simulatore compilata, installata e aperta su iPhone 17 Pro simulato.
- Inserimento e persistenza di una nota verificati nell'interfaccia del simulatore, anche dopo aver terminato e riaperto l'app.
- Archivio iOS 1.0.0 (1) firmato per App Store Connect e caricato con successo il 5 settembre 2026. Elaborazione Apple completata. App Store Connect conferma la versione 1.0.0 (1) installata sul tuo iPhone 16 Pro Max (iOS 26.6.1). Scheda app: JARVIS Personale (6808845822).
- Chiave inserita nell’archivio protetto del simulatore; chiamata API reale verificata con risposta «Ciao! Dimmi pure.». La chiave non è inclusa nel pacchetto TestFlight.
- Il caricamento segnala soltanto l’assenza dei simboli di debug del framework WebRTC: può limitare la diagnosi di eventuali crash di quella libreria.
- Voce, microfono, fotocamera e chiamate API della versione mobile richiedono una prova sul telefono con la propria chiave. Non sono state presentate come verificate usando i test simulati.
- Android: sorgente e configurazione nativa inclusi. Build APK non ancora verificata; questo Mac non ha Android SDK e Java configurati.

## Installare con TestFlight

La distribuzione personale usa App Store Connect e il gruppo interno **Andrea - iPhone personale**. La build 1.0.0 (1) è assegnata al gruppo e risulta installata sul tuo iPhone. Gli aggiornamenti si gestiscono dall’app TestFlight.

[Apri TestFlight di JARVIS](https://appstoreconnect.apple.com/teams/a4d7bf54-3ae5-48bc-8b4d-0d6cefba77fe/apps/6808845822/testflight)

## Installazione alternativa via cavo

Collega l'iPhone al Mac, sbloccalo e autorizza il computer se richiesto. Apri **Installa su iPhone.command**. Il comando trova un iPhone fisico e usa la firma Apple configurata in Xcode. Apple può richiedere Modalità sviluppatore sul telefono o una configurazione dell'account in Xcode. La durata della firma dipende dal tipo di account Apple. Non è una pubblicazione su App Store o TestFlight.

Dopo l'installazione, apri Impostazioni in JARVIS e inserisci la tua chiave OpenAI una sola volta. L'app personale usa la chiave che inserisci nel suo archivio protetto e la invia solo a OpenAI. Per distribuire un servizio ad altre persone occorre un backend autenticato, senza incorporare la chiave del proprietario nel pacchetto.

## Memoria

Sul Mac e durante la voce mobile, di' **Ricorda che…**. In chat mobile puoi scrivere lo stesso comando, anche senza API per il salvataggio locale. La scheda **Memoria** permette di aggiungere, modificare ed eliminare note.

**memoria-da-mac.json** contiene soltanto le note esportate dal Mac, senza chiave. Per importarle, aprilo sul telefono e copia il suo contenuto in **Memoria → Importa note dal Mac**. Non caricarlo su servizi pubblici se contiene informazioni personali.

I ricordi restano sul singolo dispositivo e vengono inclusi nelle richieste a OpenAI. Non c'è sincronizzazione automatica tra telefoni e Mac. La cronologia della chat è temporanea; non viene memorizzato automaticamente tutto ciò che dici o viene visto. Le note hanno un limite totale di 8.000 caratteri, 1.800 per singola nota.

## Voce, ricerca e vista

- Conversazione: `gpt-realtime-2.1-mini` via WebRTC, con voce Cedar, Ash o Echo. Il modello può chiamare `gpt-5.5` per un approfondimento; **usa il massimo** lo richiede esplicitamente.
- Chat esterna alla sessione vocale e ricerca web: `gpt-5.5`. Le fonti sono link cliccabili.
- Microfono acceso solo avviando la voce, con pausa e interruzione della risposta. Sessione massima 25 minuti e stop dopo tre minuti senza interventi.
- La fotocamera parte soltanto con **Accendi fotocamera** e usa un flusso di immagini, senza scatti fotografici. Durante la voce invia circa un fotogramma al secondo a OpenAI se la rete lo consente; fuori dalla voce le analisi sono distanziate di almeno 15 secondi e dipendono dalle variazioni della scena. Non analizza ogni istante del video.
- I fotogrammi vengono ridimensionati in memoria senza creare file fotografici. L'immagine automatica precedente viene rimossa dal contesto vocale. Il pulsante **Cambia fotocamera** passa tra frontale e posteriore.
- Su iPhone, con «Continua a schermo bloccato» attivo, una conversazione già avviata prosegue anche fuori dall’app. Il microfono continua a inviare audio a OpenAI; premi Termina per fermarlo. La fotocamera si spegne sempre. Con opzione disattivata, su Android o durante il collegamento, anche la voce si ferma. Le richieste già ricevute dal servizio possono essere state elaborate.
- Voce, immagini e ricerche usano credito API. Il modello più economico non garantisce una riduzione identica del costo totale.

## Compilazione

Richiede Flutter 3.47.2 / Dart 3.13.2 o versioni compatibili, Xcode per iOS, JDK e Android SDK per Android. Il file `pubspec.lock` blocca le dipendenze risolte.

```
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator --debug
flutter build ios --release
flutter build apk --debug
```

L'APK debug serve alle prove personali. La distribuzione richiede una firma release propria e i passaggi del relativo store. Per iOS una build senza firma non si installa su un iPhone.

File principali: `lib/core.dart` per memoria/API e fonti; `lib/realtime.dart` per WebRTC e strumenti; `lib/app_model.dart` per stato e fotocamera; `lib/main.dart` per le schermate.

## Aggiornamento 1.0.1 (2)

Audio iOS a schermo bloccato, opzione disattivabile nelle impostazioni, soglia voce più alta (0.7), filtro antirumore e attesa 750 ms dopo il parlato. Analisi statica e 10 test superati. Archivio iOS compilato, caricato ed elaborato da Apple; build 1.0.1 (2) assegnata al gruppo Andrea - iPhone personale su TestFlight. Verifica del blocco schermo e della sensibilità da completare su iPhone reale.

## Aggiornamento 1.0.2 (3)

Flusso fotocamera senza scatti, invio di circa un fotogramma al secondo durante la voce, conversione BGRA/YUV fuori dal thread UI e cambio frontale/posteriore. Gli invii vengono saltati se il canale di rete è congestionato. Analisi statica e 13 test superati, archivio iOS compilato, caricato ed elaborato da Apple; build 1.0.2 (3) assegnata al gruppo Andrea - iPhone personale su TestFlight. La fluidità e la comprensione delle immagini richiedono una prova su iPhone reale.

## Aggiornamento 1.0.3 (4)

Ogni avvio vocale apre una conversazione nuova senza reinviare i vecchi messaggi. Termina azzera la chat e spegne la fotocamera; uscire dall’app senza una chiamata attiva azzera la chat. I ricordi salvati e le impostazioni restano. Una chiamata iOS attiva continua a schermo bloccato se abilitato. Analisi statica e 15 test superati.

Build 1.0.3 (4) caricata ed elaborata da Apple il 5 settembre 2026. Avviso non bloccante: simboli dSYM WebRTC mancanti.

## Aggiornamento 1.0.4 (5)

Soglia di rilevamento voce aumentata da 0.7 a 0.8 per ridurre le interruzioni causate da suoni deboli. Interruzione tramite parlato ancora abilitata; voce, modello e attesa a fine frase invariati. Da verificare su telefono reale con tono normale e rumori ambientali.

Build 1.0.4 (5): analisi statica e 15 test superati; archivio iOS caricato ed elaborato da Apple il 5 settembre 2026. Avviso non bloccante: dSYM WebRTC mancante.

## Aggiornamento 1.0.5 (6)

Le interruzioni automatiche e le risposte al solo VAD sono disattivate: la risposta viene avviata dopo una trascrizione valida. I rumori senza parole e alcuni intercalari non interrompono; sì/ok durante la risposta non la tagliano. Aspetta/fermati restano validi. Il pulsante Interrompi agisce subito. La conferma può aggiungere attesa fino alla fine del breve intervento e alla trascrizione, e dipende dalla sua accuratezza. Analisi statica e 21 test superati; sensibilità reale da verificare su iPhone.

Distribuzione 1.0.5 (6): archivio iOS compilato, ma due tentativi di export/upload il 5 settembre 2026 alle 15:45–15:46 sono falliti con NSURLError -1004. developerservices2.apple.com:443 non raggiungibile anche tramite curl; App Store Connect raggiungibile. Build non caricata su TestFlight. Riprendere export con work/TestFlight-UploadOptions.plist quando il servizio torna raggiungibile.

Aggiornamento distribuzione 5 settembre 2026 ore 17:52: caricamento 1.0.5 (6) riuscito ed elaborazione Apple completata. Problema di connessione precedente risolto.
