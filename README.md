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

Microfono e fotocamera si attivano dai rispettivi controlli. La vista automatica invia immagini periodiche al servizio, non un video continuo. La versione mobile ferma i sensori quando passa in background.

I volti si iscrivono solo su richiesta («Ricorda questo volto come…» o il pulsante in camera). I modelli restano sul telefono, cifrati come le note; non vengono inviati a OpenAI. JARVIS può nominare soltanto le persone iscritte se le riconosce inquadrato; i volti sconosciuti restano «persona non in rubrica volti», senza indovinare celebrità o nomi a caso. La rubrica si elenca e si cancella dalle impostazioni o con «Dimentica il volto di…».

Il comando AirDrop della versione Mac esporta esplicitamente un file temporaneo contenente la propria chiave: usarlo solo verso il proprio dispositivo ed eliminare la copia ricevuta dopo l’importazione. La copia temporanea viene rimossa dopo dieci minuti mentre l’app resta aperta.

## Stato delle verifiche

Build macOS e iOS compilate; test Flutter e analisi statica superati durante lo sviluppo. Chat API provata nel simulatore iOS. Una build iOS è stata distribuita con TestFlight. La build Android non è ancora verificata. Microfono, audio e fotocamera richiedono prove sul dispositivo reale.

Le API e i modelli configurati nel codice richiedono disponibilità sul proprio account. Progetto personale indipendente, non affiliato a Marvel o ai produttori di Iron Man. Le dipendenze mantengono le rispettive licenze. Non è stata assegnata una licenza generale al codice del progetto.
