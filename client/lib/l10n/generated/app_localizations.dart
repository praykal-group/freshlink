import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_mr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('mr'),
  ];

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginTitle;

  /// No description provided for @loginSubtitlePhone.
  ///
  /// In en, this message translates to:
  /// **'Use the mobile number your manager registered.'**
  String get loginSubtitlePhone;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get phoneLabel;

  /// No description provided for @phoneHelper.
  ///
  /// In en, this message translates to:
  /// **'We will send a 6-digit code by SMS'**
  String get phoneHelper;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get otpTitle;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {phone}'**
  String otpSentTo(String phone);

  /// No description provided for @otpLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get otpLabel;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds} s'**
  String resendIn(int seconds);

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @codeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way'**
  String get codeResent;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @orDivider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orDivider;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @usePhoneInstead.
  ///
  /// In en, this message translates to:
  /// **'Use phone OTP instead'**
  String get usePhoneInstead;

  /// No description provided for @useEmailInstead.
  ///
  /// In en, this message translates to:
  /// **'Use email instead'**
  String get useEmailInstead;

  /// No description provided for @resetSent.
  ///
  /// In en, this message translates to:
  /// **'If this email has an account, a reset link is on its way.'**
  String get resetSent;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your inbox'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailBody.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to {email}. Open it, then sign in again.'**
  String verifyEmailBody(String email);

  /// No description provided for @resendEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get resendEmail;

  /// No description provided for @emailResent.
  ///
  /// In en, this message translates to:
  /// **'Email sent again'**
  String get emailResent;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get backToLogin;

  /// No description provided for @errorRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get errorRequired;

  /// No description provided for @errorPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a 10-digit mobile number'**
  String get errorPhone;

  /// No description provided for @errorOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get errorOtp;

  /// No description provided for @errorEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get errorEmail;

  /// No description provided for @errorPasswordShort.
  ///
  /// In en, this message translates to:
  /// **'At least {min} characters'**
  String errorPasswordShort(int min);

  /// No description provided for @errorNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number'**
  String get errorNotANumber;

  /// No description provided for @errorBelowMin.
  ///
  /// In en, this message translates to:
  /// **'Must be at least {min}'**
  String errorBelowMin(String min);

  /// No description provided for @errorAboveMax.
  ///
  /// In en, this message translates to:
  /// **'Must be at most {max}'**
  String errorAboveMax(String max);

  /// No description provided for @authInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get authInvalidCredentials;

  /// No description provided for @authEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email first. Check your inbox.'**
  String get authEmailNotConfirmed;

  /// No description provided for @authOtpInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code is not right. Check the SMS and try again.'**
  String get authOtpInvalid;

  /// No description provided for @authOtpExpired.
  ///
  /// In en, this message translates to:
  /// **'The code has expired. Ask for a new one.'**
  String get authOtpExpired;

  /// No description provided for @authRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes and try again.'**
  String get authRateLimited;

  /// No description provided for @authNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'This number or email is not registered. Ask your manager.'**
  String get authNotRegistered;

  /// No description provided for @authNetwork.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check the internet and try again.'**
  String get authNetwork;

  /// No description provided for @authNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is not set up in this build.'**
  String get authNotConfigured;

  /// No description provided for @authCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled.'**
  String get authCancelled;

  /// No description provided for @authUnknown.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Try again.'**
  String get authUnknown;

  /// No description provided for @reasonWrongApp.
  ///
  /// In en, this message translates to:
  /// **'Your account cannot use this app. Please use the app for your role.'**
  String get reasonWrongApp;

  /// No description provided for @reasonNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Your account is not active. Contact your manager.'**
  String get reasonNotRegistered;

  /// No description provided for @reasonOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'You logged in on another phone, so this phone was signed out.'**
  String get reasonOtherDevice;

  /// No description provided for @reasonUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Please sign in again.'**
  String get reasonUnauthorized;

  /// No description provided for @reasonGeneric.
  ///
  /// In en, this message translates to:
  /// **'Could not sign in ({code}). Try again.'**
  String reasonGeneric(String code);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Same as phone'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @settingsSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settingsSync;

  /// No description provided for @syncPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Everything is synced} =1{1 change waiting to sync} other{{count} changes waiting to sync}}'**
  String syncPending(int count);

  /// No description provided for @openSyncQueue.
  ///
  /// In en, this message translates to:
  /// **'Open sync queue'**
  String get openSyncQueue;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} (build {code})'**
  String aboutVersion(String version, String code);

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this phone?'**
  String get signOutConfirm;

  /// No description provided for @signOutPendingWarning.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change has not synced yet. It stays on this phone and syncs after you sign in again.} other{{count} changes have not synced yet. They stay on this phone and sync after you sign in again.}}'**
  String signOutPendingWarning(int count);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @syncQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync queue'**
  String get syncQueueTitle;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get syncNeedsAttention;

  /// No description provided for @syncWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get syncWaiting;

  /// No description provided for @syncNextTry.
  ///
  /// In en, this message translates to:
  /// **'Next try at {time}'**
  String syncNextTry(String time);

  /// No description provided for @syncFiles.
  ///
  /// In en, this message translates to:
  /// **'Files to upload'**
  String get syncFiles;

  /// No description provided for @syncEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting. All your changes are on the server.'**
  String get syncEmpty;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @discardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard this change? The server refused it and it will be lost.'**
  String get discardConfirm;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Offline. Your changes are saved and will sync.'**
  String get offlineBanner;

  /// No description provided for @updatedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Updated just now'**
  String get updatedJustNow;

  /// No description provided for @updatedAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{Updated 1 min ago} other{Updated {minutes} min ago}}'**
  String updatedAgo(int minutes);

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyTitle;

  /// No description provided for @homeWelcome.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String homeWelcome(String name);

  /// No description provided for @homeComingSoon.
  ///
  /// In en, this message translates to:
  /// **'The screens of this app arrive in the next release.'**
  String get homeComingSoon;

  /// No description provided for @updateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'This version is no longer supported. Install the latest version to continue.'**
  String get updateRequiredBody;

  /// No description provided for @statusSafe.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get statusSafe;

  /// No description provided for @statusWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get statusWatch;

  /// No description provided for @statusCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get statusCritical;

  /// No description provided for @statusInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get statusInfo;

  /// No description provided for @voiceInput.
  ///
  /// In en, this message translates to:
  /// **'Speak the value'**
  String get voiceInput;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @todayAtSite.
  ///
  /// In en, this message translates to:
  /// **'Today at {site}'**
  String todayAtSite(String site);

  /// No description provided for @countRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get countRegistered;

  /// No description provided for @countGraded.
  ///
  /// In en, this message translates to:
  /// **'Graded'**
  String get countGraded;

  /// No description provided for @countStored.
  ///
  /// In en, this message translates to:
  /// **'In storage'**
  String get countStored;

  /// No description provided for @countDispatched.
  ///
  /// In en, this message translates to:
  /// **'Dispatched'**
  String get countDispatched;

  /// No description provided for @newFishBatch.
  ///
  /// In en, this message translates to:
  /// **'New fish batch'**
  String get newFishBatch;

  /// No description provided for @newProduceBatch.
  ///
  /// In en, this message translates to:
  /// **'New produce batch'**
  String get newProduceBatch;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @loadTruck.
  ///
  /// In en, this message translates to:
  /// **'Load truck'**
  String get loadTruck;

  /// No description provided for @batches.
  ///
  /// In en, this message translates to:
  /// **'Batches'**
  String get batches;

  /// No description provided for @printer.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get printer;

  /// No description provided for @resumeDraft.
  ///
  /// In en, this message translates to:
  /// **'Continue the batch you started'**
  String get resumeDraft;

  /// No description provided for @discardDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardDraft;

  /// No description provided for @stepForm.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get stepForm;

  /// No description provided for @stepTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get stepTag;

  /// No description provided for @stepPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get stepPhotos;

  /// No description provided for @stepGrade.
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get stepGrade;

  /// No description provided for @stepStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get stepStorage;

  /// No description provided for @stepLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get stepLabel;

  /// No description provided for @stepDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get stepDone;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {n} of {total}'**
  String stepOf(int n, int total);

  /// No description provided for @product.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// No description provided for @catchTime.
  ///
  /// In en, this message translates to:
  /// **'Catch time'**
  String get catchTime;

  /// No description provided for @harvestTime.
  ///
  /// In en, this message translates to:
  /// **'Harvest time'**
  String get harvestTime;

  /// No description provided for @weight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get weight;

  /// No description provided for @vesselId.
  ///
  /// In en, this message translates to:
  /// **'Vessel ID'**
  String get vesselId;

  /// No description provided for @farmRef.
  ///
  /// In en, this message translates to:
  /// **'Farm ID'**
  String get farmRef;

  /// No description provided for @iceRatio.
  ///
  /// In en, this message translates to:
  /// **'Ice-to-fish ratio'**
  String get iceRatio;

  /// No description provided for @coreTemp.
  ///
  /// In en, this message translates to:
  /// **'Core temperature'**
  String get coreTemp;

  /// No description provided for @maturity.
  ///
  /// In en, this message translates to:
  /// **'Maturity index'**
  String get maturity;

  /// No description provided for @brix.
  ///
  /// In en, this message translates to:
  /// **'Brix'**
  String get brix;

  /// No description provided for @fieldTemp.
  ///
  /// In en, this message translates to:
  /// **'Field temperature'**
  String get fieldTemp;

  /// No description provided for @fieldHumidity.
  ///
  /// In en, this message translates to:
  /// **'Field humidity'**
  String get fieldHumidity;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening… say the number'**
  String get listening;

  /// No description provided for @voiceNotHeard.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t catch a number. Try again or type it.'**
  String get voiceNotHeard;

  /// No description provided for @mastersMissing.
  ///
  /// In en, this message translates to:
  /// **'Master lists are not downloaded yet. Connect once to download them.'**
  String get mastersMissing;

  /// No description provided for @tagChoose.
  ///
  /// In en, this message translates to:
  /// **'Tag the crate'**
  String get tagChoose;

  /// No description provided for @tagNfc.
  ///
  /// In en, this message translates to:
  /// **'Tap NFC tag'**
  String get tagNfc;

  /// No description provided for @tagQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get tagQr;

  /// No description provided for @tagWedge.
  ///
  /// In en, this message translates to:
  /// **'RFID reader'**
  String get tagWedge;

  /// No description provided for @tagRead.
  ///
  /// In en, this message translates to:
  /// **'Tag {uid}'**
  String tagRead(String uid);

  /// No description provided for @tagInvalid.
  ///
  /// In en, this message translates to:
  /// **'This is not a valid tag'**
  String get tagInvalid;

  /// No description provided for @tagWedgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan with the RFID reader'**
  String get tagWedgeTitle;

  /// No description provided for @tagWedgeHelp.
  ///
  /// In en, this message translates to:
  /// **'Pull the reader trigger, or type the tag number and press Enter.'**
  String get tagWedgeHelp;

  /// No description provided for @nfcHold.
  ///
  /// In en, this message translates to:
  /// **'Hold the tag to the back of the phone'**
  String get nfcHold;

  /// No description provided for @nfcUnavailable.
  ///
  /// In en, this message translates to:
  /// **'NFC is off or not available. Use QR or the RFID reader.'**
  String get nfcUnavailable;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @scanQrHelp.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code'**
  String get scanQrHelp;

  /// No description provided for @photoTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get photoTop;

  /// No description provided for @photoSide.
  ///
  /// In en, this message translates to:
  /// **'Side'**
  String get photoSide;

  /// No description provided for @photoCloseup.
  ///
  /// In en, this message translates to:
  /// **'Close-up'**
  String get photoCloseup;

  /// No description provided for @photoHelpTop.
  ///
  /// In en, this message translates to:
  /// **'From above: the whole crate inside the frame'**
  String get photoHelpTop;

  /// No description provided for @photoHelpSide.
  ///
  /// In en, this message translates to:
  /// **'From the side: show the depth of the crate'**
  String get photoHelpSide;

  /// No description provided for @photoHelpCloseup.
  ///
  /// In en, this message translates to:
  /// **'Close-up: one fish or fruit fills the frame'**
  String get photoHelpCloseup;

  /// No description provided for @retake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get retake;

  /// No description provided for @photosNeeded.
  ///
  /// In en, this message translates to:
  /// **'Take all three photos'**
  String get photosNeeded;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera is not available'**
  String get cameraUnavailable;

  /// No description provided for @gradeWaiting.
  ///
  /// In en, this message translates to:
  /// **'Grading…'**
  String get gradeWaiting;

  /// No description provided for @gradeQueued.
  ///
  /// In en, this message translates to:
  /// **'Grading queued. The grade arrives when the phone is online.'**
  String get gradeQueued;

  /// No description provided for @gradeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Grading is not available right now. It is queued and runs later.'**
  String get gradeUnavailable;

  /// No description provided for @gradeResult.
  ///
  /// In en, this message translates to:
  /// **'Grade {grade}'**
  String gradeResult(String grade);

  /// No description provided for @confidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence {pct}%'**
  String confidence(int pct);

  /// No description provided for @defects.
  ///
  /// In en, this message translates to:
  /// **'Defects'**
  String get defects;

  /// No description provided for @noDefects.
  ///
  /// In en, this message translates to:
  /// **'No defects found'**
  String get noDefects;

  /// No description provided for @dispute.
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get dispute;

  /// No description provided for @disputeReason.
  ///
  /// In en, this message translates to:
  /// **'Why is the grade wrong?'**
  String get disputeReason;

  /// No description provided for @disputeSent.
  ///
  /// In en, this message translates to:
  /// **'Dispute sent to the manager'**
  String get disputeSent;

  /// No description provided for @pathBlastChiller.
  ///
  /// In en, this message translates to:
  /// **'Blast chiller'**
  String get pathBlastChiller;

  /// No description provided for @pathRipening.
  ///
  /// In en, this message translates to:
  /// **'Ripening chamber'**
  String get pathRipening;

  /// No description provided for @pathColdRoom.
  ///
  /// In en, this message translates to:
  /// **'Cold room'**
  String get pathColdRoom;

  /// No description provided for @sellFirst.
  ///
  /// In en, this message translates to:
  /// **'Sell first'**
  String get sellFirst;

  /// No description provided for @recommendedUnit.
  ///
  /// In en, this message translates to:
  /// **'Recommended: {unit} ({free} kg free)'**
  String recommendedUnit(String unit, String free);

  /// No description provided for @noUnit.
  ///
  /// In en, this message translates to:
  /// **'No suitable unit is free at this site'**
  String get noUnit;

  /// No description provided for @assign.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get assign;

  /// No description provided for @assigned.
  ///
  /// In en, this message translates to:
  /// **'Stored in {unit}'**
  String assigned(String unit);

  /// No description provided for @storageOffline.
  ///
  /// In en, this message translates to:
  /// **'Shown from this phone\'s lists. Assign it when you are online.'**
  String get storageOffline;

  /// No description provided for @print.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get print;

  /// No description provided for @shareImage.
  ///
  /// In en, this message translates to:
  /// **'Share image'**
  String get shareImage;

  /// No description provided for @labelOffline.
  ///
  /// In en, this message translates to:
  /// **'The label is ready once the batch has synced.'**
  String get labelOffline;

  /// No description provided for @noPrinter.
  ///
  /// In en, this message translates to:
  /// **'No printer set up'**
  String get noPrinter;

  /// No description provided for @printed.
  ///
  /// In en, this message translates to:
  /// **'Label sent to the printer'**
  String get printed;

  /// No description provided for @printFailed.
  ///
  /// In en, this message translates to:
  /// **'Printing failed. Share the label as an image instead.'**
  String get printFailed;

  /// No description provided for @doneTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch registered'**
  String get doneTitle;

  /// No description provided for @doneTime.
  ///
  /// In en, this message translates to:
  /// **'Done in {seconds} s'**
  String doneTime(int seconds);

  /// No description provided for @newBatch.
  ///
  /// In en, this message translates to:
  /// **'New batch'**
  String get newBatch;

  /// No description provided for @goHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get goHome;

  /// No description provided for @pendingSync.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get pendingSync;

  /// No description provided for @searchBatches.
  ///
  /// In en, this message translates to:
  /// **'Search code or tag'**
  String get searchBatches;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @stRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get stRegistered;

  /// No description provided for @stGraded.
  ///
  /// In en, this message translates to:
  /// **'Graded'**
  String get stGraded;

  /// No description provided for @stStored.
  ///
  /// In en, this message translates to:
  /// **'Stored'**
  String get stStored;

  /// No description provided for @stAllocated.
  ///
  /// In en, this message translates to:
  /// **'Allocated'**
  String get stAllocated;

  /// No description provided for @stLoaded.
  ///
  /// In en, this message translates to:
  /// **'Loaded'**
  String get stLoaded;

  /// No description provided for @stInTransit.
  ///
  /// In en, this message translates to:
  /// **'In transit'**
  String get stInTransit;

  /// No description provided for @stDiverted.
  ///
  /// In en, this message translates to:
  /// **'Diverted'**
  String get stDiverted;

  /// No description provided for @stDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get stDelivered;

  /// No description provided for @stPartial.
  ///
  /// In en, this message translates to:
  /// **'Partly delivered'**
  String get stPartial;

  /// No description provided for @stRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get stRejected;

  /// No description provided for @stSpoiled.
  ///
  /// In en, this message translates to:
  /// **'Spoiled'**
  String get stSpoiled;

  /// No description provided for @shelfLifeHours.
  ///
  /// In en, this message translates to:
  /// **'Shelf life {hours} h'**
  String shelfLifeHours(String hours);

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @chainVerified.
  ///
  /// In en, this message translates to:
  /// **'Record chain verified'**
  String get chainVerified;

  /// No description provided for @chainBroken.
  ///
  /// In en, this message translates to:
  /// **'Record chain NOT verified'**
  String get chainBroken;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @requestEdit.
  ///
  /// In en, this message translates to:
  /// **'Request edit'**
  String get requestEdit;

  /// No description provided for @editMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 min left to edit} other{{minutes} min left to edit}}'**
  String editMinutesLeft(int minutes);

  /// No description provided for @editClosed.
  ///
  /// In en, this message translates to:
  /// **'The 30-minute edit window has closed. Ask the manager.'**
  String get editClosed;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @requestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent to the manager'**
  String get requestSent;

  /// No description provided for @printLabel.
  ///
  /// In en, this message translates to:
  /// **'Print label'**
  String get printLabel;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @onlineOnly.
  ///
  /// In en, this message translates to:
  /// **'This needs an internet connection.'**
  String get onlineOnly;

  /// No description provided for @scanBatch.
  ///
  /// In en, this message translates to:
  /// **'Scan the batch'**
  String get scanBatch;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'No batch found for {value}'**
  String notFound(String value);

  /// No description provided for @condition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get condition;

  /// No description provided for @condGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get condGood;

  /// No description provided for @condFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get condFair;

  /// No description provided for @condPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get condPoor;

  /// No description provided for @damagePhotos.
  ///
  /// In en, this message translates to:
  /// **'Damage photos'**
  String get damagePhotos;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @outcome.
  ///
  /// In en, this message translates to:
  /// **'Outcome'**
  String get outcome;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @partial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get partial;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @acceptedWeight.
  ///
  /// In en, this message translates to:
  /// **'Accepted weight'**
  String get acceptedWeight;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @receiveSaved.
  ///
  /// In en, this message translates to:
  /// **'Receiving saved. It syncs when the phone is online.'**
  String get receiveSaved;

  /// No description provided for @noTrips.
  ///
  /// In en, this message translates to:
  /// **'No trips to load today'**
  String get noTrips;

  /// No description provided for @loadedCount.
  ///
  /// In en, this message translates to:
  /// **'{n} of {total} loaded'**
  String loadedCount(int n, int total);

  /// No description provided for @wrongBatch.
  ///
  /// In en, this message translates to:
  /// **'Not for this trip: {code}'**
  String wrongBatch(String code);

  /// No description provided for @alreadyScanned.
  ///
  /// In en, this message translates to:
  /// **'Already scanned'**
  String get alreadyScanned;

  /// No description provided for @confirmLoad.
  ///
  /// In en, this message translates to:
  /// **'Confirm loading'**
  String get confirmLoad;

  /// No description provided for @loadSaved.
  ///
  /// In en, this message translates to:
  /// **'Loading saved. It syncs when the phone is online.'**
  String get loadSaved;

  /// No description provided for @scanNext.
  ///
  /// In en, this message translates to:
  /// **'Scan next crate'**
  String get scanNext;

  /// No description provided for @pairedPrinters.
  ///
  /// In en, this message translates to:
  /// **'Paired printers'**
  String get pairedPrinters;

  /// No description provided for @noPairedPrinters.
  ///
  /// In en, this message translates to:
  /// **'No paired printer. Pair the printer in the phone’s Bluetooth settings first.'**
  String get noPairedPrinters;

  /// No description provided for @testPrint.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get testPrint;

  /// No description provided for @selectedPrinter.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selectedPrinter;

  /// No description provided for @bluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off. Turn it on to print.'**
  String get bluetoothOff;

  /// No description provided for @acceptReroute.
  ///
  /// In en, this message translates to:
  /// **'Accept new route'**
  String get acceptReroute;

  /// No description provided for @declineReroute.
  ///
  /// In en, this message translates to:
  /// **'Keep current route'**
  String get declineReroute;

  /// No description provided for @acknowledge.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge'**
  String get acknowledge;

  /// No description provided for @alertTemp.
  ///
  /// In en, this message translates to:
  /// **'Temperature out of range'**
  String get alertTemp;

  /// No description provided for @alertTempDo.
  ///
  /// In en, this message translates to:
  /// **'Check the reefer is running and the setpoint is right. Keep the doors closed.'**
  String get alertTempDo;

  /// No description provided for @alertDriverFix.
  ///
  /// In en, this message translates to:
  /// **'Temperature drifting'**
  String get alertDriverFix;

  /// No description provided for @alertDriverFixDo.
  ///
  /// In en, this message translates to:
  /// **'Check the door seals, the reefer setpoint and that the airflow is not blocked. Re-checked in 15 minutes.'**
  String get alertDriverFixDo;

  /// No description provided for @alertSpoilage.
  ///
  /// In en, this message translates to:
  /// **'Cargo at risk of spoiling'**
  String get alertSpoilage;

  /// No description provided for @alertSpoilageDo.
  ///
  /// In en, this message translates to:
  /// **'Wait for the new route from the control tower and accept it.'**
  String get alertSpoilageDo;

  /// No description provided for @alertHumidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity out of range'**
  String get alertHumidity;

  /// No description provided for @alertHumidityDo.
  ///
  /// In en, this message translates to:
  /// **'Check the doors and the reefer.'**
  String get alertHumidityDo;

  /// No description provided for @alertEthylene.
  ///
  /// In en, this message translates to:
  /// **'Ethylene high'**
  String get alertEthylene;

  /// No description provided for @alertEthyleneDo.
  ///
  /// In en, this message translates to:
  /// **'Ventilate if safe and tell the control tower.'**
  String get alertEthyleneDo;

  /// No description provided for @alertShock.
  ///
  /// In en, this message translates to:
  /// **'Hard shock detected'**
  String get alertShock;

  /// No description provided for @alertShockDo.
  ///
  /// In en, this message translates to:
  /// **'Stop when safe and check the cargo.'**
  String get alertShockDo;

  /// No description provided for @alertDevice.
  ///
  /// In en, this message translates to:
  /// **'Sensor offline'**
  String get alertDevice;

  /// No description provided for @alertDeviceDo.
  ///
  /// In en, this message translates to:
  /// **'Check the sensor pod power and cable.'**
  String get alertDeviceDo;

  /// No description provided for @alertGeneric.
  ///
  /// In en, this message translates to:
  /// **'Cargo alert'**
  String get alertGeneric;

  /// No description provided for @alertGenericDo.
  ///
  /// In en, this message translates to:
  /// **'Read the message and follow the control tower.'**
  String get alertGenericDo;

  /// No description provided for @allStopsDone.
  ///
  /// In en, this message translates to:
  /// **'All stops done. Drive back to the depot.'**
  String get allStopsDone;

  /// No description provided for @allUploaded.
  ///
  /// In en, this message translates to:
  /// **'Everything is uploaded'**
  String get allUploaded;

  /// No description provided for @pendingUploads.
  ///
  /// In en, this message translates to:
  /// **'{count} items waiting to upload'**
  String pendingUploads(int count);

  /// No description provided for @arrived.
  ///
  /// In en, this message translates to:
  /// **'I have arrived'**
  String get arrived;

  /// No description provided for @deliverHere.
  ///
  /// In en, this message translates to:
  /// **'Deliver here'**
  String get deliverHere;

  /// No description provided for @cargoStatus.
  ///
  /// In en, this message translates to:
  /// **'Cargo'**
  String get cargoStatus;

  /// No description provided for @cargoTemp.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get cargoTemp;

  /// No description provided for @cargoHumidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity'**
  String get cargoHumidity;

  /// No description provided for @cargoLowestShelfLife.
  ///
  /// In en, this message translates to:
  /// **'Lowest shelf life: {value}'**
  String cargoLowestShelfLife(String value);

  /// No description provided for @cargoAsOf.
  ///
  /// In en, this message translates to:
  /// **'Last update {time} (offline)'**
  String cargoAsOf(String time);

  /// No description provided for @cargoEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cargo on board'**
  String get cargoEmpty;

  /// No description provided for @cargoSafeRange.
  ///
  /// In en, this message translates to:
  /// **'Safe {min} to {max} °C'**
  String cargoSafeRange(String min, String max);

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @gpsOff.
  ///
  /// In en, this message translates to:
  /// **'Location is off. Turn it on to start the trip.'**
  String get gpsOff;

  /// No description provided for @gpsDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission is needed to track the trip.'**
  String get gpsDenied;

  /// No description provided for @gpsDeniedForever.
  ///
  /// In en, this message translates to:
  /// **'Location permission is blocked. Allow it in settings.'**
  String get gpsDeniedForever;

  /// No description provided for @gpsFailed.
  ///
  /// In en, this message translates to:
  /// **'Trip tracking could not start. Try again.'**
  String get gpsFailed;

  /// No description provided for @notificationsDenied.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications so you can see that the trip is tracked.'**
  String get notificationsDenied;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @historyPods.
  ///
  /// In en, this message translates to:
  /// **'Deliveries recorded: {count}'**
  String historyPods(int count);

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No trips yet'**
  String get noHistory;

  /// No description provided for @tripHistory.
  ///
  /// In en, this message translates to:
  /// **'Trip history'**
  String get tripHistory;

  /// No description provided for @incDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get incDelay;

  /// No description provided for @incBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get incBreakdown;

  /// No description provided for @incAccident.
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get incAccident;

  /// No description provided for @incRoadblock.
  ///
  /// In en, this message translates to:
  /// **'Road block'**
  String get incRoadblock;

  /// No description provided for @incReeferFault.
  ///
  /// In en, this message translates to:
  /// **'Reefer fault'**
  String get incReeferFault;

  /// No description provided for @incPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get incPhoto;

  /// No description provided for @incPhotoDone.
  ///
  /// In en, this message translates to:
  /// **'Photo added'**
  String get incPhotoDone;

  /// No description provided for @incPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'Show the problem'**
  String get incPhotoHint;

  /// No description provided for @incVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get incVoice;

  /// No description provided for @incVoiceDone.
  ///
  /// In en, this message translates to:
  /// **'Voice note {seconds} s'**
  String incVoiceDone(int seconds);

  /// No description provided for @incVoiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop ({seconds} s left)'**
  String incVoiceStop(int seconds);

  /// No description provided for @incSend.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get incSend;

  /// No description provided for @incSent.
  ///
  /// In en, this message translates to:
  /// **'Report saved. It is sent as soon as there is network.'**
  String get incSent;

  /// No description provided for @incQueuedHint.
  ///
  /// In en, this message translates to:
  /// **'Works without network: it is sent later.'**
  String get incQueuedHint;

  /// No description provided for @reportIncident.
  ///
  /// In en, this message translates to:
  /// **'Report incident'**
  String get reportIncident;

  /// No description provided for @micDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is needed for a voice note.'**
  String get micDenied;

  /// No description provided for @navigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get navigate;

  /// No description provided for @nextStop.
  ///
  /// In en, this message translates to:
  /// **'Next stop'**
  String get nextStop;

  /// No description provided for @noTripToday.
  ///
  /// In en, this message translates to:
  /// **'No trip today'**
  String get noTripToday;

  /// No description provided for @noTripTodayHint.
  ///
  /// In en, this message translates to:
  /// **'Pull down to check again.'**
  String get noTripTodayHint;

  /// No description provided for @openAlerts.
  ///
  /// In en, this message translates to:
  /// **'{count} open alerts: tap to see'**
  String openAlerts(int count);

  /// No description provided for @openTrip.
  ///
  /// In en, this message translates to:
  /// **'Open trip'**
  String get openTrip;

  /// No description provided for @preCheck.
  ///
  /// In en, this message translates to:
  /// **'Pre-trip check'**
  String get preCheck;

  /// No description provided for @preCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get preCheckAgain;

  /// No description provided for @pcReeferOn.
  ///
  /// In en, this message translates to:
  /// **'Reefer is ON'**
  String get pcReeferOn;

  /// No description provided for @pcSetpointChecked.
  ///
  /// In en, this message translates to:
  /// **'Set temperature checked'**
  String get pcSetpointChecked;

  /// No description provided for @pcDoorsClosed.
  ///
  /// In en, this message translates to:
  /// **'Doors are closed'**
  String get pcDoorsClosed;

  /// No description provided for @pcSetpoint.
  ///
  /// In en, this message translates to:
  /// **'Reefer set temperature'**
  String get pcSetpoint;

  /// No description provided for @pcSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save check'**
  String get pcSubmit;

  /// No description provided for @pcAllNeeded.
  ///
  /// In en, this message translates to:
  /// **'Turn on all three checks to continue.'**
  String get pcAllNeeded;

  /// No description provided for @pcFailed.
  ///
  /// In en, this message translates to:
  /// **'Check failed'**
  String get pcFailed;

  /// No description provided for @pcReeferOff.
  ///
  /// In en, this message translates to:
  /// **'The reefer is off'**
  String get pcReeferOff;

  /// No description provided for @pcDoorsOpen.
  ///
  /// In en, this message translates to:
  /// **'A door is open'**
  String get pcDoorsOpen;

  /// No description provided for @pcSetpointOut.
  ///
  /// In en, this message translates to:
  /// **'The set temperature is wrong for this cargo'**
  String get pcSetpointOut;

  /// No description provided for @pcIncompatible.
  ///
  /// In en, this message translates to:
  /// **'These products cannot travel together. Call the control tower.'**
  String get pcIncompatible;

  /// No description provided for @pcAllowedRange.
  ///
  /// In en, this message translates to:
  /// **'Allowed: {min} to {max} °C'**
  String pcAllowedRange(String min, String max);

  /// No description provided for @podAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get podAccepted;

  /// No description provided for @podPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get podPartial;

  /// No description provided for @podRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get podRejected;

  /// No description provided for @podAcceptedKg.
  ///
  /// In en, this message translates to:
  /// **'Accepted weight'**
  String get podAcceptedKg;

  /// No description provided for @podBatchWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight {kg} kg'**
  String podBatchWeight(String kg);

  /// No description provided for @podReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get podReason;

  /// No description provided for @podReceiver.
  ///
  /// In en, this message translates to:
  /// **'Receiver name'**
  String get podReceiver;

  /// No description provided for @podSignature.
  ///
  /// In en, this message translates to:
  /// **'Receiver signature'**
  String get podSignature;

  /// No description provided for @podPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo of the delivery'**
  String get podPhoto;

  /// No description provided for @podPhotoDone.
  ///
  /// In en, this message translates to:
  /// **'Photo taken'**
  String get podPhotoDone;

  /// No description provided for @podPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'Show the crates at the receiver'**
  String get podPhotoHint;

  /// No description provided for @podSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit delivery'**
  String get podSubmit;

  /// No description provided for @podSaved.
  ///
  /// In en, this message translates to:
  /// **'Delivery saved. It is sent as soon as there is network.'**
  String get podSaved;

  /// No description provided for @podDone.
  ///
  /// In en, this message translates to:
  /// **'Delivery recorded for this stop.'**
  String get podDone;

  /// No description provided for @podScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan each crate: {done} of {total}'**
  String podScanTitle(int done, int total);

  /// No description provided for @podOtherStop.
  ///
  /// In en, this message translates to:
  /// **'Crate {code} is for another stop. Keep it on the truck.'**
  String podOtherStop(String code);

  /// No description provided for @podUnknownCrate.
  ///
  /// In en, this message translates to:
  /// **'{code} is not on this truck.'**
  String podUnknownCrate(String code);

  /// No description provided for @podNeedScan.
  ///
  /// In en, this message translates to:
  /// **'scan the crate'**
  String get podNeedScan;

  /// No description provided for @podWrongTag.
  ///
  /// In en, this message translates to:
  /// **'wrong crate'**
  String get podWrongTag;

  /// No description provided for @podNeedKg.
  ///
  /// In en, this message translates to:
  /// **'enter the accepted weight (less than the full weight)'**
  String get podNeedKg;

  /// No description provided for @podNeedReason.
  ///
  /// In en, this message translates to:
  /// **'enter a reason'**
  String get podNeedReason;

  /// No description provided for @podNeedReceiver.
  ///
  /// In en, this message translates to:
  /// **'Enter the receiver name'**
  String get podNeedReceiver;

  /// No description provided for @podNeedSignature.
  ///
  /// In en, this message translates to:
  /// **'Ask the receiver to sign'**
  String get podNeedSignature;

  /// No description provided for @podNeedPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take the delivery photo'**
  String get podNeedPhoto;

  /// No description provided for @reasonDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay on the road: a faster order of stops'**
  String get reasonDelay;

  /// No description provided for @reasonIncident.
  ///
  /// In en, this message translates to:
  /// **'Incident: the route changed to protect the cargo'**
  String get reasonIncident;

  /// No description provided for @reasonDiversion.
  ///
  /// In en, this message translates to:
  /// **'Diversion: deliver to a nearer buyer before the cargo spoils'**
  String get reasonDiversion;

  /// No description provided for @reasonRescue.
  ///
  /// In en, this message translates to:
  /// **'Rescue: hand the cargo to another truck'**
  String get reasonRescue;

  /// No description provided for @reasonManual.
  ///
  /// In en, this message translates to:
  /// **'The control tower changed the route'**
  String get reasonManual;

  /// No description provided for @rerouteTitle.
  ///
  /// In en, this message translates to:
  /// **'New route'**
  String get rerouteTitle;

  /// No description provided for @rerouteOld.
  ///
  /// In en, this message translates to:
  /// **'Was going to'**
  String get rerouteOld;

  /// No description provided for @rerouteNew.
  ///
  /// In en, this message translates to:
  /// **'Now go to'**
  String get rerouteNew;

  /// No description provided for @rerouteExtraKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km longer'**
  String rerouteExtraKm(String km);

  /// No description provided for @rerouteShorterKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km shorter'**
  String rerouteShorterKm(String km);

  /// No description provided for @rerouteMustAccept.
  ///
  /// In en, this message translates to:
  /// **'This route protects the cargo and must be accepted.'**
  String get rerouteMustAccept;

  /// No description provided for @rerouteWaiting.
  ///
  /// In en, this message translates to:
  /// **'A new route is waiting: tap to see'**
  String get rerouteWaiting;

  /// No description provided for @shelfLifeDays.
  ///
  /// In en, this message translates to:
  /// **'{days} d {hours} h left'**
  String shelfLifeDays(int days, int hours);

  /// No description provided for @shelfLifeHm.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min left'**
  String shelfLifeHm(int hours, int minutes);

  /// No description provided for @shelfLifeExpired.
  ///
  /// In en, this message translates to:
  /// **'Shelf life over'**
  String get shelfLifeExpired;

  /// No description provided for @shelfLifeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Shelf life not known yet'**
  String get shelfLifeUnknown;

  /// No description provided for @sos.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get sos;

  /// No description provided for @sosSent.
  ///
  /// In en, this message translates to:
  /// **'SOS sent'**
  String get sosSent;

  /// No description provided for @sosSentBody.
  ///
  /// In en, this message translates to:
  /// **'Your location goes to the control tower and your emergency contact. Stay safe; help is coming.'**
  String get sosSentBody;

  /// No description provided for @speedLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Driving'**
  String get speedLockTitle;

  /// No description provided for @speedLockBody.
  ///
  /// In en, this message translates to:
  /// **'Stop the truck to use this screen. Navigate and SOS still work.'**
  String get speedLockBody;

  /// No description provided for @startTrip.
  ///
  /// In en, this message translates to:
  /// **'Start trip'**
  String get startTrip;

  /// No description provided for @startNeedsPreCheck.
  ///
  /// In en, this message translates to:
  /// **'Do the pre-trip check first.'**
  String get startNeedsPreCheck;

  /// No description provided for @stopArriveHint.
  ///
  /// In en, this message translates to:
  /// **'Tap when the truck is at this stop.'**
  String get stopArriveHint;

  /// No description provided for @stopPickupHint.
  ///
  /// In en, this message translates to:
  /// **'Pickup stop: nothing to deliver here.'**
  String get stopPickupHint;

  /// No description provided for @stopNotFound.
  ///
  /// In en, this message translates to:
  /// **'This stop is no longer on the route.'**
  String get stopNotFound;

  /// No description provided for @stopPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get stopPickup;

  /// No description provided for @stopDrop.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get stopDrop;

  /// No description provided for @stopDiversion.
  ///
  /// In en, this message translates to:
  /// **'Diversion buyer'**
  String get stopDiversion;

  /// No description provided for @stopRescuePickup.
  ///
  /// In en, this message translates to:
  /// **'Rescue pickup'**
  String get stopRescuePickup;

  /// No description provided for @stopRescueDrop.
  ///
  /// In en, this message translates to:
  /// **'Hand over to rescue truck'**
  String get stopRescueDrop;

  /// No description provided for @stopColdStorage.
  ///
  /// In en, this message translates to:
  /// **'Cold storage'**
  String get stopColdStorage;

  /// No description provided for @stopEta.
  ///
  /// In en, this message translates to:
  /// **'ETA {time}'**
  String stopEta(String time);

  /// No description provided for @stopWindow.
  ///
  /// In en, this message translates to:
  /// **'Window {window}'**
  String stopWindow(String window);

  /// No description provided for @tripBatches.
  ///
  /// In en, this message translates to:
  /// **'Batches: {count}'**
  String tripBatches(int count);

  /// No description provided for @tripInProgress.
  ///
  /// In en, this message translates to:
  /// **'Trip {code} in progress'**
  String tripInProgress(String code);

  /// No description provided for @tripInProgressText.
  ///
  /// In en, this message translates to:
  /// **'Location is shared with the control tower'**
  String get tripInProgressText;

  /// No description provided for @tripStarts.
  ///
  /// In en, this message translates to:
  /// **'Starts {time}'**
  String tripStarts(String time);

  /// No description provided for @tripVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle {regNo}'**
  String tripVehicle(String regNo);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'mr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'mr':
      return AppLocalizationsMr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
