# Tubio

Natywna aplikacja macOS (SwiftUI) do pobierania wideo z serwisów streamingowych, zbudowana jako lekki, wizualny wrapper na [yt-dlp](https://github.com/yt-dlp/yt-dlp) i [ffmpeg](https://ffmpeg.org/). Styl okna, ikon i kontrolek nawiązuje do [Movi](../Movi). Okno podąża za wyglądem systemu (jasne/ciemne — w tym tryb "Auto" w Ustawieniach systemowych, przełączający się o zachodzie/wschodzie słońca), zamiast być na sztywno jasne lub ciemne.

## Skąd ten projekt się wziął

Punktem wyjścia była analiza otwartoźródłowego projektu **Open Video Downloader** (youtube-dl-gui, autor: Jelle Glebbeek, licencja **AGPL-3.0-or-later**, Tauri 2 + Rust + Vue 3) — solidnej, dobrze zaprojektowanej aplikacji o tej samej ogólnej funkcji.

Pierwsza wersja Tubio była świadomie *luźno* inspirowana tamtym kodem (własny, prostszy dobór formatu, własny mechanizm wykrywania ścieżki pliku wynikowego) — głównie z myślą o licencji AGPL-3.0, która przy dystrybucji/sprzedaży wymagałaby udostępnienia całego kodu pochodnego na tej samej licencji. Skoro Tubio jest **wyłącznie na Twój własny użytek** (nie jest sprzedawana ani rozpowszechniana), to ograniczenie przestaje mieć zastosowanie — AGPL dotyczy dystrybucji, nie prywatnego kompilowania i używania.

W tej wersji silnik pobierania (dobór formatu `-f`/`-S`, szablon postępu, sposób ustalania finalnej ścieżki pliku) jest więc **wiernym portem** rzeczywistej logiki z `src-tauri/src/runners/ytdlp_args/format_args.rs`, `output_args.rs` i `ytdlp_runner.rs` tamtego projektu — przepisanym na Swift, nie kopiowanym linia-po-linii z Rusta (inna składnia, inny model współbieżności), ale obliczającym te same selektory i flagi `yt-dlp`, zamiast własnej, uproszczonej wersji, która w praktyce działała inaczej. Gdybyś kiedyś chciał udostępnić lub sprzedać tę aplikację, warto wrócić do kwestii licencji — na razie, przy czysto prywatnym użytku, nie jest to problem.

Ikona i branding pozostają własnym projektem (patrz niżej) — to osobna decyzja, niezwiązana z licencją kodu.

## Ikona i branding

Aktualna ikona to grafika, którą dostarczyłeś bezpośrednio (czerwony zaokrąglony kwadrat, biały panel wewnątrz, czarna strzałka pobierania) — nie generuję jej już sama. Jedyna obróbka, jaką jej zrobiłem: usunąłem checkerboard (szachownicę oznaczającą przezroczystość w podglądzie) i wyeksportowałem ją w rozmiarach wymaganych przez macOS (16–1024 px, 1x/2x).

Plik źródłowy (1024×1024, już z usuniętym tłem) jest w `icon-source/tubio-icon-1024.png` — to z niego wygenerowane są wszystkie rozmiary w `Sources/Assets.xcassets/AppIcon.appiconset/` (ikona Docka/Findera) i `BrandMark.imageset/` (mały znak w nagłówku okna, obok nazwy aplikacji — używa tej samej grafiki, przeskalowanej). Wcześniejszy, generowany programistycznie wariant ikony (`icon-source/gen_icon.py`) został usunięty, bo nie jest już używany.

Ta ikona (czerwony kwadrat + strzałka w dół) nie odwzorowuje znaku towarowego YouTube (czerwony prostokąt + biały trójkąt odtwarzania skierowany w bok) — to inny, bardziej generyczny motyw "pobierania", wspólny dla wielu aplikacji tego typu — ale warto wiedzieć, że to Twoja własna grafika, nie coś, co zweryfikowałem pod kątem praw do niej; jeśli pochodzi skądś indziej, to już Twoja ocena, czy możesz jej używać.

## Czego aplikacja robi

- Wklejasz URL filmu → Tubio pyta `yt-dlp -J` o metadane (tytuł, miniaturę, czas trwania, dostępne rozdzielczości) — większe miniatury w kolejce niż w pierwszej wersji, żeby łatwiej rozpoznać film na pierwszy rzut oka.
- Wybierasz jakość (najlepsza / konkretna rozdzielczość / tylko audio jako MP3) — selektor formatu (`-f`/`-S`) jest wiernym portem tego, co faktycznie buduje oryginalny projekt dla tego samego wyboru, a nie własną, uproszczoną wersją.
- Tubio odpytuje `yt-dlp` z `--progress-template` o dokładnie taki sam zestaw pól co oryginalny projekt, żeby dostać postęp pobierania w formacie, który łatwo sparsować (a nie ludzki pasek postępu z terminala), i pokazuje go jako pasek + prędkość + ETA.
- Finalną ścieżkę pliku Tubio ustala tak samo jak oryginalny projekt: obserwując zwykłe, tekstowe linie, które `yt-dlp` i tak drukuje w trakcie pracy (`[download] Destination: …`, `[Merger] Merging formats into "…"`, `[VideoRemuxer] Destination: …`, …) i zapamiętując tę o najwyższej "pewności" — a nie przez osobną flagę `--print`, która w pierwszej wersji była jedynym, nie do końca sprawdzonym w boju sposobem.
- Kolejka obsługuje kilka pobrań równocześnie (limit ustawiany w Ustawieniach), **wstrzymanie/wznowienie** (prawdziwe `SIGSTOP`/`SIGCONT`, nie tylko wizualne — patrz niżej), anulowanie, ponawianie nieudanych, "Pokaż w Finderze" / "Otwórz".
- Okno jest jasne lub ciemne zależnie od wyglądu systemu (Ustawienia systemowe → Wygląd), bez wymuszania jednego motywu — tak samo ikony: wszystkie neutralne (nie czerwone) ikony w interfejsie śledzą ten sam systemowy kolor etykiety co ikona Ustawień (ciemne w jasnym motywie, jasne w ciemnym).
- W Ustawieniach: sprawdzanie i instalowanie aktualizacji `yt-dlp`/`ffmpeg` przez Homebrew (patrz "Sprawdzanie aktualizacji" niżej).
- Przy pierwszym uruchomieniu na danym komputerze, jeśli `yt-dlp`/`ffmpeg` akurat nie są jeszcze zainstalowane, Tubio od razu pokazuje krótki monit o tym (patrz "Pierwsze uruchomienie" niżej) — zanim jeszcze spróbujesz dodać link.
- Interfejs mówi po polsku lub po angielsku automatycznie, zależnie od języka systemu (patrz "Język aplikacji" niżej) — bez przełącznika w Ustawieniach.

## Czego aplikacja **nie** robi (świadomie)

- **Nie pobiera i nie uruchamia `yt-dlp`/`ffmpeg` za Ciebie.** Open Video Downloader ma cały system do tego: podpisany Ed25519 manifest, weryfikację SHA-256, pobieranie binarek z internetu. To poważny, dobrze zrobiony mechanizm — ale też większa powierzchnia ataku (trzeba ufać serwerowi z manifestem) i więcej kodu do utrzymania. Tubio zamiast tego **szuka** `yt-dlp`/`ffmpeg` zainstalowanych przez Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `~/.local/bin`) albo w `PATH`. Jeśli ich nie znajdzie, pokazuje ekran z gotowym do skopiowania `brew install yt-dlp ffmpeg`.
- **Nie zarządza żadnymi danymi logowania** do serwisów (OVD ma do tego cały moduł Stronghold + OS keyring, bo obsługuje pliki cookies/loginy). Tubio celowo tego nie dotyka — nie ma żadnego magazynu sekretów, bo nic takiego nie przechowuje.
- **Nie ma Sandboxa** (`App Sandbox`), w przeciwieństwie do Movi. Sandbox jest fundamentalnie niekompatybilny z szukaniem/odpalaniem dowolnych binarek zainstalowanych przez użytkownika w dowolnym miejscu i zapisem do dowolnie wybranego folderu docelowego. Aplikacja jest budowana pod dystrybucję poza Mac App Store (podpisana + notaryzowana), nie pod sam Store.
- **Nie obsługuje jeszcze playlist** — model `PlaylistInfo` jest zdefiniowany, ale nie podłączony do UI. Jedno-URL-na-raz, na razie.
- **Pauza pobrania przez ffmpeg nie jest objęta.** Samo "Wstrzymaj" działa naprawdę — wysyła `SIGSTOP` do procesu `yt-dlp` (patrz "Pauza/wznów" niżej) — ale jeśli dane już trafiły do osobno odpalonego `ffmpeg` (łączenie/przekodowanie po ściągnięciu), ten proces nie jest zamrażany, bo działa jako własne, niezależne dziecko. W praktyce pauza ma sens głównie w fazie samego ściągania, czyli przez większość czasu trwania pobrania.

## Pauza/wznów

"Wstrzymaj" na trwającym pobraniu wysyła realny sygnał Unix `SIGSTOP` do procesu `yt-dlp` — to ten sam mechanizm, co `Ctrl+Z` w terminalu: proces dosłownie zamiera (zero zużycia CPU, zero transferu), a nie tylko "udaje" wstrzymanie w interfejsie. "Wznów" wysyła `SIGCONT` i proces kontynuuje od tego samego miejsca, bez utraty już ściągniętych danych. "Anuluj" na wstrzymanym pobraniu najpierw wysyła `SIGCONT` (sygnał `SIGTERM` wysłany do zamrożonego procesu czekałby w kolejce, nieobsłużony, aż do wznowienia), a potem normalnie kończy proces.

Analizowany oryginalny projekt **nie ma** w ogóle funkcji pauzy/wznowienia (sprawdzone w jego źródłach — nie ma śladu `pause`/`SIGSTOP`/`suspend` w kodzie Rust) — to własna funkcja Tubio, dodana na Twoją prośbę, a nie port niczego istniejącego.

Ograniczenie: to zamraża tylko sam proces `yt-dlp`. Jeśli pobieranie zdążyło już przejść do fazy łączenia/przekodowania przez osobno odpalony `ffmpeg`, ten proces-dziecko działa dalej — patrz uwaga w sekcji "Czego aplikacja nie robi" wyżej.

## Sprawdzanie aktualizacji (yt-dlp / ffmpeg)

W Ustawieniach jest sekcja "yt-dlp / ffmpeg" z przyciskiem "Sprawdź aktualizacje" (uruchamia `brew outdated --quiet yt-dlp ffmpeg` i pokazuje aktualne wersje obu narzędzi) oraz, gdy jest co aktualizować, przyciskiem "Zaktualizuj" (`brew upgrade yt-dlp ffmpeg`).

To jest **adaptacja**, nie port mechanizmu aktualizacji z analizowanego oryginalnego projektu — i warto rozumieć różnicę. Oryginał (`binaries_manager.rs` + moduł `commands/updater/`) ma dwa zupełnie osobne systemy: (1) własny system aktualizacji binarek yt-dlp/ffmpeg — podpisany Ed25519 manifest, weryfikacja SHA-256, pobieranie z własnych serwerów hostujących te binarki, i (2) niezwiązany z tym samoaktualizujący się mechanizm samej aplikacji Tauri (`tauri_plugin_updater`). Punkt (1) nie ma czego portować: Tubio nie zarządza własnymi kopiami yt-dlp/ffmpeg (patrz `BinaryLocator`) i nie ma żadnego serwera hostującego binarki, do którego taki port mógłby się odnosić. Zamiast udawać port nieistniejącego u Tubio systemu, `HomebrewUpdater` robi to, co i tak zrobiłbyś ręcznie w Terminalu — pyta Homebrew, który już zarządza tymi binarkami na Twoim systemie.

## Pierwsze uruchomienie

Przy samym pierwszym uruchomieniu Tubio na danym komputerze (zapamiętane w `UserDefaults`, więc pokazuje się dokładnie raz, nigdy więcej) — jeśli `yt-dlp`/`ffmpeg` akurat nie są zainstalowane w tym momencie — wyskakuje krótki alert "Witaj w Tubio" z informacją, że do pobierania wideo potrzebne są te dwa narzędzia, zanim jeszcze dojdzie do próby dodania linka. To celowo *dodatek* do istniejącego ekranu "Brakuje yt-dlp i/lub ffmpeg" (`MissingToolsView`), nie jego zamiennik — ten ekran z gotowym do skopiowania `brew install yt-dlp ffmpeg` nadal pokazuje się za każdym razem, gdy narzędzia są niedostępne, tak długo jak długo faktycznie ich brakuje. Jeśli przy pierwszym uruchomieniu `yt-dlp`/`ffmpeg` już są zainstalowane, alert się nie pojawia — nie ma czego sygnalizować.

## Język aplikacji

Interfejs jest teraz w pełni zlokalizowany: polski i angielski, wybierane automatycznie na podstawie języka systemu (Ustawienia systemowe → Ogólne → Język i region) — bez przełącznika w samej aplikacji, bo macOS robi to sam dla każdej poprawnie zlokalizowanej aplikacji. Jeśli system jest w innym języku niż te dwa, Tubio pokazuje polski (to język źródłowy tekstów w kodzie).

Technicznie: wszystkie napisy w interfejsie są kluczami w `Sources/Resources/Localizable.xcstrings` (String Catalog, natywny dla Xcode 15+) — kluczami są same polskie teksty z kodu, a plik dodaje do nich angielskie tłumaczenia. Dodanie kolejnego języka to dopisanie w tym pliku trzeciej listy tłumaczeń, bez zmian w Swifcie. Kilka rzeczy zostało świadomie bez tłumaczenia, bo są identyczne w obu językach albo to nie są słowa: nazwa aplikacji, nazwy narzędzi (`yt-dlp`, `ffmpeg`, `brew`), etykiety rozdzielczości (`1080p` itd.) i składnia szablonu nazwy pliku (`%(title)s.%(ext)s`).

## Wymagania

- macOS 14+
- [Homebrew](https://brew.sh)
- `yt-dlp` i `ffmpeg`: `brew install yt-dlp ffmpeg`
- Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen) do zbudowania projektu z `project.yml` (`brew install xcodegen`)

### Odinstalowanie yt-dlp / ffmpeg

```bash
brew uninstall yt-dlp ffmpeg
```

Przydatne np. przy czystej reinstalacji, jeśli podejrzewasz uszkodzoną/przestarzałą instalację. Po odinstalowaniu Tubio pokaże ekran "Brakuje yt-dlp i/lub ffmpeg" z gotową komendą instalacyjną.

## Budowanie

```bash
cd Tubio
xcodegen generate
open Tubio.xcodeproj
```

## Architektura (krótko)

- `Services/BinaryLocator.swift` — szukanie `yt-dlp`/`ffmpeg`/`brew` na dysku.
- `Services/HomebrewUpdater.swift` — sprawdzanie i instalowanie aktualizacji `yt-dlp`/`ffmpeg` przez `brew outdated`/`brew upgrade` (patrz "Sprawdzanie aktualizacji" wyżej).
- `Services/YtdlpArgs.swift` — budowanie tablic argumentów (nigdy stringa do shella) dla każdego wywołania `yt-dlp`; selektor formatu, pola sortowania i flagi postprocessingu to port rzeczywistej logiki oryginalnego projektu (patrz wyżej).
- `Services/YtdlpRunner.swift` — bezpieczne odpalanie `Process`, strumień zdarzeń (`AsyncStream<YtdlpEvent>`) z postępem/stderr/finalną ścieżką pliku/kodem wyjścia; czyta zarówno stdout, jak i stderr tak jak oryginalny silnik.
- `Services/ProgressParser.swift` — parsowanie linii `RAW|...` z `--progress-template` (identyczny zestaw pól co oryginał, z tym samym łańcuchem fallbacków przy liczeniu procentu).
- `Services/DestinationParser.swift` — ustalanie finalnej ścieżki pliku z linii `yt-dlp` typu "Destination:"/"Merging formats into", z systemem "pewności" identycznym jak w oryginale.
- `Models/` — `MediaInfo`/`YtdlpFormat` (dekodowanie JSON z `yt-dlp -J`), `DownloadItem`/`DownloadProgress`/`DownloadState`.
- `ViewModels/DownloadQueueViewModel.swift` — kolejka, limit równoczesnych pobrań, ustawienia w `UserDefaults`.
- `Views/` — `ContentView` (główne okno, jasne/ciemne zależnie od systemu, pierwsze-uruchomienie alert), `DownloadCardView` (wiersz kolejki z większą miniaturą), `SettingsView`, `MissingToolsView`.
- `Resources/Localizable.xcstrings` — String Catalog z tłumaczeniami wszystkich napisów interfejsu (polski → angielski); patrz "Język aplikacji" wyżej.

## Odpowiedzialne korzystanie

Tubio to narzędzie ogólnego przeznaczenia do pobierania wideo — tak jak `yt-dlp` samo w sobie, czy dziesiątki podobnych GUI. Nie omija żadnych zabezpieczeń DRM, nie udostępnia treści chronionych prawem autorskim nikomu innemu, nie łamie żadnych zamków technicznych. To, co pobierzesz i co z tym zrobisz, podlega regulaminowi serwisu, z którego pobierasz, oraz obowiązującemu prawu autorskiemu w Twojej jurysdykcji — to Twoja odpowiedzialność jako użytkownika, tak jak przy każdym innym narzędziu tego typu.
