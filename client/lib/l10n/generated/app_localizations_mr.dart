// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class AppLocalizationsMr extends AppLocalizations {
  AppLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get languageName => 'मराठी';

  @override
  String get loading => 'लोड होत आहे…';

  @override
  String get loginTitle => 'साइन इन करा';

  @override
  String get loginSubtitlePhone =>
      'तुमच्या मॅनेजरने नोंदवलेला मोबाइल नंबर वापरा.';

  @override
  String get phoneLabel => 'मोबाइल नंबर';

  @override
  String get phoneHelper => 'आम्ही SMS ने 6 अंकी कोड पाठवू';

  @override
  String get sendCode => 'कोड पाठवा';

  @override
  String get language => 'भाषा';

  @override
  String get otpTitle => 'कोड टाका';

  @override
  String otpSentTo(String phone) {
    return 'कोड $phone वर पाठवला';
  }

  @override
  String get otpLabel => '6 अंकी कोड';

  @override
  String get verify => 'खात्री करा';

  @override
  String resendIn(int seconds) {
    return '$seconds सेकंदांनी पुन्हा पाठवा';
  }

  @override
  String get resendCode => 'कोड पुन्हा पाठवा';

  @override
  String get codeResent => 'नवीन कोड पाठवला जात आहे';

  @override
  String get changeNumber => 'नंबर बदला';

  @override
  String get continueWithGoogle => 'Google ने पुढे चला';

  @override
  String get orDivider => 'किंवा';

  @override
  String get emailLabel => 'ईमेल';

  @override
  String get passwordLabel => 'पासवर्ड';

  @override
  String get signIn => 'साइन इन करा';

  @override
  String get forgotPassword => 'पासवर्ड विसरलात?';

  @override
  String get usePhoneInstead => 'फोन OTP ने साइन इन करा';

  @override
  String get useEmailInstead => 'ईमेलने साइन इन करा';

  @override
  String get resetSent => 'या ईमेलचे खाते असल्यास, रीसेट लिंक पाठवली जात आहे.';

  @override
  String get verifyEmailTitle => 'तुमचा इनबॉक्स पाहा';

  @override
  String verifyEmailBody(String email) {
    return 'आम्ही $email वर खात्री लिंक पाठवली आहे. ती उघडा, मग पुन्हा साइन इन करा.';
  }

  @override
  String get resendEmail => 'ईमेल पुन्हा पाठवा';

  @override
  String get emailResent => 'ईमेल पुन्हा पाठवला';

  @override
  String get backToLogin => 'साइन इनवर परत जा';

  @override
  String get errorRequired => 'आवश्यक आहे';

  @override
  String get errorPhone => '10 अंकी मोबाइल नंबर टाका';

  @override
  String get errorOtp => '6 अंकी कोड टाका';

  @override
  String get errorEmail => 'योग्य ईमेल पत्ता टाका';

  @override
  String errorPasswordShort(int min) {
    return 'किमान $min अक्षरे';
  }

  @override
  String get errorNotANumber => 'संख्या टाका';

  @override
  String errorBelowMin(String min) {
    return 'किमान $min असावे';
  }

  @override
  String errorAboveMax(String max) {
    return 'जास्तीत जास्त $max असावे';
  }

  @override
  String get authInvalidCredentials => 'ईमेल किंवा पासवर्ड चुकीचा आहे.';

  @override
  String get authEmailNotConfirmed =>
      'आधी तुमचा ईमेल खात्री करा. इनबॉक्स पाहा.';

  @override
  String get authOtpInvalid =>
      'हा कोड बरोबर नाही. SMS पाहून पुन्हा प्रयत्न करा.';

  @override
  String get authOtpExpired => 'कोडची मुदत संपली. नवीन कोड मागवा.';

  @override
  String get authRateLimited =>
      'खूप प्रयत्न झाले. काही मिनिटे थांबून पुन्हा प्रयत्न करा.';

  @override
  String get authNotRegistered =>
      'हा नंबर किंवा ईमेल नोंदवलेला नाही. तुमच्या मॅनेजरशी बोला.';

  @override
  String get authNetwork => 'इंटरनेट नाही. कनेक्शन तपासून पुन्हा प्रयत्न करा.';

  @override
  String get authNotConfigured => 'या बिल्डमध्ये साइन इन सेट केलेले नाही.';

  @override
  String get authCancelled => 'साइन इन रद्द केले.';

  @override
  String get authUnknown => 'साइन इन झाले नाही. पुन्हा प्रयत्न करा.';

  @override
  String get reasonWrongApp =>
      'तुमचे खाते हे ॲप वापरू शकत नाही. तुमच्या भूमिकेचे ॲप वापरा.';

  @override
  String get reasonNotRegistered =>
      'तुमचे खाते सक्रिय नाही. तुमच्या मॅनेजरशी बोला.';

  @override
  String get reasonOtherDevice =>
      'तुम्ही दुसऱ्या फोनवर लॉग इन केले, म्हणून हा फोन साइन आउट झाला.';

  @override
  String get reasonUnauthorized => 'तुमचे सत्र संपले. पुन्हा साइन इन करा.';

  @override
  String reasonGeneric(String code) {
    return 'साइन इन झाले नाही ($code). पुन्हा प्रयत्न करा.';
  }

  @override
  String get settingsTitle => 'सेटिंग्ज';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get themeSystem => 'फोनप्रमाणे';

  @override
  String get themeLight => 'फिकट';

  @override
  String get themeDark => 'गडद';

  @override
  String get settingsSync => 'सिंक';

  @override
  String syncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बदल सिंक व्हायचे आहेत',
      one: '1 बदल सिंक व्हायचा आहे',
      zero: 'सर्व काही सिंक झाले आहे',
    );
    return '$_temp0';
  }

  @override
  String get openSyncQueue => 'सिंक रांग उघडा';

  @override
  String get settingsAbout => 'ॲपबद्दल';

  @override
  String aboutVersion(String version, String code) {
    return 'आवृत्ती $version (बिल्ड $code)';
  }

  @override
  String get signOut => 'साइन आउट';

  @override
  String get signOutConfirm => 'या फोनवरून साइन आउट करायचे?';

  @override
  String signOutPendingWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count बदल अजून सिंक झालेले नाहीत. ते याच फोनवर राहतील आणि पुन्हा साइन इन केल्यावर सिंक होतील.',
      one:
          '1 बदल अजून सिंक झालेला नाही. तो याच फोनवर राहील आणि पुन्हा साइन इन केल्यावर सिंक होईल.',
    );
    return '$_temp0';
  }

  @override
  String get cancel => 'रद्द करा';

  @override
  String get syncQueueTitle => 'सिंक रांग';

  @override
  String get syncNow => 'आता सिंक करा';

  @override
  String get syncNeedsAttention => 'लक्ष देणे आवश्यक';

  @override
  String get syncWaiting => 'सिंकची वाट';

  @override
  String syncNextTry(String time) {
    return 'पुढचा प्रयत्न $time वाजता';
  }

  @override
  String get syncFiles => 'अपलोड व्हायच्या फाइल्स';

  @override
  String get syncEmpty => 'काहीही बाकी नाही. तुमचे सर्व बदल सर्व्हरवर आहेत.';

  @override
  String get retry => 'पुन्हा प्रयत्न करा';

  @override
  String get discard => 'काढून टाका';

  @override
  String get discardConfirm =>
      'हा बदल काढून टाकायचा? सर्व्हरने तो नाकारला आहे आणि तो हरवेल.';

  @override
  String get offlineBanner => 'ऑफलाइन. तुमचे बदल जतन आहेत आणि नंतर सिंक होतील.';

  @override
  String get updatedJustNow => 'आत्ताच अपडेट झाले';

  @override
  String updatedAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes मिनिटांपूर्वी अपडेट झाले',
      one: '1 मिनिटापूर्वी अपडेट झाले',
    );
    return '$_temp0';
  }

  @override
  String get errorTitle => 'काहीतरी चुकले';

  @override
  String get emptyTitle => 'इथे अजून काही नाही';

  @override
  String homeWelcome(String name) {
    return 'नमस्कार, $name';
  }

  @override
  String get homeComingSoon => 'या ॲपच्या स्क्रीन पुढच्या रिलीजमध्ये येतील.';

  @override
  String get updateRequiredTitle => 'अपडेट आवश्यक आहे';

  @override
  String get updateRequiredBody =>
      'ही आवृत्ती आता चालत नाही. पुढे जाण्यासाठी नवीन आवृत्ती इंस्टॉल करा.';

  @override
  String get statusSafe => 'सुरक्षित';

  @override
  String get statusWatch => 'सावध';

  @override
  String get statusCritical => 'गंभीर';

  @override
  String get statusInfo => 'माहिती';

  @override
  String get voiceInput => 'मूल्य बोला';
}
