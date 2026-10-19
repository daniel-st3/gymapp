# Run Little Lift on your Mac

**Latest local update: Build 17.** Open **Today → My gym chat → Copy updated message** to prepare the message for your existing gym conversation. Bring its reply back with Paste, review/edit and accept. Copying does not send anything automatically. Add routine now preserves Today; import errors and retries give visible feedback. Both real apps received the free-signed update with original data preserved. [Chat guide](docs/gym-chat.md), [Build 17 checklist](docs/upgrade-17-checklist.md), [27-point matrix](docs/feedback-27.md).

Your completed workout review appears automatically after the phone saves it. Open **Today → Your latest workout review**, or **History → a workout → Automatic review**. No account or model setup is required. ChatGPT remains a separate optional route. Original data, free signing and icon are preserved; **do not uninstall**.

For a nontechnical walkthrough, use **Settings → Start here** inside the phone app, or open the [local Spanish guide](docs/onboarding/index.html). The existing explicit-chat workflow and optional independent Shortcut remain separate. The historical Build 4 notes below are not new verification.

## Easiest way to run it

1. Finish any current Xcode debug run. Xcode may stay open.
2. Double-click **Run Little Lift.command** in this folder.
3. Let its Terminal window build and launch both apps. Keep that window open until it finishes.

Use the launcher inside **this current local folder**, so both devices receive the monochrome build rather than an older open Xcode project.

The launcher selects an existing iPhone/Watch pair, builds and installs both apps, then starts both independently of Xcode's debugger. It keeps their existing data. If the selected iPhone has no plan, the explicit demo launch loads the generic example. The watch requests the workout automatically. The launcher then checks that the watch saved the same plan with a fresh sync timestamp before printing **Confirmed**. A stale saved plan does not count. No signing account or paid developer membership is needed for these simulator runs.

If a build fails, the Terminal window prints the last compiler messages and saves the full logs in BuildLogs. If delivery is not confirmed within about 20 seconds, it reports that separately and keeps both apps open. It does not erase simulator data. The launcher has automated tests for pair selection, command order, and delivery checks; actual Apple-tool execution still requires your Mac.

## Open in Xcode manually

The shared workout engine is compiled directly into both app targets, with no package-resolution step.

1. Unzip this folder and open **LittleLift.xcodeproj** in Xcode.
2. Choose the **LittleLift** scheme in the top bar, choose an **iPhone simulator**, and press **▶ Run**. This first run does not require signing or a paid developer account.
3. The existing device installation uses the free Personal Team. The private **Refresh My Devices.command** refreshes signing and updates both apps while keeping workout data. Personal signing profiles expire after about seven days; the refresh script checks the current installation. No paid enrollment or publishing is needed.

For an actual compile check of both apps and the engine tests, run this in Terminal from this folder:

```sh
bash scripts/verify-mac.sh
```

Build 4 was built and exercised on this Mac with Xcode 27, the existing iPhone 18 Pro Max, and its paired 46 mm Apple Watch Series 12 simulators. Both Apple SDK builds, 25 engine tests, 10 launcher tests, and project/icon checks passed. Actual UI logging, rest extension/skip/expiry, undo, early and full completion, History delivery, duplicate replay, relaunch recovery, long names, large text, and system Reduce Motion were exercised. Original workout data and simulator pairing were preserved. See `docs/verification.md` for observed results and hardware limitations.

In the iPhone app, **Use example workout** is a quick way to populate the logger. For your actual training, use **Import workout** and the coaching prompt for your existing ChatGPT chat. Optional analysis setup is available under **Settings → Coach connection → Set up review Shortcut**.

The project has no server, OpenAI API keys, advertising, or runtime package downloads. Your personal workout data is not included in this source bundle.
