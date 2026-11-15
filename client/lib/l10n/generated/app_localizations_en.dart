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

  @override
  String get acceptReroute => 'Accept new route';

  @override
  String get declineReroute => 'Keep current route';

  @override
  String get acknowledge => 'Acknowledge';

  @override
  String get alertTemp => 'Temperature out of range';

  @override
  String get alertTempDo =>
      'Check the reefer is running and the setpoint is right. Keep the doors closed.';

  @override
  String get alertDriverFix => 'Temperature drifting';

  @override
  String get alertDriverFixDo =>
      'Check the door seals, the reefer setpoint and that the airflow is not blocked. Re-checked in 15 minutes.';

  @override
  String get alertSpoilage => 'Cargo at risk of spoiling';

  @override
  String get alertSpoilageDo =>
      'Wait for the new route from the control tower and accept it.';

  @override
  String get alertHumidity => 'Humidity out of range';

  @override
  String get alertHumidityDo => 'Check the doors and the reefer.';

  @override
  String get alertEthylene => 'Ethylene high';

  @override
  String get alertEthyleneDo => 'Ventilate if safe and tell the control tower.';

  @override
  String get alertShock => 'Hard shock detected';

  @override
  String get alertShockDo => 'Stop when safe and check the cargo.';

  @override
  String get alertDevice => 'Sensor offline';

  @override
  String get alertDeviceDo => 'Check the sensor pod power and cable.';

  @override
  String get alertGeneric => 'Cargo alert';

  @override
  String get alertGenericDo => 'Read the message and follow the control tower.';

  @override
  String get allStopsDone => 'All stops done. Drive back to the depot.';

  @override
  String get allUploaded => 'Everything is uploaded';

  @override
  String pendingUploads(int count) {
    return '$count items waiting to upload';
  }

  @override
  String get arrived => 'I have arrived';

  @override
  String get deliverHere => 'Deliver here';

  @override
  String get cargoStatus => 'Cargo';

  @override
  String get cargoTemp => 'Temperature';

  @override
  String get cargoHumidity => 'Humidity';

  @override
  String cargoLowestShelfLife(String value) {
    return 'Lowest shelf life: $value';
  }

  @override
  String cargoAsOf(String time) {
    return 'Last update $time (offline)';
  }

  @override
  String get cargoEmpty => 'No cargo on board';

  @override
  String cargoSafeRange(String min, String max) {
    return 'Safe $min to $max °C';
  }

  @override
  String get clear => 'Clear';

  @override
  String get gpsOff => 'Location is off. Turn it on to start the trip.';

  @override
  String get gpsDenied => 'Location permission is needed to track the trip.';

  @override
  String get gpsDeniedForever =>
      'Location permission is blocked. Allow it in settings.';

  @override
  String get gpsFailed => 'Trip tracking could not start. Try again.';

  @override
  String get notificationsDenied =>
      'Allow notifications so you can see that the trip is tracked.';

  @override
  String get openSettings => 'Open settings';

  @override
  String historyPods(int count) {
    return 'Deliveries recorded: $count';
  }

  @override
  String get noHistory => 'No trips yet';

  @override
  String get tripHistory => 'Trip history';

  @override
  String get incDelay => 'Delay';

  @override
  String get incBreakdown => 'Breakdown';

  @override
  String get incAccident => 'Accident';

  @override
  String get incRoadblock => 'Road block';

  @override
  String get incReeferFault => 'Reefer fault';

  @override
  String get incPhoto => 'Add photo';

  @override
  String get incPhotoDone => 'Photo added';

  @override
  String get incPhotoHint => 'Show the problem';

  @override
  String get incVoice => 'Voice note';

  @override
  String incVoiceDone(int seconds) {
    return 'Voice note $seconds s';
  }

  @override
  String incVoiceStop(int seconds) {
    return 'Stop ($seconds s left)';
  }

  @override
  String get incSend => 'Send report';

  @override
  String get incSent => 'Report saved. It is sent as soon as there is network.';

  @override
  String get incQueuedHint => 'Works without network: it is sent later.';

  @override
  String get reportIncident => 'Report incident';

  @override
  String get micDenied => 'Microphone permission is needed for a voice note.';

  @override
  String get navigate => 'Navigate';

  @override
  String get nextStop => 'Next stop';

  @override
  String get noTripToday => 'No trip today';

  @override
  String get noTripTodayHint => 'Pull down to check again.';

  @override
  String openAlerts(int count) {
    return '$count open alerts: tap to see';
  }

  @override
  String get openTrip => 'Open trip';

  @override
  String get preCheck => 'Pre-trip check';

  @override
  String get preCheckAgain => 'Check again';

  @override
  String get pcReeferOn => 'Reefer is ON';

  @override
  String get pcSetpointChecked => 'Set temperature checked';

  @override
  String get pcDoorsClosed => 'Doors are closed';

  @override
  String get pcSetpoint => 'Reefer set temperature';

  @override
  String get pcSubmit => 'Save check';

  @override
  String get pcAllNeeded => 'Turn on all three checks to continue.';

  @override
  String get pcFailed => 'Check failed';

  @override
  String get pcReeferOff => 'The reefer is off';

  @override
  String get pcDoorsOpen => 'A door is open';

  @override
  String get pcSetpointOut => 'The set temperature is wrong for this cargo';

  @override
  String get pcIncompatible =>
      'These products cannot travel together. Call the control tower.';

  @override
  String pcAllowedRange(String min, String max) {
    return 'Allowed: $min to $max °C';
  }

  @override
  String get podAccepted => 'Accepted';

  @override
  String get podPartial => 'Partial';

  @override
  String get podRejected => 'Rejected';

  @override
  String get podAcceptedKg => 'Accepted weight';

  @override
  String podBatchWeight(String kg) {
    return 'Weight $kg kg';
  }

  @override
  String get podReason => 'Reason';

  @override
  String get podReceiver => 'Receiver name';

  @override
  String get podSignature => 'Receiver signature';

  @override
  String get podPhoto => 'Photo of the delivery';

  @override
  String get podPhotoDone => 'Photo taken';

  @override
  String get podPhotoHint => 'Show the crates at the receiver';

  @override
  String get podSubmit => 'Submit delivery';

  @override
  String get podSaved =>
      'Delivery saved. It is sent as soon as there is network.';

  @override
  String get podDone => 'Delivery recorded for this stop.';

  @override
  String podScanTitle(int done, int total) {
    return 'Scan each crate: $done of $total';
  }

  @override
  String podOtherStop(String code) {
    return 'Crate $code is for another stop. Keep it on the truck.';
  }

  @override
  String podUnknownCrate(String code) {
    return '$code is not on this truck.';
  }

  @override
  String get podNeedScan => 'scan the crate';

  @override
  String get podWrongTag => 'wrong crate';

  @override
  String get podNeedKg =>
      'enter the accepted weight (less than the full weight)';

  @override
  String get podNeedReason => 'enter a reason';

  @override
  String get podNeedReceiver => 'Enter the receiver name';

  @override
  String get podNeedSignature => 'Ask the receiver to sign';

  @override
  String get podNeedPhoto => 'Take the delivery photo';

  @override
  String get reasonDelay => 'Delay on the road: a faster order of stops';

  @override
  String get reasonIncident =>
      'Incident: the route changed to protect the cargo';

  @override
  String get reasonDiversion =>
      'Diversion: deliver to a nearer buyer before the cargo spoils';

  @override
  String get reasonRescue => 'Rescue: hand the cargo to another truck';

  @override
  String get reasonManual => 'The control tower changed the route';

  @override
  String get rerouteTitle => 'New route';

  @override
  String get rerouteOld => 'Was going to';

  @override
  String get rerouteNew => 'Now go to';

  @override
  String rerouteExtraKm(String km) {
    return '$km km longer';
  }

  @override
  String rerouteShorterKm(String km) {
    return '$km km shorter';
  }

  @override
  String get rerouteMustAccept =>
      'This route protects the cargo and must be accepted.';

  @override
  String get rerouteWaiting => 'A new route is waiting: tap to see';

  @override
  String shelfLifeDays(int days, int hours) {
    return '$days d $hours h left';
  }

  @override
  String shelfLifeHm(int hours, int minutes) {
    return '$hours h $minutes min left';
  }

  @override
  String get shelfLifeExpired => 'Shelf life over';

  @override
  String get shelfLifeUnknown => 'Shelf life not known yet';

  @override
  String get sos => 'SOS';

  @override
  String get sosSent => 'SOS sent';

  @override
  String get sosSentBody =>
      'Your location goes to the control tower and your emergency contact. Stay safe; help is coming.';

  @override
  String get speedLockTitle => 'Driving';

  @override
  String get speedLockBody =>
      'Stop the truck to use this screen. Navigate and SOS still work.';

  @override
  String get startTrip => 'Start trip';

  @override
  String get startNeedsPreCheck => 'Do the pre-trip check first.';

  @override
  String get stopArriveHint => 'Tap when the truck is at this stop.';

  @override
  String get stopPickupHint => 'Pickup stop: nothing to deliver here.';

  @override
  String get stopNotFound => 'This stop is no longer on the route.';

  @override
  String get stopPickup => 'Pickup';

  @override
  String get stopDrop => 'Delivery';

  @override
  String get stopDiversion => 'Diversion buyer';

  @override
  String get stopRescuePickup => 'Rescue pickup';

  @override
  String get stopRescueDrop => 'Hand over to rescue truck';

  @override
  String get stopColdStorage => 'Cold storage';

  @override
  String stopEta(String time) {
    return 'ETA $time';
  }

  @override
  String stopWindow(String window) {
    return 'Window $window';
  }

  @override
  String tripBatches(int count) {
    return 'Batches: $count';
  }

  @override
  String tripInProgress(String code) {
    return 'Trip $code in progress';
  }

  @override
  String get tripInProgressText => 'Location is shared with the control tower';

  @override
  String tripStarts(String time) {
    return 'Starts $time';
  }

  @override
  String tripVehicle(String regNo) {
    return 'Vehicle $regNo';
  }

  @override
  String get mgrDashboard => 'Dashboard';

  @override
  String get mgrTrips => 'Trips';

  @override
  String get mgrAlerts => 'Alerts';

  @override
  String get mgrPlanning => 'Planning';

  @override
  String get mgrForecast => 'Forecast';

  @override
  String get mgrApprovals => 'Approvals';

  @override
  String get mgrBuyers => 'Buyers & cold storage';

  @override
  String get mgrReports => 'Reports';

  @override
  String get mgrReleases => 'App releases';

  @override
  String get mgrMasters => 'Master data';

  @override
  String get mgrUsers => 'Users';

  @override
  String get mgrConfig => 'Remote config';

  @override
  String get mgrMore => 'More';

  @override
  String get kpiActiveTrips => 'Active trips';

  @override
  String get kpiCriticalAlerts => 'Open critical alerts';

  @override
  String get kpiAtRisk => 'Batches at risk (< 12 h)';

  @override
  String get kpiDeliveries => 'Deliveries today';

  @override
  String get kpiAvoided => 'Spoilage avoided (30 days)';

  @override
  String liveVehicles(int count) {
    return 'Vehicles on the road: $count';
  }

  @override
  String vehiclesNoPosition(int count) {
    return '$count without a position yet';
  }

  @override
  String get latestAlerts => 'Latest alerts';

  @override
  String get seeAll => 'See all';

  @override
  String get noAlerts => 'No alerts';

  @override
  String get refresh => 'Refresh';

  @override
  String get noDriver => 'No driver';

  @override
  String get tripStatus => 'Status';

  @override
  String get tripVehicleLabel => 'Vehicle';

  @override
  String get tripDriver => 'Driver';

  @override
  String get tripDistance => 'Distance';

  @override
  String get tripCo2 => 'Emissions';

  @override
  String get tripRouteVersion => 'Route';

  @override
  String get proposed => 'proposed';

  @override
  String get assignDriver => 'Assign driver and vehicle';

  @override
  String get telemetryTitle => 'Reefer temperature';

  @override
  String get noTelemetry => 'No sensor readings for this trip yet';

  @override
  String chartAllInBand(int count) {
    return '$count readings, all inside the safe range';
  }

  @override
  String chartExcursions(int bad, int count) {
    return '$bad of $count readings outside the safe range';
  }

  @override
  String get stopsTitle => 'Stops';

  @override
  String batchesOnTrip(int count) {
    return 'Batches on the trip: $count';
  }

  @override
  String get alertsTab => 'Alerts';

  @override
  String get incidentsTab => 'Incidents';

  @override
  String get resolve => 'Resolve';

  @override
  String get noIncidents => 'No incidents';

  @override
  String incidentSteps(int count) {
    return '$count steps';
  }

  @override
  String get incidentTitle => 'Incident';

  @override
  String rescueBy(String code) {
    return 'rescue: $code';
  }

  @override
  String get manualActions => 'Take over';

  @override
  String offersTitle(int count) {
    return 'Offers sent: $count';
  }

  @override
  String decisionLog(int count) {
    return 'Decision log ($count)';
  }

  @override
  String get resolveIncident => 'Mark this incident resolved?';

  @override
  String get markFailed => 'Cargo lost';

  @override
  String get markFailedConfirm => 'Close the incident as FAILED (cargo lost)?';

  @override
  String get pickBuyer => 'Choose the buyer';

  @override
  String get pickRescueTrip => 'Choose the rescue truck';

  @override
  String get nothingToPick => 'Nothing to choose from';

  @override
  String confirmAction(String action) {
    return 'Send $action?';
  }

  @override
  String get actionSent => 'Action sent';

  @override
  String get siteLabel => 'Site';

  @override
  String get productLabel => 'Product';

  @override
  String get pickSiteProduct => 'Choose a centre and a product';

  @override
  String get noForecast => 'No forecast for these days yet';

  @override
  String modelVersion(String version) {
    return 'Model $version';
  }

  @override
  String get runForecast => 'Run forecast now';

  @override
  String get forecastRunning => 'Forecast running…';

  @override
  String get forecastBusy => 'A forecast is already running';

  @override
  String jobStatus(String status) {
    return 'Last run: $status';
  }

  @override
  String planFor(String day) {
    return 'Plan for $day';
  }

  @override
  String get changeDate => 'Change date';

  @override
  String get runPlanner => 'Run planner';

  @override
  String get loadExistingOrders => 'Show existing orders for this day';

  @override
  String get plannerDone => 'Draft orders ready';

  @override
  String get needsTitle => 'Need per centre';

  @override
  String get forecastKg => 'Forecast';

  @override
  String get onHandKg => 'On hand';

  @override
  String get needKg => 'Need';

  @override
  String get shortfallKg => 'Shortfall';

  @override
  String ordersTitle(int count) {
    return 'Orders: $count';
  }

  @override
  String approveAll(int count) {
    return 'Approve all ($count)';
  }

  @override
  String get noOrders => 'No orders for this day';

  @override
  String get approve => 'Approve';

  @override
  String buildRoutes(int count) {
    return 'Build routes for $count approved orders';
  }

  @override
  String get noApprovedOrders => 'Approve at least one order first';

  @override
  String get pickDepot => 'Routes from which depot?';

  @override
  String get routesBuilt => 'Routes built';

  @override
  String tripsBuilt(int count) {
    return 'Trips planned: $count';
  }

  @override
  String editOrder(String code) {
    return 'Edit $code';
  }

  @override
  String get quantityKg => 'Quantity';

  @override
  String get destination => 'Destination';

  @override
  String get invalidQuantity => 'Enter a quantity above 0';

  @override
  String get loadFailed => 'Could not load the lists. Try again.';

  @override
  String get editRequestsTab => 'Edit requests';

  @override
  String get disputesTab => 'Grade disputes';

  @override
  String get nothingPending => 'Nothing waiting';

  @override
  String requestedBy(String name, String time) {
    return '$name · $time';
  }

  @override
  String reasonIs(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get rejected => 'Rejected';

  @override
  String get approved => 'Approved';

  @override
  String aiConfidence(int percent) {
    return 'AI confidence $percent %';
  }

  @override
  String get setGrade => 'Set the grade';

  @override
  String gradeSet(String grade) {
    return 'Grade set to $grade';
  }

  @override
  String get addBuyer => 'Add buyer';

  @override
  String get editBuyer => 'Edit buyer';

  @override
  String get noBuyers => 'No buyers yet';

  @override
  String minGradeIs(String grade) {
    return 'min grade $grade';
  }

  @override
  String acceptsProducts(int count) {
    return 'Accepts $count products';
  }

  @override
  String get deactivate => 'Deactivate';

  @override
  String get deactivateBuyer => 'Deactivate this buyer? Past offers are kept.';

  @override
  String get fieldRequired => 'Required';

  @override
  String numberBetween(String min, String max) {
    return 'A number from $min to $max';
  }

  @override
  String hoursInvalid(String day) {
    return 'Check the hours for $day (HH:MM, at most 4 ranges)';
  }

  @override
  String get pickOneProduct => 'Choose at least one product';

  @override
  String hoursFor(String day) {
    return 'Hours on $day';
  }

  @override
  String get opens => 'Opens';

  @override
  String get closes => 'Closes';

  @override
  String get closedDay => 'Closed';

  @override
  String get name => 'Name';

  @override
  String get typeLabel => 'Type';

  @override
  String get phoneE164 => 'Phone (+91…)';

  @override
  String get phoneInvalidE164 =>
      'Enter the number with the country code, e.g. +919812345678';

  @override
  String get emailOptional => 'Email (optional)';

  @override
  String get latitude => 'Latitude';

  @override
  String get longitude => 'Longitude';

  @override
  String get discountPct => 'Discount';

  @override
  String get minGrade => 'Minimum grade';

  @override
  String get capacityOptional => 'Capacity (optional)';

  @override
  String get acceptedProducts => 'Products accepted';

  @override
  String get openingHours => 'Opening hours (IST)';

  @override
  String get save => 'Save';

  @override
  String get complianceReport => 'Compliance report per batch';

  @override
  String get batchCodeOrTag => 'Batch code or tag';

  @override
  String get search => 'Search';

  @override
  String periodIs(String from, String to) {
    return '$from to $to';
  }

  @override
  String get traceabilityCsv => 'Traceability export (CSV)';

  @override
  String get emissionsReport => 'Emissions';

  @override
  String emissionsTotals(int trips, String km, String co2) {
    return '$trips trips · $km km · $co2 kg CO₂';
  }

  @override
  String emissionFactor(String value, String source) {
    return 'Factor $value kg/km ($source)';
  }

  @override
  String get downloadCsv => 'Download CSV';

  @override
  String get reeferHealth => 'Reefer health';

  @override
  String get noData => 'Nothing here yet';

  @override
  String get noWeeks => 'No weekly check yet';

  @override
  String degradation(String pct) {
    return 'Pull-down slower by $pct %';
  }

  @override
  String get flagged => 'Needs service';

  @override
  String get noReleases => 'No releases published yet';

  @override
  String get noReleasesHint =>
      'Releases appear here once the GitHub release sync runs.';

  @override
  String get mandatory => 'mandatory';

  @override
  String get add => 'Add';

  @override
  String get inactive => 'inactive';

  @override
  String get notANumber => 'Enter a number';

  @override
  String get secretHelp =>
      '16–128 characters; it is stored hashed and never shown again';

  @override
  String get secretKeep => 'Leave empty to keep the current secret';

  @override
  String get secretLength => '16 to 128 characters';

  @override
  String get immutable => 'Cannot be changed';

  @override
  String get addUser => 'Add user';

  @override
  String get disabled => 'Disabled';

  @override
  String get roleLabel => 'Role';

  @override
  String get emailInvalid => 'Enter a valid email';

  @override
  String get siteRequired => 'Drivers and operators need a site';

  @override
  String get emergencyContact => 'Emergency contact (+91…)';

  @override
  String get enableUser => 'Enable user';

  @override
  String get disableUser => 'Disable user';

  @override
  String get disableUserConfirm =>
      'Disable this user? They are signed out on every device.';

  @override
  String get configHint =>
      'Values are checked by the server; a wrong shape is refused.';

  @override
  String get notSet => 'Not set (default)';

  @override
  String get jsonValue => 'JSON value';

  @override
  String get invalidJson => 'That is not valid JSON';

  @override
  String operatorSays(String reason) {
    return 'Operator says: $reason';
  }

  @override
  String get tripAssigned => 'Driver and vehicle assigned';
}
