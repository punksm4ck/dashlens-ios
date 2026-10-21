# DashLens for iPhone (v4.1)

**Testing the iPhone build? Start here: [TESTER-GUIDE.md](TESTER-GUIDE.md)**


Offer analyzer, mileage log, earnings, expenses and tax estimates for DoorDash Dashers, ported from the Android app.
Everything stays on the phone. No account, no servers, no analytics.

> **Read this first: what is different from Android**
>
> 1. **No live overlay.** Android's version reads the Dasher screen with an Accessibility Service and draws the card on top of it. iOS has no equivalent: no app can read or draw over another app, and there is no jailbreak-free way around that. On iPhone you trigger a shortcut (Back Tap or the Action Button) while an offer is on screen. It takes a screenshot, DashLens reads it **on the phone** (Apple's Vision text recognition), and the TAKE / MAYBE / DECLINE card pops up in about two seconds. Offers expire fast, so this is slower than the Android card.
> 2. **Online / On order is manual.** Android guesses it from Dasher's screens. On iPhone you tap **On order** when you accept (or Back Tap "I Accepted the Offer") and **Online** when the order is done. DashLens still learns your real order times and merchant history from that.
> 3. **No auto-stop, no "Dasher looks active" prompt**, for the same reason.
> 4. **Weekly files are saved when you open the app**, not at Sunday 23:59 (iOS can't run code on a timer). A Sunday reminder notification tells you to open it.
> 5. **This code has not been compiled or run on a device.** It was written without access to Xcode or macOS. The first GitHub build is its first compile. If it fails, see [If the build fails](#if-the-build-fails).

Everything else matches the Android app: same verdict math, same filters and presets, same merchant and pace learning, same earnings / expenses / receipts / tax view, insights, reports and CSV exports.

---

## Which iPhones

Built for the four newest iPhone generations as of October 2026, and everything back to iOS 17:

| Generation | Models |
|---|---|
| iPhone 18 | 18 Pro, 18 Pro Max (base iPhone 18 is expected spring 2027; it will work too) |
| iPhone 17 | 17, Air, 17 Pro, 17 Pro Max, 17e |
| iPhone 16 | 16, 16 Plus, 16 Pro, 16 Pro Max, 16e |
| iPhone 15 | 15, 15 Plus, 15 Pro, 15 Pro Max |

Minimum is **iOS 17.0**, so it also installs on iPhone 12 and newer. It runs on iOS 27 (released September 14, 2026). No jailbreak is needed or used.

---

## Step 1. Get the app file (.ipa)

You cannot build an iPhone app on Windows or Linux, so GitHub builds it on a free Mac in the cloud (the same way your Android APK is built).

1. Create a new GitHub repository (**public** is simplest: macOS build minutes are free for public repos; on a private repo they cost 10x and the free allowance runs out fast).
2. Put the contents of this folder at the **root** of that repo, including the hidden `.github` folder. The easiest reliable way is Git or GitHub Desktop. If you use the web uploader and the `.github` folder doesn't come across, use *Add file > Create new file*, type `.github/workflows/build-ios.yml` as the name, and paste in that file.
   - To put it inside your existing Android repo instead, place the folder as `ios/`, move `build-ios.yml` into the repo's `.github/workflows/`, and add `working-directory: ios` under each `run:` step.
3. Open the **Actions** tab. The workflow **Build iOS IPA (unsigned)** runs on every push, or click **Run workflow**. It takes roughly 5 to 10 minutes.
4. When it finishes, open the run and download the **DashLens-iOS-ipa** artifact (a zip). Unzip it to get `DashLens-4.1-unsigned.ipa`.

The file is *unsigned* on purpose: Step 2 signs it with your own Apple ID.

### If the build fails
Open the failed run and download the **build-log** artifact, or copy the red error lines from the log. Send them back to Claude and the fix is usually a one-line change. First builds of new code commonly need one or two rounds.

---

## Step 2. Install on your iPhone (no jailbreak)

Apple only runs apps that are signed. Without the App Store, you sign the .ipa yourself with a free Apple ID. Pick **one** route.

### What every route has in common
- A **free Apple ID** works. Use a separate one just for this if you prefer; the tools send the credentials to Apple only.
- **Free-account limits:** the app stops opening after **7 days** until it is re-signed ("refreshed"), and you can have **3** sideloaded apps at once. A paid Apple Developer account ($99/year) lifts both: signing lasts a year.
- Your iPhone must have **Developer Mode** on (iOS 16 and later). See [Developer Mode](#developer-mode).

### Route A: Sideloadly (recommended, Windows or Mac)
1. Install **Sideloadly** from sideloadly.io. On Windows it also needs **iTunes** installed from apple.com (the downloadable version, *not* the Microsoft Store one). Follow the requirements on the Sideloadly download page, as they change.
2. Connect the iPhone with a cable. Tap **Trust This Computer** on the phone and enter your passcode.
3. Open Sideloadly. Drag `DashLens-4.1-unsigned.ipa` onto it, enter your Apple ID, and click **Start**. Enter your password and the 2-factor code when asked.
4. On the phone: **Settings > General > VPN & Device Management**, tap your Apple ID under *Developer App*, then **Trust**.
5. Turn on [Developer Mode](#developer-mode) if you haven't, then open DashLens.
6. **Every 7 days:** connect the phone, open Sideloadly and install the same .ipa again. This refreshes the signature **and keeps your data**. Do not delete the app first.

### Route B: AltStore (refreshes itself while your computer is on)
1. Install **AltServer** on your Windows PC or Mac from altstore.io. On Windows it needs iTunes and iCloud from apple.com, not the Microsoft Store.
2. Connect the phone, click the AltServer icon in the system tray / menu bar > **Install AltStore** > your iPhone, and sign in with your Apple ID.
3. Trust the profile on the phone (same as Route A, step 4). Open **AltStore**.
4. Send `DashLens-4.1-unsigned.ipa` to the phone (AirDrop, iCloud Drive or the Files app), open AltStore > **My Apps** > **+** and pick the file.
5. Leave AltServer running on your computer, on the same Wi-Fi as the phone. AltStore refreshes DashLens in the background before the 7 days are up.

### Route C: SideStore (refreshes from the phone itself)
SideStore refreshes apps on the phone with no computer around, after a one-time computer-assisted setup. It is more fiddly, and iOS releases sometimes break it for a while. Use the official guide at sidestore.io for your iOS version, then install the .ipa through it. Good for drivers who are rarely at a computer.

### Route D: Xcode on a Mac
Install Xcode (free), open Xcode > Settings > Accounts and add your Apple ID. Run `xcodegen generate` in this folder (`brew install xcodegen`), open `DashLens.xcodeproj`, set **Signing & Capabilities > Team** to your Apple ID, pick your iPhone and press Run. Same 7-day limit on a free account.

### Route E: paid Apple Developer account ($99/year)
Sign the same .ipa with Sideloadly or AltStore using the paid account for one-year signing, or archive in Xcode and use TestFlight (builds last 90 days). Worth it if the weekly refresh becomes a nuisance.

### Developer Mode
**Settings > Privacy & Security > Developer Mode** (scroll to the bottom) > on > restart > **Turn On** after the restart. It only appears after you've sideloaded something. If you can't find it, install the app first, then look again.

### Troubleshooting the install
- **"Untrusted Developer" / app won't open:** do the Trust step (VPN & Device Management).
- **App opens, then closes immediately, or says the app is unavailable:** it expired. Refresh it (Route A step 6 / AltStore refresh).
- **"Maximum number of apps" or "App ID limit":** a free Apple ID allows 3 active sideloaded apps and a limited number of new app IDs per week. Remove another sideloaded app, or wait a few days.
- **Apple ID sign-in fails in the tool:** check you're on the latest version of Sideloadly/AltServer. Tools sometimes need an update after a new iOS release.
- **Reinstalling:** installing the new .ipa *over* the old one keeps your data. **Deleting the app erases the database.** Export your reports regularly (see below).

---

## Step 3. First run

1. Open DashLens, read the welcome screen, tap **Allow location and notifications**.
2. Location: choose **Allow While Using**, then when iOS asks, **Change to Always Allow**. Always is what lets mileage keep logging while Dasher is open and the phone is locked. (You'll see the blue location indicator during a shift: that is iOS telling you the app is logging.)
3. Settings > pick a profile (Strict / Balanced / Easygoing) and set your vehicle cost per mile and other assumptions.

### Set up the offer card (Back Tap)
1. Open the **Shortcuts** app > **+** (new shortcut).
2. Add the action **Take Screenshot**.
3. Add the action **Analyze Dasher Offer** (search "DashLens"). Drop the **Screenshot** result into its *Screenshot* field.
4. Name it **Dash Check**.
5. **Settings > Accessibility > Touch > Back Tap > Double Tap** > choose **Dash Check**.
6. Optional: make a second shortcut with the DashLens action **I Accepted the Offer**, and put it on **Triple Tap**. If your phone has an Action Button, **Settings > Action Button > Shortcut** works too.

Test it without a real offer: Home > **Test with a saved Dasher screenshot**, and pick a screenshot you took of an offer earlier. The same screen shows exactly what text was read, which is what you'd send back if the card needs tuning.

### A normal shift
1. Go online in Dasher. Open DashLens once and tap **Start shift** (or run the **Start Shift** shortcut by voice or Back Tap).
2. Offer arrives: double-tap the back of the phone. Card appears. Decide in Dasher.
3. If you accept: triple-tap (or tap **On order** in DashLens). Offers you don't mark accepted within 5 minutes are recorded as *passed*. You can fix any row in the **Offers** tab.
4. When the order is done: tap **Online** in DashLens (or run the **Order Done** shortcut).
5. **Stop shift** when you go offline.

---

## Your data

- Stored in a private database inside the app. Deleting the app deletes it.
- **Reports > Save** writes CSVs and a text summary to **Files > On My iPhone > DashLens**. Opening the app also saves any finished week automatically. Copy these off the phone now and then, especially before reinstalling.
- Receipt photos are saved in **Files > On My iPhone > DashLens > Receipts**.

---

## Honest limits

- The card depends on text recognition reading Dasher's offer screen correctly. It is tuned to the layout the Android parser was tuned on (pay, "Guaranteed (incl. tips)", miles, "Deliver by", "Pickup" + merchant, Accept / Decline). If Dasher changes its layout, or OCR misreads a number, the card can be wrong or say it found no offer. Always sanity-check the numbers against the offer.
- Screenshots add 2 to 4 seconds. Dasher offers have a short countdown.
- Mileage uses the phone's GPS. If iOS force-quits the app mid-shift, it is relaunched by significant-location changes and resumes, but you can lose a few minutes. Keep the app out of Low Power Mode during shifts.
- Tax figures are estimates, not tax advice.
- DashLens is independent and not affiliated with DoorDash. Check Dasher's terms before relying on any tool that reads their screens, including screenshots.

---

## What's in this folder

| Path | Purpose |
|---|---|
| `project.yml` | XcodeGen description of the Xcode project (permissions, background location, Files-app sharing) |
| `.github/workflows/build-ios.yml` | Builds the unsigned .ipa on a GitHub macOS runner |
| `DashLens/Core` | Ported logic: parser, analyzer, finance/tax, reports, insights, SQLite database, GPS tracker, OCR engine |
| `DashLens/Intents` | The Shortcuts actions (Analyze Dasher Offer, Start/Stop Shift, I Accepted, Order Done, ...) |
| `DashLens/UI` | SwiftUI screens (Home, Offers, Money, Insights, Reports, Settings, Welcome) |
