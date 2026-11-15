// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageName => 'English';

  @override
  String get loading => 'Loading…';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginSubtitlePhone =>
      'Use the mobile number your manager registered.';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get phoneHelper => 'We will send a 6-digit code by SMS';

  @override
  String get sendCode => 'Send code';

  @override
  String get language => 'Language';

  @override
  String get otpTitle => 'Enter the code';

  @override
  String otpSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get otpLabel => '6-digit code';

  @override
  String get verify => 'Verify';

  @override
  String resendIn(int seconds) {
    return 'Resend in $seconds s';
  }

  @override
  String get resendCode => 'Resend code';

  @override
  String get codeResent => 'A new code is on its way';

  @override
  String get changeNumber => 'Change number';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get orDivider => 'or';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get usePhoneInstead => 'Use phone OTP instead';

  @override
  String get useEmailInstead => 'Use email instead';

  @override
  String get resetSent =>
      'If this email has an account, a reset link is on its way.';

  @override
  String get verifyEmailTitle => 'Check your inbox';

  @override
  String verifyEmailBody(String email) {
    return 'We sent a confirmation link to $email. Open it, then sign in again.';
  }

  @override
  String get resendEmail => 'Resend email';

  @override
  String get emailResent => 'Email sent again';

  @override
  String get backToLogin => 'Back to sign in';

  @override
  String get errorRequired => 'Required';

  @override
  String get errorPhone => 'Enter a 10-digit mobile number';

  @override
  String get errorOtp => 'Enter the 6-digit code';

  @override
  String get errorEmail => 'Enter a valid email address';

  @override
  String errorPasswordShort(int min) {
    return 'At least $min characters';
  }

  @override
  String get errorNotANumber => 'Enter a number';

  @override
  String errorBelowMin(String min) {
    return 'Must be at least $min';
  }

  @override
  String errorAboveMax(String max) {
    return 'Must be at most $max';
  }

  @override
  String get authInvalidCredentials => 'Wrong email or password.';

  @override
  String get authEmailNotConfirmed =>
      'Confirm your email first. Check your inbox.';

  @override
  String get authOtpInvalid =>
      'That code is not right. Check the SMS and try again.';

  @override
  String get authOtpExpired => 'The code has expired. Ask for a new one.';

  @override
  String get authRateLimited =>
      'Too many attempts. Wait a few minutes and try again.';

  @override
  String get authNotRegistered =>
      'This number or email is not registered. Ask your manager.';

  @override
  String get authNetwork => 'No connection. Check the internet and try again.';

  @override
  String get authNotConfigured => 'Sign-in is not set up in this build.';

  @override
  String get authCancelled => 'Sign-in was cancelled.';

  @override
  String get authUnknown => 'Sign-in failed. Try again.';

  @override
  String get reasonWrongApp =>
      'Your account cannot use this app. Please use the app for your role.';

  @override
  String get reasonNotRegistered =>
      'Your account is not active. Contact your manager.';

  @override
  String get reasonOtherDevice =>
      'You logged in on another phone, so this phone was signed out.';

  @override
  String get reasonUnauthorized =>
      'Your session has ended. Please sign in again.';

  @override
  String reasonGeneric(String code) {
    return 'Could not sign in ($code). Try again.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeSystem => 'Same as phone';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsSync => 'Sync';

  @override
  String syncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting to sync',
      one: '1 change waiting to sync',
      zero: 'Everything is synced',
    );
    return '$_temp0';
  }

  @override
  String get openSyncQueue => 'Open sync queue';

  @override
  String get settingsAbout => 'About';

  @override
  String aboutVersion(String version, String code) {
    return 'Version $version (build $code)';
  }

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirm => 'Sign out of this phone?';

  @override
  String signOutPendingWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes have not synced yet. They stay on this phone and sync after you sign in again.',
      one:
          '1 change has not synced yet. It stays on this phone and syncs after you sign in again.',
    );
    return '$_temp0';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get syncQueueTitle => 'Sync queue';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncNeedsAttention => 'Needs attention';

  @override
  String get syncWaiting => 'Waiting to sync';

  @override
  String syncNextTry(String time) {
    return 'Next try at $time';
  }

  @override
  String get syncFiles => 'Files to upload';

  @override
  String get syncEmpty =>
      'Nothing is waiting. All your changes are on the server.';

  @override
  String get retry => 'Retry';

  @override
  String get discard => 'Discard';

  @override
  String get discardConfirm =>
      'Discard this change? The server refused it and it will be lost.';

  @override
  String get offlineBanner => 'Offline. Your changes are saved and will sync.';

  @override
  String get updatedJustNow => 'Updated just now';

  @override
  String updatedAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Updated $minutes min ago',
      one: 'Updated 1 min ago',
    );
    return '$_temp0';
  }

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get emptyTitle => 'Nothing here yet';

  @override
  String homeWelcome(String name) {
    return 'Hello, $name';
  }

  @override
  String get homeComingSoon =>
      'The screens of this app arrive in the next release.';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredBody =>
      'This version is no longer supported. Install the latest version to continue.';

  @override
  String get statusSafe => 'Safe';

  @override
  String get statusWatch => 'Watch';

  @override
  String get statusCritical => 'Critical';

  @override
  String get statusInfo => 'Info';

  @override
  String get voiceInput => 'Speak the value';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Close';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get send => 'Send';

  @override
  String get saved => 'Saved';

  @override
  String todayAtSite(String site) {
    return 'Today at $site';
  }

  @override
  String get countRegistered => 'Registered';

  @override
  String get countGraded => 'Graded';

  @override
  String get countStored => 'In storage';

  @override
  String get countDispatched => 'Dispatched';

  @override
  String get newFishBatch => 'New fish batch';

  @override
  String get newProduceBatch => 'New produce batch';

  @override
  String get receive => 'Receive';

  @override
  String get loadTruck => 'Load truck';

  @override
  String get batches => 'Batches';

  @override
  String get printer => 'Printer';

  @override
  String get resumeDraft => 'Continue the batch you started';

  @override
  String get discardDraft => 'Discard';

  @override
  String get stepForm => 'Details';

  @override
  String get stepTag => 'Tag';

  @override
  String get stepPhotos => 'Photos';

  @override
  String get stepGrade => 'Grade';

  @override
  String get stepStorage => 'Storage';

  @override
  String get stepLabel => 'Label';

  @override
  String get stepDone => 'Done';

  @override
  String stepOf(int n, int total) {
    return 'Step $n of $total';
  }

  @override
  String get product => 'Product';

  @override
  String get catchTime => 'Catch time';

  @override
  String get harvestTime => 'Harvest time';

  @override
  String get weight => 'Weight';

  @override
  String get vesselId => 'Vessel ID';

  @override
  String get farmRef => 'Farm ID';

  @override
  String get iceRatio => 'Ice-to-fish ratio';

  @override
  String get coreTemp => 'Core temperature';

  @override
  String get maturity => 'Maturity index';

  @override
  String get brix => 'Brix';

  @override
  String get fieldTemp => 'Field temperature';

  @override
  String get fieldHumidity => 'Field humidity';

  @override
  String get listening => 'Listening… say the number';

  @override
  String get voiceNotHeard => 'Didn\'t catch a number. Try again or type it.';

  @override
  String get mastersMissing =>
      'Master lists are not downloaded yet. Connect once to download them.';

  @override
  String get tagChoose => 'Tag the crate';

  @override
  String get tagNfc => 'Tap NFC tag';

  @override
  String get tagQr => 'Scan QR';

  @override
  String get tagWedge => 'RFID reader';

  @override
  String tagRead(String uid) {
    return 'Tag $uid';
  }

  @override
  String get tagInvalid => 'This is not a valid tag';

  @override
  String get tagWedgeTitle => 'Scan with the RFID reader';

  @override
  String get tagWedgeHelp =>
      'Pull the reader trigger, or type the tag number and press Enter.';

  @override
  String get nfcHold => 'Hold the tag to the back of the phone';

  @override
  String get nfcUnavailable =>
      'NFC is off or not available. Use QR or the RFID reader.';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get scanQrHelp => 'Point the camera at the QR code';

  @override
  String get photoTop => 'Top';

  @override
  String get photoSide => 'Side';

  @override
  String get photoCloseup => 'Close-up';

  @override
  String get photoHelpTop => 'From above: the whole crate inside the frame';

  @override
  String get photoHelpSide => 'From the side: show the depth of the crate';

  @override
  String get photoHelpCloseup => 'Close-up: one fish or fruit fills the frame';

  @override
  String get retake => 'Retake';

  @override
  String get photosNeeded => 'Take all three photos';

  @override
  String get cameraUnavailable => 'The camera is not available';

  @override
  String get gradeWaiting => 'Grading…';

  @override
  String get gradeQueued =>
      'Grading queued. The grade arrives when the phone is online.';

  @override
  String get gradeUnavailable =>
      'Grading is not available right now. It is queued and runs later.';

  @override
  String gradeResult(String grade) {
    return 'Grade $grade';
  }

  @override
  String confidence(int pct) {
    return 'Confidence $pct%';
  }

  @override
  String get defects => 'Defects';

  @override
  String get noDefects => 'No defects found';

  @override
  String get dispute => 'Dispute';

  @override
  String get disputeReason => 'Why is the grade wrong?';

  @override
  String get disputeSent => 'Dispute sent to the manager';

  @override
  String get pathBlastChiller => 'Blast chiller';

  @override
  String get pathRipening => 'Ripening chamber';

  @override
  String get pathColdRoom => 'Cold room';

  @override
  String get sellFirst => 'Sell first';

  @override
  String recommendedUnit(String unit, String free) {
    return 'Recommended: $unit ($free kg free)';
  }

  @override
  String get noUnit => 'No suitable unit is free at this site';

  @override
  String get assign => 'Assign';

  @override
  String assigned(String unit) {
    return 'Stored in $unit';
  }

  @override
  String get storageOffline =>
      'Shown from this phone\'s lists. Assign it when you are online.';

  @override
  String get print => 'Print';

  @override
  String get shareImage => 'Share image';

  @override
  String get labelOffline => 'The label is ready once the batch has synced.';

  @override
  String get noPrinter => 'No printer set up';

  @override
  String get printed => 'Label sent to the printer';

  @override
  String get printFailed =>
      'Printing failed. Share the label as an image instead.';

  @override
  String get doneTitle => 'Batch registered';

  @override
  String doneTime(int seconds) {
    return 'Done in $seconds s';
  }

  @override
  String get newBatch => 'New batch';

  @override
  String get goHome => 'Home';

  @override
  String get pendingSync => 'Not synced yet';

  @override
  String get searchBatches => 'Search code or tag';

  @override
  String get all => 'All';

  @override
  String get stRegistered => 'Registered';

  @override
  String get stGraded => 'Graded';

  @override
  String get stStored => 'Stored';

  @override
  String get stAllocated => 'Allocated';

  @override
  String get stLoaded => 'Loaded';

  @override
  String get stInTransit => 'In transit';

  @override
  String get stDiverted => 'Diverted';

  @override
  String get stDelivered => 'Delivered';

  @override
  String get stPartial => 'Partly delivered';

  @override
  String get stRejected => 'Rejected';

  @override
  String get stSpoiled => 'Spoiled';

  @override
  String shelfLifeHours(String hours) {
    return 'Shelf life $hours h';
  }

  @override
  String get history => 'History';

  @override
  String get chainVerified => 'Record chain verified';

  @override
  String get chainBroken => 'Record chain NOT verified';

  @override
  String get edit => 'Edit';

  @override
  String get requestEdit => 'Request edit';

  @override
  String editMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min left to edit',
      one: '1 min left to edit',
    );
    return '$_temp0';
  }

  @override
  String get editClosed =>
      'The 30-minute edit window has closed. Ask the manager.';

  @override
  String get reason => 'Reason';

  @override
  String get requestSent => 'Request sent to the manager';

  @override
  String get printLabel => 'Print label';

  @override
  String get tags => 'Tags';

  @override
  String get onlineOnly => 'This needs an internet connection.';

  @override
  String get scanBatch => 'Scan the batch';

  @override
  String notFound(String value) {
    return 'No batch found for $value';
  }

  @override
  String get condition => 'Condition';

  @override
  String get condGood => 'Good';

  @override
  String get condFair => 'Fair';

  @override
  String get condPoor => 'Poor';

  @override
  String get damagePhotos => 'Damage photos';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get outcome => 'Outcome';

  @override
  String get accept => 'Accept';

  @override
  String get partial => 'Partial';

  @override
  String get reject => 'Reject';

  @override
  String get acceptedWeight => 'Accepted weight';

  @override
  String get submit => 'Submit';

  @override
  String get receiveSaved =>
      'Receiving saved. It syncs when the phone is online.';

  @override
  String get noTrips => 'No trips to load today';

  @override
  String loadedCount(int n, int total) {
    return '$n of $total loaded';
  }

  @override
  String wrongBatch(String code) {
    return 'Not for this trip: $code';
  }

  @override
  String get alreadyScanned => 'Already scanned';

  @override
  String get confirmLoad => 'Confirm loading';

  @override
  String get loadSaved => 'Loading saved. It syncs when the phone is online.';

  @override
  String get scanNext => 'Scan next crate';

  @override
  String get pairedPrinters => 'Paired printers';

  @override
  String get noPairedPrinters =>
      'No paired printer. Pair the printer in the phone’s Bluetooth settings first.';

  @override
  String get testPrint => 'Test print';

  @override
  String get selectedPrinter => 'Selected';

  @override
  String get bluetoothOff => 'Bluetooth is off. Turn it on to print.';
}
