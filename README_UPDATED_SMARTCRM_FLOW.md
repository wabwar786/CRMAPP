# SmartCRM Mobile Update

This ZIP includes the previous CRM call-flow patch plus the new CRM UI redesign.

## Included call-flow changes
- Outgoing call logging remains intact.
- Incoming calls are matched against loaded CRM lead/customer numbers.
- Unknown/personal incoming calls are ignored and are not saved.
- Missed CRM customer calls are logged.
- Call-end remarks/follow-up dialog added.
- Pending call remarks are saved locally and shown when the app opens.
- Today follow-up popup is shown after leads load.
- Recording upload service no longer starts a second recording; it uploads the existing recording file only.
- Android call receiver is manifest-based to avoid duplicate events.

## Included UI redesign changes
- Material 3 theme in `lib/main.dart`.
- New bottom navigation in Dashboard: Home, Leads, Follow-up, Remarks, Portal.
- New Sales CRM Overview home tab.
- New dashboard metric cards: Today Follow-ups, Overdue, New Leads, Pending Remarks, Ready Sale, Tasks.
- New priority work section.
- New CRM shortcuts.
- New Follow-up Center tab.
- New Pending Remarks tab.
- New customer timeline bottom sheet from priority lead cards.
- Existing WebView and login flow are preserved.

## Important
Build testing was not completed inside this environment because Gradle/Flutter CLI is not available here. Please run:

```bash
flutter clean
flutter pub get
flutter build apk --release
```

If any build error appears, share the exact error and I will patch it directly.
