# Kirole App Store screenshot refresh

Three English screenshots for the next App Store version. The visual direction is a small daily ritual: begin the day, share it with a companion, then make room for focus.

| Order | File | Message |
| --- | --- | --- |
| 1 | `screenshots-en/01-a-gentler-start.png` | A gentler start. |
| 2 | `screenshots-en/02-a-little-company.png` | A little company. |
| 3 | `screenshots-en/03-room-to-focus.png` | Room to focus. |

## Design and references

Warm paper, forest green and sage form a coherent triptych. Book-style serif headlines, numbered chapters, fine rules and concentric rings establish the ritual. Each panel contains one short message and one intact App screenshot. All copy outside the App UI is English.

- [Apple asset best practices](https://developer.apple.com/app-store/asset-best-practices/): a clear focal point, legible short text, and imagery grounded in the actual experience.
- [Apple product page guidance](https://developer.apple.com/app-store/product-page/): prioritize the first screenshots and communicate the core experience.
- [Stoic screenshot design reference](https://dribbble.com/shots/27232248-App-Store-Screenshots-stoic-journal-mental-health): restrained editorial hierarchy and generous typography. Reference only; no artwork copied.
- [Finch screenshot reference](https://www.shyftup.com/blog/finch-aso-audit-reports/): companion-led storytelling and a sequence of single-message panels. Reference only; no artwork copied.

## Source integrity

The UI images are referenced directly from `../2026-08-22/screenshots-en/`, without repainting, rearranging, recoloring, or inventing App components. Their MD5 checksums were matched to all three screenshots of live App Store version 2.0.1 on 2026-09-07:

```text
9bdc2a7a69e38640296cd1e7ed1525a6  01-home-timeline.png
2dadf1e02e4a6d4926276990bdadd5ca  02-pet-today.png
5168b115b4fa6bc2170aa31506b8f147  03-settings-privacy.png
```

Only the surrounding graphic layout is new. These marketing assets do not establish acceptance of a new binary, firmware or hardware feature. Historical candidate records are retained as historical records.

## Editable source and verification

`artwork.html` contains the layout. `render.cjs` uses Playwright to render each 440×956 artboard at 3×, validates 1320×2868 RGB PNG without alpha, and writes `SHA256SUMS` and `contact-sheet.png`.

With Node.js and Playwright available:

```sh
node docs/app-store/2026-09-07/render.cjs
```

Verification completed: all three source images load; all PNGs meet dimensions and color requirements; the overview was visually inspected; an independent code review passed after correcting footer clearance. No App code was changed.

## App Store replacement

Apple only allows screenshot updates on an editable version. Version 2.0.1 was already `READY_FOR_SALE`, and no editable version existed at the initial read-back. A 2.0.2 draft is used for this screenshot refresh. The live 2.0.1 storefront changes only after a subsequent version is reviewed and released.

Replacement completed in version 2.0.2: exactly three new screenshots remain in `en-US` / `APP_IPHONE_67`, in the intended order, all `COMPLETE` with matching local MD5 checksums. The inherited old screenshots were removed only after all new images were verified. The exact version/set identifiers and initial upload evidence are recorded in `asc-readback.json`.

Version 2.0.2 (Build 661) was submitted for App Review on 2026-09-07 at 08:24 Asia/Shanghai. Apple read-back confirms `WAITING_FOR_REVIEW`; see `submission-readback.json` and `SUBMISSION-RECORD.md`. The user waived a new real-device smoke after the complete source comparison confirmed only version/build-number changes from approved 2.0.1 (659). The connected phone retains Build 662 and its Outlook test state. The refreshed screenshots have not yet been released on the live storefront.

[Apple screenshot upload rules](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
