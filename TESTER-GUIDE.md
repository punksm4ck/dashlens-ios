# DashLens for iPhone: tester install guide

Thanks for testing. This is an early test build, so please report anything odd. It installs without a jailbreak, using your own free Apple ID.

**Download:** scan the QR code, or open
https://github.com/punksm4ck/dashlens-ios/releases/latest
and download **DashLens-4.1-unsigned.ipa** (under "Assets").

**What you need**
- An iPhone on iOS 17 or newer (iPhone 12 and newer; built for the iPhone 15 to 18 families)
- A Mac or a Windows PC, and the cable that charges your iPhone
- A free Apple ID (a spare one is fine; it is only used to sign the app)
- About 10 minutes

---

## Part 1. Install

### Step 1: Install Sideloadly on your computer
1. Go to **sideloadly.io** and download Sideloadly for your Mac or Windows PC.
2. **Windows only:** also install **iTunes** from apple.com (the downloadable version, *not* the Microsoft Store one). Sideloadly's download page lists current requirements; follow it if it says anything different.

### Step 2: Sign and install the app
1. Plug your iPhone into the computer. On the phone, tap **Trust This Computer** and enter your passcode.
2. Open Sideloadly. Your iPhone should appear at the top.
3. Drag **DashLens-4.1-unsigned.ipa** into Sideloadly.
4. Type your Apple ID email, then click **Start**. Enter your password and the 6-digit 2-factor code when asked.
5. Wait for "Done". The DashLens icon (a white ring with a green dot) is now on your home screen.

### Step 3: Trust the app and turn on Developer Mode
1. On the iPhone: **Settings > General > VPN & Device Management**. Tap your Apple ID under *Developer App*, then **Trust**.
2. **Settings > Privacy & Security**, scroll to the bottom, tap **Developer Mode**, switch it **on**, then tap **Restart**. After the restart, tap **Turn On** and enter your passcode.
   - If you don't see Developer Mode, it appears only after an app has been sideloaded. Do Step 2 first, then look again.
3. Open DashLens.

### Things to know
- **It expires after 7 days.** Free Apple IDs only sign apps for a week. When DashLens stops opening, repeat Part 1 Step 2 with the same file. **Do not delete the app first**, because deleting it erases your data.
- A free Apple ID allows 3 sideloaded apps at a time.
- If Sideloadly shows a sign-in error, update Sideloadly and try again. After a new iPhone software update, these tools can lag by a few days.

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
