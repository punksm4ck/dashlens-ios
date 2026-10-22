# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [4.3.0] - 2026-10-22

### Added
- **DashLens Live (beta)**: a screen-broadcast extension reads the Dasher offer screen on the phone and DashLens shows the verdict as a banner over Dasher, with no taps. New Home card "Start shift + live detection".
- Banners also show while DashLens is open.
- Live status block, Self-test, Banner in 5 s and Copy live report on the Home card, plus a heartbeat from the broadcast extension, so a remote tester can show exactly where the chain stopped.

### Security
- The app-to-extension link is loopback-only UDP and every datagram is size, shape, length and rate checked. See SECURITY.md.
- Today's Numbers shortcut requires the phone to be unlocked. The hotspot Maps link uses https.

## [4.2.0] - 2026-10-20

Brings the iPhone app to the same grading model as Android 4.2.0.

### Added
- Line-by-line vehicle cost on every offer: gas (miles ÷ mpg × gas price) plus wear and tear (per mile), then net pay. New settings: gas price, mpg, wear and tear. The old flat cost per mile still works when "itemize" is switched off, and your logged actual cost still overrides both.
- Shop & deliver time model: "N items" is read from the offer, and shopping time (per item) plus checkout time (per store) replaces the wait at the store. New settings: shopping time per item, checkout time.
- Offers shown with a "+" (a minimum pay) are marked and graded at that minimum, with a note that the real pay may be higher.
- Net $/mi tile, an "against your $X/hr floor, after vehicle costs" line under the verdict, and an optional full-math block on the offer card. Switch it off in Settings for the short reasons.
- Shareable offer card: tap SHARE on any row in Offers to make a picture card (verdict, net $/hr and $/mi, the math, the assumptions) and open the iOS share sheet. Settings > Diagnostics has "Share a sample offer card (test)".
- Settings: "Load typical Dasher assumptions" button (asks first).
- LICENSE (MIT), SECURITY.md, CONTRIBUTING.md, and issue and pull request templates.

### Changed
- The sample offer card is now a sample shop & deliver offer.
- The merchant history screen uses the vehicle cost actually in force (itemized, flat or logged actual).
- Database adds item count and "+" flag to the offer history. Existing data is kept.
- Default vehicle cost is now gas + wear (about $0.33/mi at the default gas price and mpg) instead of a flat $0.30/mi. Turn "itemize" off in Settings to keep the flat rate.
- The unsigned build is published as `DashLens-unsigned.ipa` (stable name, used by the QR code) and `DashLens-<version>-unsigned.ipa`, with a `SHA256SUMS.txt`.

## [4.1] - 2026-10-20

### Added
- First public iPhone test build: Shortcut and Back Tap offer reading with on-device text recognition, mileage log, earnings, expenses, tax view, insights, reports.
