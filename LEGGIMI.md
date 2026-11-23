# VideoRepair per macOS

Ripara i video corrotti (MP4, MOV, M4V, MKV, AVI, MTS…).
È un'app Universal: gira su Mac **Intel** e **Apple Silicon** con **macOS 11 Big Sur** o successivo. ffmpeg è già incluso.
Il file originale non viene mai modificato: il video riparato viene salvato accanto all'originale.

## Installazione

1. Vai nella pagina **Releases** di questo repository e scarica `VideoRepair-x.y.z.pkg`.
2. Aprilo con un doppio clic.
   Se macOS dice "sviluppatore non identificato": **tasto destro sul .pkg > Apri > Apri**.
3. Segui l'installer: l'app finisce nella cartella **Applicazioni**.

Ogni modifica al ramo `main` fa partire GitHub Actions, che compila l'app e pubblica un nuovo `.pkg` tra le Releases.

## Come si usa

- Trascina i video nella finestra, oppure sull'icona nel Dock.
- Finder: **tasto destro > Apri con > VideoRepair**.
- Finder: **tasto destro > Servizi > Ripara video con VideoRepair**.
  Se la voce non compare, attivala in Preferenze di Sistema > Tastiera > Abbreviazioni > Servizi.

## Come ripara

1. **Riparazione rapida (senza perdita di qualità)**: riscrive il contenitore, rigenera i timestamp e scarta i pacchetti danneggiati. Il risultato è `nome_riparato.mov`.
2. **Ricodifica completa**: si usa per glitch, verde o fotogrammi rotti. Il video viene decodificato ignorando gli errori e ricodificato in H.264/AAC. Il risultato è `nome_riparato_ricodificato.mp4`.
3. **Ricostruzione dell'indice**: per i file con errore "moov atom not found", tipico delle riprese interrotte. Servono un **video di riferimento** sano, girato con lo stesso dispositivo, e lo strumento facoltativo `untrunc`.

Dopo ogni tentativo l'app controlla che il risultato si riproduca davvero.

## Compilare da soli (su un Mac con Xcode)

```bash
bash scripts/fetch-ffmpeg.sh vendor/bin
FFMPEG_DIR=vendor/bin ./build.sh
./scripts/make-pkg.sh
```
