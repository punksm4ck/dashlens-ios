# DashLens for iPhone: tester install guide

Thanks for testing. This is an early test build, so please report anything odd. It installs without a jailbreak, using your own free Apple ID.

**Download:** scan the QR code, or open
https://github.com/punksm4ck/dashlens-ios/releases/latest
and download **DashLens-unsigned.ipa** (under "Assets").

**DashLens itself has no login and no sign-up.** There is no account to create. The only place you type an Apple ID and password is **Sideloadly** (the free tool on your computer that signs the app so your iPhone will run it). If something is asking you to "log in or sign up" and you are not inside Sideloadly, stop and send me a screenshot.

**What you need**
- An iPhone on iOS 17 or newer (iPhone 12 and newer; built for the iPhone 15 to 18 families)
- A Mac or a Windows PC, and the cable that charges your iPhone
- An Apple ID that you have already used to sign in on an iPhone or iPad (a spare one is fine; it is only used to sign the app). A brand-new Apple ID that has never been used on a device may be refused.
- About 15 minutes

**How it works, in one line:** an iPhone cannot install a downloaded app file by itself. You download the `.ipa` on your computer, and Sideloadly signs it with your Apple ID and pushes it to the phone over the cable.

---

## Part 1. Install

### Step 1: Get the app file on your computer
Open https://github.com/punksm4ck/dashlens-ios/releases/latest on the **computer**, scroll to **Assets**, and click **DashLens-unsigned.ipa**. No GitHub account is needed. If your browser saves it with an extra `.zip` on the end, rename it so it ends in `.ipa`.

### Step 2: Install the tools
**Windows PC**
1. Install **iTunes** and **iCloud** from **apple.com** (search "download iTunes for Windows"). Use Apple's own website installers, **not** the Microsoft Store versions: Sideloadly cannot talk to the phone through the Store versions.
2. Install **Sideloadly** from **sideloadly.io**.
3. Restart the PC if the installers ask you to.

**Mac**
1. Install **Sideloadly** from **sideloadly.io** (no iTunes needed).

### Step 3: Connect the phone
1. Plug the iPhone into the computer with the cable.
2. On the phone, tap **Trust This Computer** and enter your passcode.
3. On Windows, if iTunes opens, let it see the phone once, then close it.

### Step 4: Sign and install
1. Open **Sideloadly**. Your iPhone should appear in the device box at the top. If it does not, see "If it will not work" below.
2. Drag **DashLens-unsigned.ipa** onto the Sideloadly window.
3. Type your **Apple ID email** and click **Start**.
4. Enter your Apple ID **password** when Sideloadly asks. Then a **6-digit code** appears on your iPhone (or another Apple device signed in to that Apple ID): type it in quickly.
5. Wait for "Done". The DashLens icon (a white ring with a green dot) is now on your home screen.

### Step 5: Trust the app and turn on Developer Mode
1. On the iPhone: **Settings > General > VPN & Device Management**. Tap your Apple ID under *Developer App*, then **Trust**.
2. **Settings > Privacy & Security**, scroll to the bottom, tap **Developer Mode**, switch it **on**, then tap **Restart**. After the restart, tap **Turn On** and enter your passcode.
   - If you don't see Developer Mode, it appears only after an app has been sideloaded. Do Step 4 first, then look again.
3. Open DashLens.

### If it will not work
Send me a **screenshot of the whole Sideloadly window** (including the log at the bottom) and tell me which step you were on. Common causes:

| What you see | What to try |
|---|---|
| iPhone does not appear in Sideloadly | Try another cable or USB port. Tap Trust on the phone. On Windows, check iTunes and iCloud are the **apple.com** versions, not the Microsoft Store ones. |
| Apple ID or password rejected | Re-type it, and check you can sign in to your Apple account page in a browser (account.apple.com). If you have an app-specific password, do not use it here. |
| Asks for the 6-digit code twice, or "unknown error" on the code | Wait for a fresh code on the phone and enter it right away. Make sure the phone shows the code prompt and is not locked. |
| "Maximum App ID limit reached" | A free Apple ID can only create a few new app IDs per week. Wait about a week, or use a different Apple ID. |
| Apple ID refused for development, or a brand-new Apple ID | Use an Apple ID that has been signed in on an iPhone for a while. |
| "Guru Meditation" and a long code | Update Sideloadly, pause your antivirus for a minute, re-plug the phone, try again. If it repeats, send me the code. |
| The app icon appears but will not open | Do Step 5 (Trust, then Developer Mode). |

### Things to know
- **It expires after 7 days.** Free Apple IDs only sign apps for a week. When DashLens stops opening, repeat Step 4 with the same file. **Do not delete the app first**, because deleting it erases your data.
- A free Apple ID allows 3 sideloaded apps at a time.
- After a new iPhone software update, these tools can lag by a few days.

---

## Part 2. First run

1. Read the welcome screen and tap **Allow location and notifications**.
2. For location, choose **Allow While Using**. When iOS asks again, choose **Change to Always Allow**. (This lets mileage keep logging while Dasher is open and the phone is locked. You'll see the blue location indicator during a shift.)
3. In **Settings** inside DashLens, pick a profile (Strict / Balanced / Easygoing) and enter your vehicle cost per mile.

### Set up the offer card (Back Tap)
iPhone can't draw over the Dasher app. Instead, a shortcut takes a screenshot and DashLens reads it on your phone.
1. Open the **Shortcuts** app and tap **+** (new shortcut).
2. Add the action **Take Screenshot**.
3. Add the action **Analyze Dasher Offer** (search "DashLens") and put the screenshot result into its *Screenshot* field.
4. Name it **Dash Check**.
5. **Settings > Accessibility > Touch > Back Tap > Double Tap**, and choose **Dash Check**.
6. Optional: make a second shortcut with the DashLens action **I Accepted the Offer** and set it as **Triple Tap**.

---

## Part 3. What to test (please reply with results)

**1. Install.** Did it install and open? Note any step that was confusing or failed, and exactly what the error said.

**2. Screenshot test (most important).**
- Take a normal screenshot of a real Dasher offer (the one with the pay, miles and Accept / Decline).
- In DashLens, on Home, tap **Test with a saved Dasher screenshot** and pick it.
- Send back: a screenshot of the card DashLens shows, **and** the text under "Text DashLens read from the screenshot" (tap **Copy text** and paste it in your message).
- Is the pay, miles and restaurant name right?

**3. Back Tap.** With a real offer on screen, double-tap the back of the phone. Does the verdict card appear over Dasher? About how many seconds does it take?

**4. Mileage.** Tap **Start shift**, lock the phone, walk or drive about half a mile, then stop the shift. Open Home > **Mileage reports**. Does the mileage look about right? Did it keep logging while the phone was locked?

**5. Anything else.** Crashes, screens that look wrong, or things that confused you.

Everything stays on your phone. DashLens has no account and uploads nothing. The money and tax numbers are estimates, not tax advice.

## New in 4.2.0: what to test
1. Run an offer through the shortcut and check the card shows the gas, wear, net pay, time and miles lines. Do the numbers match what you would work out by hand?
2. If you see a shop & deliver offer ("4 items"), check the item count is read and the time line shows shopping and checkout.
3. If you see pay with a "+", check it is marked and the card says it was graded at that minimum.
4. In Offers, tap **SHARE** on a row and check the picture card looks right in the share sheet.
5. In Settings, try **Load typical Dasher assumptions**, then change a value and check the next offer uses it.

Your old history and settings should still be there after updating. If anything is missing, tell us what the app showed before and after.

---

## Testing Live detection (beta builds only)

Live detection shows the TAKE / MAYBE / DECLINE verdict as a banner on top of Dasher with no taps. It is new, so please
test it in this order and send me the report. It takes about 3 minutes and does not need a real offer for steps 1 to 3.

1. **Banner test.** Open DashLens > Home > **Live detection** > **Live status and tests** > **Banner in 5 s**. Switch to
   any other app. A DashLens banner should appear at the top within 5 seconds. (If not: Settings > Notifications > DashLens
   must be on, and a Focus such as Driving or Do Not Disturb must allow DashLens.)
2. **Self-test.** In the same place tap **Self-test**. A banner for "Self-test Deli" should appear.
3. **Start it.** Tap **Start shift + live detection**, pick **DashLens Live** in the list, tap **Start Broadcast**, wait for the
   3-2-1, then go to the Dasher app. A red recording indicator shows while it runs. That is normal.
4. **Wait for a real offer** (or ask a friend to show you a Dasher offer screen). The banner should appear within about
   a second of the offer showing.
5. **Send the report, whatever happened.** Back in DashLens open **Live status and tests** and tap **Copy live report**.
   Paste it into your message to me, and tell me what you saw (banner yes or no, how fast, anything odd in Dasher).

Stop the broadcast afterwards: tap the red recording indicator, then Stop Broadcast.
