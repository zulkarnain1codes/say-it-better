# Say it better (iPhone app)

Listens while you talk (even with the phone locked), writes down your words, and later marks grammar and word-choice mistakes. Speech-to-text and grammar checking both run on your iPhone, so nothing you say leaves the phone.

## What you need

- Windows PC
- iPhone 15 Pro or newer with iOS 26 or later
- Apple Intelligence turned on (Settings → Apple Intelligence & Siri)
- A free GitHub account (it builds the app for you, because iPhone apps can only be built on a Mac)
- Your Apple ID, and a USB cable for the first setup

## Part 1: Build the app (free, in the cloud)

1. Make a free account at github.com.
2. Click **+** (top right) → **New repository**. Name it `say-it-better`, choose **Public**, then click **Create repository**. (Public projects build for free. Only this code goes there, never your recordings.)
3. On the new page, click **uploading an existing file**. Unzip `say-it-better-app.zip` on your PC, open the `SayItBetter` folder, select everything inside it (including the `.github` folder) and drag it onto the page. Click **Commit changes**.
4. Click the **Actions** tab. "Build app" starts by itself and takes about 5–10 minutes.
   - Green tick: done, go to step 5.
   - Red cross: open the run, click **Show build errors**, copy those lines and send them to Claude.
   - Nothing there? The `.github` folder didn't upload. Click **Add file → Create new file**, type `.github/workflows/build.yml` as the name, paste in the contents of that file from the zip, and click **Commit changes**.
5. Your app file is always at this link (put in your GitHub name):
   `https://github.com/YOUR-NAME/say-it-better/releases/latest/download/SayItBetter.ipa`

## Part 2: Set up AltStore (one time)

1. Install **iTunes** and **iCloud** from Apple's website, not the Microsoft Store. If you already have the Microsoft Store versions, uninstall them first.
   - iTunes: https://www.apple.com/itunes/download/win64
   - iCloud: see https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
2. Download **AltServer for Windows** from https://altstore.io, unzip it and run the installer.
3. Plug your iPhone into the PC and tap **Trust** on the iPhone.
4. Open iTunes, click the little phone icon, tick **Sync with this iPhone over Wi-Fi**, click **Apply**.
5. Search Windows for **AltServer**, right-click it → **Run as administrator**. Allow private networks if Windows asks.
6. Click the AltServer icon near the clock (it may be hidden under **^**) → **Install AltStore** → your iPhone. Enter your Apple ID and password.
7. On the iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
8. On the iPhone: **Settings → Privacy & Security → Developer Mode** → turn it on and restart the phone.

## Part 3: Install Say it better

1. On the iPhone, open the link from Part 1 step 5 in Safari and tap **Download**.
2. Open **AltStore → My Apps → +** (top left) and pick `SayItBetter.ipa` from Downloads. Keep the PC on with AltServer running, on the same Wi-Fi.
3. Open Say it better and tap **Start listening**. Allow the microphone, speech recognition and notifications. The first time, it downloads Apple's speech model, so you need internet once.

## Keeping it working every week

Apps installed with a free Apple ID stop working after 7 days unless they're refreshed. AltStore refreshes them by itself when your iPhone and PC are on the same Wi-Fi and AltServer is running, so leave AltServer running on the PC at home. If the app ever stops opening, go home, open **AltStore → My Apps → Refresh All**. Your saved sessions stay when the app refreshes.

## Getting an updated version

Upload the changed files to the same GitHub project, wait for the new green tick, download the `.ipa` again and install it through AltStore. Your sessions are kept.

## Using it

- Tap **Start listening** at the start of a shift and lock the phone. The orange dot at the top of the screen means the mic is on.
- It pauses during phone calls and starts again after. If it can't, it sends you a notification.
- Listening all shift uses a lot of battery, so keep the phone charging in the car.
- Go to **Review**, open a session and tap **Check grammar**. Keep the app open while it checks; a whole shift can take several minutes.
- Red dotted underline = grammar. Yellow highlight = better word choice. Tap **X** on a correction if it's wrong.
- **Find my patterns** gives you three things to work on.
- It hears everyone nearby, not just you, so be careful about recording other people.
- AltServer sends your Apple ID only to Apple. Some people use a second Apple ID for this anyway.
