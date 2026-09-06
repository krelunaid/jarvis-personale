# JARVIS per Mac — versione 0.4

Apri **Jarvis.app**. È un’app nativa per questo Mac Apple Silicon (macOS 13 o successivo).

## Scegli la voce

Apri **Scegli la voce AI**. Sono disponibili **Cedar**, **Ash** ed **Echo**: le anteprime leggono la stessa frase italiana. Premi **Ascolta** e poi **Usa questa voce**; la scelta viene salvata e applicata alla prossima conversazione. Le anteprime usano Realtime senza attivare il microfono, sono salvate nella cartella `Voci` e gli ascolti successivi non richiedono nuove chiamate. Sono voci AI, non il doppiatore del film.

La lettura della chat con la voce locale del Mac è ora spenta per impostazione predefinita. Il problema audio macOS `-10875` è stato corretto allineando il formato di uscita al formato del microfono: l'avvio Realtime e una risposta vocale sono stati verificati su questo Mac con il credito attivo.

## Inizia in due passaggi

1. In **Impostazioni e memoria**, incolla una chiave API OpenAI e premi **Salva**. La chiave resta nel Portachiavi del Mac. Serve un account API con credito e accesso ai modelli usati; l’app non usa la sessione di Codex.
2. Premi **Avvia conversazione** e consenti il microfono. Parla normalmente: JARVIS riconosce quando termini la frase e risponde con voce AI. L’acquisizione ora usa direttamente AVCaptureSession. Per evitare ritorni della voce dagli altoparlanti, ascolta tra le risposte; premi l’altoparlante barrato per interromperlo e parlare.

**Pausa microfono** interrompe l’invio di nuovo audio; la risposta già in corso può continuare. **Termina conversazione** chiude la connessione e ferma l’audio. Se cambi dispositivo audio, riavvia la conversazione. Dopo 3 minuti senza un tuo intervento la sessione si ferma; ogni sessione dura al massimo 25 minuti. Puoi riavviarla.

## Internet

La chat può cercare sul web e mostrare fonti cliccabili. Anche nella conversazione vocale puoi dire «Cerca su internet…»: JARVIS richiama una ricerca Responses e ne riassume il risultato a voce; il testo con le fonti compare in chat. La ricerca usa la stessa chiave già salvata e credito API. Non equivale al controllo del browser o all'accesso ai tuoi account.

## Dagli la vista

Premi **Accendi videocamera**: **JARVIS guarda automaticamente** è già attivo. Non serve premere Guarda. Fuori dalla conversazione, analizza una foto all'accensione e poi circa ogni 15 secondi più il tempo della risposta; pubblica una breve descrizione quando rileva cambiamenti. Durante la conversazione invia una nuova foto ogni 5 secondi: JARVIS la usa per rispondere quando gli parli. Le vecchie immagini automatiche vengono sostituite nel contesto vocale.

Le immagini sono ridotte a 768 pixel sul lato maggiore e inviate a OpenAI, usando credito API. Non è un video continuo. L'indicatore sotto la webcam mostra attività o errori. **Spegni videocamera** interrompe nuove acquisizioni e l'invio automatico; disattivando **JARVIS guarda automaticamente** resta solo l'anteprima locale. Una richiesta già ricevuta dal servizio può essere stata elaborata. **Guarda e rispondi** resta disponibile per una richiesta manuale. La videocamera resta spenta all'avvio dell'app.

## Chat, voce e memoria

Puoi anche scrivere. Durante la conversazione la domanda scritta entra nella stessa sessione vocale; fuori dalla sessione usa il modello di ragionamento e legge la risposta con la voce del Mac se **Leggi chat** è acceso.

**Detta testo** rimane disponibile come alternativa: registra fino a un minuto, trascrive e lascia controllare il testo prima dell’invio. **Prova altoparlanti** usa la voce locale del Mac, diversa dalla voce AI della conversazione.

Le note personali nelle impostazioni sono la memoria persistente: restano nelle preferenze del Mac e vengono incluse nelle richieste. Di’ «Ricorda che…» durante la conversazione, oppure scrivilo in chat: la nota viene salvata sul Mac e resta disponibile dopo la chiusura. Il salvataggio viene confermato solo dopo l’esito. Le note hanno un limite complessivo di 4.000 caratteri: quando sono piene l’app chiede di liberare spazio. Modifica o cancella il testo e premi Salva per cambiarle. Non vengono creati ricordi automatici. La cronologia della chat resta in memoria fino alla chiusura; **Nuova chat** ferma la sessione e la svuota. Riavviando una sessione, le ultime 12 voci testuali forniscono contesto.

## Dati e servizi

- Voce naturale: OpenAI **gpt-realtime-2.1-mini**, voce **cedar**, riconoscimento automatico dei turni e ascolto tra le risposte per evitare il ritorno dagli altoparlanti.
- Chat scritta fuori dalla sessione: **gpt-5.5**, ragionamento medio.
- Trascrizione nella sessione: **gpt-4o-mini-transcribe**. Dettatura separata: **whisper-1**.
- Microfono spento prima di Avvia; durante la sessione l’audio viene inviato a OpenAI anche tra i tuoi turni. Premi Pausa o Termina per fermare l’invio. L’audio della sessione non viene salvato su disco.
- La dettatura usa un file temporaneo eliminato al termine o all’uscita normale. Un arresto anomalo può lasciare questo file nella cartella temporanea di macOS.
- Le foto non vengono salvate su disco. Nella sessione vocale rimangono nel contesto del servizio fino alla chiusura; la riapertura trasferisce solo testo. L’anteprima non è trasmessa come video.
- La chat Responses usa `store: false`. Non è una garanzia di assenza di log lato fornitore; per Realtime si applicano le politiche del servizio.
- Le API sono a consumo. La pausa automatica non è un tetto di spesa monetario.

## Verifiche e limiti

Compilazione e firma locale verificate. I test offline coprono conversione PCM reale su un segnale sintetico, configurazione dei turni, acquisizione immagini consentita/negata, duplicati, limite delle foto, pausa, trascrizioni, interruzioni e chiusura su errore. Le prove della macchina a stati usano eventi simulati e non sostituiscono una chiamata reale.

Verificati con la chiave salvata: ricerca web con fonte in chat, descrizione automatica della webcam, acquisizione audio e conversazione. I test offline coprono anche citazioni, duplicati di ricerca e sostituzione delle immagini automatiche. La qualità dipende da rete, ambiente e account.

Questa versione non controlla app o domotica, non ascolta una parola di attivazione in background e non equivale al personaggio del film. Può sbagliare risposte e interpretazioni visive.

## Sorgente

`Source/Jarvis.swift` contiene l’interfaccia e la chat; `Source/Realtime.swift` la conversazione audio. `build.command` ricompila e firma l’app; `verify.command` esegue i test senza chiave, rete o accesso ai sensori. Richiedono gli strumenti di sviluppo Apple già disponibili su questo Mac.

Documentazione ufficiale: [conversazioni Realtime](https://developers.openai.com/api/docs/guides/realtime-conversations), [modello vocale](https://developers.openai.com/api/docs/models/gpt-realtime-2.1), [modello della chat](https://developers.openai.com/api/docs/models/gpt-5.5).

Aggiornamento microfono: il percorso VoiceProcessingIO non consegnava audio in ingresso su questo Mac. È stato sostituito con acquisizione PCM tramite AVCaptureSession. Verificati segnale non nullo, trascrizione di un intervento vocale e risposta nella sessione reale.

Corretto anche `string_above_max_length`: gli identificativi delle foto automatiche rispettano ora il limite del servizio. Le note persistenti sono distinte dalla cronologia temporanea; JARVIS non registra automaticamente tutto ciò che dici o vede.

Verifica memoria: salvata una preferenza tramite «Ricorda che…», chiusa e riaperta l’app, ritrovata la stessa nota nelle impostazioni. La ricerca è stata verificata sia in chat sia nella sessione vocale, con fonti cliccabili.

## Risparmio automatico

La conversazione usa Realtime 2.1 Mini. Per problemi complessi può chiamare GPT-5.5 tramite `consult_expert`, poi raccontare la risposta con la voce selezionata. Di’ «usa il massimo» o «pensaci meglio» per richiedere l'approfondimento. Compare «Consulto il modello potente…» e il risultato viene mostrato in chat. Massimo due approfondimenti per intervento; gli errori non vengono presentati come risposte riuscite. La scelta automatica può sbagliare.

La chat scritta fuori dalla conversazione e la ricerca restano su GPT-5.5. La webcam mantiene gli intervalli precedenti; il risparmio del modello vocale non è una riduzione identica del costo totale. Le tre anteprime già salvate non vengono rigenerate.
