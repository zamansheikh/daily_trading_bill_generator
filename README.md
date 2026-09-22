# Daily Trading Bill Generator

Turns buyer purchase-order PDFs (Daily Shopping and Best Buy, both issued by
Desh Logistics) into Daily Trading Corporation memos: one Letter-size PDF per
PO, laid out like the Excel memo, with Bangla product names and Bengali serial
numbers.

One Flutter code base, pure Dart, no Python side-car: it runs on Windows,
macOS, Linux, Android and iOS.

## How it works

1. **Import** - drop or pick PO PDFs. A file may contain many POs and a PO
   may span pages. Text is read with word positions; the table columns are
   located from the header row on each page, so layout differences between
   the two buyers do not matter.
2. **Verify** - every line is checked (`qty x rate - discount = total`), the
   lines are summed against the PO grand total and serial numbers are checked
   for gaps. Anything off is shown as a warning on the order.
3. **Match** - each PO line is matched to the catalogue by code. Best Buy uses
   its own 6-digit codes, so those are matched by normalised name + size the
   first time and the code is remembered as an alias afterwards. Unmatched
   lines are highlighted and can be assigned by hand.
4. **Generate** - memos get sequential numbers, are rendered to
   `<output folder>/<supply date>/<memo no>(<outlet>).pdf` and recorded in
   History. Prices from the PO update the chain's price list (optional).

### Excel export

With "Also export Excel (.xlsx)" on in Settings (the default), every memo is
also written as `<memo no>(<outlet>).xlsx` next to the PDF, built by
`lib/core/memo/memo_xlsx.dart`. The workbook has the same layout (letterhead,
black label cells, two side-by-side tables, Bangla names, Bengali serials),
prints on one Letter page, and uses live formulas: each amount is
`qty x unit price` and the total sums both amount columns, so a quantity can
be corrected in Excel and the sheet recalculates. Bangla cells use the
Nirmala UI font, which ships with Windows.

### Backfilling missing values

Nothing is ever guessed silently; the app proposes and you apply:

- **Parser**: a PO line missing one of quantity, rate or total gets it computed
  from the other two and is flagged in the order's warnings.
- **Order page, "Fill missing"**: lists proposals with a confidence label:
  the closest catalogue product for an unmatched line (typos included),
  quantity or rate computed from the other columns or taken from the list
  price, a default memo name, blank chain prices filled from the other chain
  and missing Bangla names taken from a sibling size. Tick what you want and
  press Apply.
- **Catalogue, magic-wand menu**: fill all blank Best Buy (or Daily Shopping)
  prices from the other chain's list in one go.

## Project layout

| Path | What |
| --- | --- |
| `lib/core/parsing/` | `pdf_words.dart` (positioned word extraction), `po_parser.dart` (PO table parser and verification) |
| `lib/core/catalog/` | `seed_catalog.dart` (78 products, Bangla names, both price lists, Best Buy aliases), `product_matcher.dart` |
| `lib/core/memo/` | `memo_builder.dart` (PO + catalogue -> memo rows), `memo_pdf.dart` (PDF layout), `memo_xlsx.dart` (Excel layout) |
| `lib/core/suggest/suggestions.dart` | Suggestion engine behind "Fill missing" |
| `lib/data/app_database.dart` | SQLite storage (products, prices, aliases, outlets, orders, memos, settings) |
| `lib/app/` | State (`AppState`) and screens: Import, History, Catalogue, Settings |
| `sample_pdf/` | Reference inputs and outputs used by the tests |
| `installer/` | Inno Setup script for the Windows installer |

## Build

```bash
flutter pub get
flutter test                       # parser, matcher, memo, database and UI-layout tests
flutter run -d windows             # or macos / linux / an Android device
```

Test memos are written to `build/test_memos/` when the tests run.

### Windows installer

On a Windows PC:

1. `flutter build windows --release`
2. Open `installer/daily_trading_bill_generator.iss` in Inno Setup 6 and
   click Compile. The setup exe lands in `installer/output/`.

Or let GitHub build it: the "Release builds" workflow
(`.github/workflows/windows-installer.yml`) runs on every push to `main`, on
tags such as `v1.0.0`, and by hand from the Actions tab. It builds the Windows
setup exe and the Android APK and publishes both on a GitHub release: the tag
name for tag pushes, otherwise `v<version from pubspec.yaml>` as a pre-release
that is updated in place.

The installer uses the app icon, closes a running copy before upgrading and
offers a desktop shortcut.

### Android

`flutter build apk --release` (or `flutter run` on a connected phone). On
Android there is no output-folder setting: memos are saved in the app's
private documents folder and handed on with the system share sheet after
generation, from the History tab, or from an order's detail page.

### App icon

`assets/icon/app_icon.png` is drawn by `dart run tool/make_icon.dart`.
`dart run flutter_launcher_icons` fans it out to Windows, macOS, iOS and
Android (adaptive icon) from the config in `pubspec.yaml`.

## Screens

The layout adapts to the window: a navigation rail (expanded above 900px)
on desktop and tablets, a bottom bar on phones. Order lists become full-width
tiles and the items table becomes cards below 600px. `test/widgets_test.dart`
renders every screen at phone, tablet and desktop sizes.

## Built-in catalogue

The catalogue that ships with the app (78 products, Bangla names, Daily
Shopping and Best Buy price lists, Best Buy code aliases) is written into the
database on first launch. Add or edit products in the Catalogue tab; Settings
has "Restore shipped catalogue" to go back to the built-in data without
touching orders or memos.

## Notes on the data

- Codes follow the buyers' POs. The old Excel template had Araroot 100gm and
  200gm codes swapped (5000000627 / 5000000628) and used the Cardamom code
  for Isobgul Bhushi, and 5000000387 for Star Masala (POs use 5000000386); the
  catalogue here uses the codes that appear on POs.
- "Order date" on the memo is filled with the PO date.
- The Best Buy memo hides the seven products that never appear on Best Buy
  POs (papor items and walnut); toggle them in Catalogue if needed.
