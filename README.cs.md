<h3 align="center"><a href="README.md">🇬🇧 English</a> &nbsp;|&nbsp; 🇨🇿 Čeština</h3>

# BakaWidget

Widget do panelu KDE Plasma 6, který zobrazuje vaše nadcházející hodiny
z Bakalářů — aktuální hodinu, co je další, suplování a odpadlé hodiny —
přímo v panelu, s detailním náhledem po najetí myší nebo kliknutí.

## Co umí

- Kompaktní pruh v panelu: předchozí hodina (zašedlá), aktuální hodina
  (zvýrazněná barvou předmětu) a několik dalších nadcházejících hodin
- Po najetí myší nebo kliknutí se zobrazí detail: předmět, učitel,
  místnost, téma a zbytek dne
- Odpadlé hodiny jsou přeškrtnuté, suplované hodiny jsou zvlášť označené
- Zvládá dny bez výuky, výpadky sítě (zobrazí poslední známý rozvrh
  místo prázdného widgetu) i stav "přihlaste se" srozumitelně
- Barvy podle předmětu, vždy stejné

## Co je potřeba

- KDE Plasma 6
- Python 3 a `python-dbus` (na Arch: `pacman -S python python-dbus`)
- KWallet (na Plasmě 6 zapnutý ve výchozím stavu)

## Instalace

```bash
cd bakawidget
./install.sh
```

Tím se nainstaluje widget a nastaví se služba na pozadí, která udržuje
rozvrh aktuální. Poté přidejte **BakaWidget** do panelu (klikněte pravým
na panel → *Přidat widgety…*).

Chcete raději klasický pacman balíček? `makepkg -si` sestaví
`plasma6-applets-bakawidget` — viz [PUBLISHING.md](PUBLISHING.md), pokud
ho chcete zveřejnit v AUR. Pro odinstalaci spusťte `./uninstall.sh`.

## První přihlášení

Klikněte pravým na widget → **Nastavit BakaWidget…** → zadejte subdoménu
vaší školy (část `skola` z `skola.bakalari.cz`), uživatelské jméno a
heslo → **Přihlásit se**. Widget by se měl naplnit během pár vteřin.

Vaše heslo se použije jen jednou k přihlášení a nikde se neukládá — jak
přesně to funguje, viz [SECURITY.md](SECURITY.md) (anglicky).

## Nastavení

- **Interval obnovování** — jak často kontrolovat aktualizace
  (výchozí 15 min)
- **Počet zobrazených hodin** — kolik "kartiček" se zobrazí v pruhu

Obě nastavení se projeví okamžitě, bez nutnosti se znovu přihlašovat.
Změna subdomény nebo uživatelského jména už nové přihlášení vyžaduje,
protože jsou svázané s uloženou relací.

## Reset / odhlášení

Na stránce nastavení klikněte na **Odhlásit se / smazat uložené
přihlašovací údaje**, nebo spusťte:

```bash
python3 ~/.local/share/plasma/plasmoids/bakawidget/contents/backend/bakawidget_backend.py logout
```

## Řešení problémů

Pokud hodiny, suplování nebo předměty vypadají špatně, jde
pravděpodobně o rozdíl ve schématu API konkrétní školní instance
Bakalářů (viz [SECURITY.md](SECURITY.md#known-limitations), anglicky).
Spusťte:

```bash
python3 ~/.local/share/plasma/plasmoids/bakawidget/contents/backend/bakawidget_backend.py debug-dump
```

a výstup přiložte k nahlášení problému (issue) — jména jsou před
vypsáním automaticky začerněná, ale i tak si výstup nejdřív sami
prohlédněte.

## Jak to funguje

- **`contents/ui/`** — samotný widget (QML, Kirigami). Čistě
  zobrazovací vrstva; nikdy nekomunikuje po síti ani nevidí vaše heslo.
- **`contents/backend/bakawidget_backend.py`** — malý Python démon, který
  má na starosti přihlášení, obnovu tokenu, ukládání do KWalletu a
  stahování rozvrhu.
- Tyto dvě části spolu komunikují přes JSON soubor (`state.json`), který
  backend zapisuje a widget čte, plus jednorázové příkazy (přihlásit se,
  odhlásit se, změnit interval) pro vše, co se má stát jen jednou.
- Backend běží nepřetržitě jako služba `systemd --user`, takže je rozvrh
  aktuální bez ohledu na to, jestli je widget zrovna vidět.

## Vývoj

```bash
plasmoidviewer -a bakawidget
```

Načte widget samostatně pro rychlé testování změn, bez nutnosti
kompletní instalace a restartu panelu. Kde a proč se QML verze liší od
původního návrhu ve Figmě, popisuje [DESIGN_NOTES.md](DESIGN_NOTES.md)
(anglicky).

## Zabezpečení

Vaše heslo se nikdy neukládá — celý model (co se kde ukládá, jak funguje
přihlášení a jaká jsou známá omezení) je popsaný v
[SECURITY.md](SECURITY.md) (anglicky).

## Licence

MIT — viz [LICENSE](LICENSE).
