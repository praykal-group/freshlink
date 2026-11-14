// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get languageName => 'हिन्दी';

  @override
  String get loading => 'लोड हो रहा है…';

  @override
  String get loginTitle => 'साइन इन करें';

  @override
  String get loginSubtitlePhone =>
      'वही मोबाइल नंबर डालें जो आपके मैनेजर ने दर्ज किया है।';

  @override
  String get phoneLabel => 'मोबाइल नंबर';

  @override
  String get phoneHelper => 'हम SMS से 6 अंकों का कोड भेजेंगे';

  @override
  String get sendCode => 'कोड भेजें';

  @override
  String get language => 'भाषा';

  @override
  String get otpTitle => 'कोड डालें';

  @override
  String otpSentTo(String phone) {
    return 'कोड $phone पर भेजा गया';
  }

  @override
  String get otpLabel => '6 अंकों का कोड';

  @override
  String get verify => 'पुष्टि करें';

  @override
  String resendIn(int seconds) {
    return '$seconds सेकंड में फिर भेजें';
  }

  @override
  String get resendCode => 'कोड फिर भेजें';

  @override
  String get codeResent => 'नया कोड भेजा जा रहा है';

  @override
  String get changeNumber => 'नंबर बदलें';

  @override
  String get continueWithGoogle => 'Google से जारी रखें';

  @override
  String get orDivider => 'या';

  @override
  String get emailLabel => 'ईमेल';

  @override
  String get passwordLabel => 'पासवर्ड';

  @override
  String get signIn => 'साइन इन करें';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get usePhoneInstead => 'फ़ोन OTP से साइन इन करें';

  @override
  String get useEmailInstead => 'ईमेल से साइन इन करें';

  @override
  String get resetSent =>
      'अगर इस ईमेल का खाता है, तो रीसेट लिंक भेजा जा रहा है।';

  @override
  String get verifyEmailTitle => 'अपना इनबॉक्स देखें';

  @override
  String verifyEmailBody(String email) {
    return 'हमने $email पर पुष्टि लिंक भेजा है। उसे खोलें, फिर दोबारा साइन इन करें।';
  }

  @override
  String get resendEmail => 'ईमेल फिर भेजें';

  @override
  String get emailResent => 'ईमेल फिर भेज दिया गया';

  @override
  String get backToLogin => 'साइन इन पर वापस जाएँ';

  @override
  String get errorRequired => 'ज़रूरी है';

  @override
  String get errorPhone => '10 अंकों का मोबाइल नंबर डालें';

  @override
  String get errorOtp => '6 अंकों का कोड डालें';

  @override
  String get errorEmail => 'सही ईमेल पता डालें';

  @override
  String errorPasswordShort(int min) {
    return 'कम से कम $min अक्षर';
  }

  @override
  String get errorNotANumber => 'संख्या डालें';

  @override
  String errorBelowMin(String min) {
    return 'कम से कम $min होना चाहिए';
  }

  @override
  String errorAboveMax(String max) {
    return 'ज़्यादा से ज़्यादा $max होना चाहिए';
  }

  @override
  String get authInvalidCredentials => 'ईमेल या पासवर्ड गलत है।';

  @override
  String get authEmailNotConfirmed =>
      'पहले अपना ईमेल पुष्टि करें। इनबॉक्स देखें।';

  @override
  String get authOtpInvalid => 'यह कोड सही नहीं है। SMS देखकर फिर कोशिश करें।';

  @override
  String get authOtpExpired => 'कोड की समय सीमा खत्म हो गई। नया कोड मँगाएँ।';

  @override
  String get authRateLimited =>
      'बहुत ज़्यादा कोशिशें। कुछ मिनट रुककर फिर कोशिश करें।';

  @override
  String get authNotRegistered =>
      'यह नंबर या ईमेल दर्ज नहीं है। अपने मैनेजर से संपर्क करें।';

  @override
  String get authNetwork => 'इंटरनेट नहीं है। कनेक्शन जाँचकर फिर कोशिश करें।';

  @override
  String get authNotConfigured => 'इस बिल्ड में साइन इन सेट नहीं है।';

  @override
  String get authCancelled => 'साइन इन रद्द किया गया।';

  @override
  String get authUnknown => 'साइन इन नहीं हो सका। फिर कोशिश करें।';

  @override
  String get reasonWrongApp =>
      'आपका खाता यह ऐप इस्तेमाल नहीं कर सकता। अपनी भूमिका वाला ऐप इस्तेमाल करें।';

  @override
  String get reasonNotRegistered =>
      'आपका खाता सक्रिय नहीं है। अपने मैनेजर से संपर्क करें।';

  @override
  String get reasonOtherDevice =>
      'आपने दूसरे फ़ोन पर लॉग इन किया, इसलिए यह फ़ोन साइन आउट हो गया।';

  @override
  String get reasonUnauthorized =>
      'आपका सत्र खत्म हो गया। दोबारा साइन इन करें।';

  @override
  String reasonGeneric(String code) {
    return 'साइन इन नहीं हो सका ($code)। फिर कोशिश करें।';
  }

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get themeSystem => 'फ़ोन जैसा';

  @override
  String get themeLight => 'हल्की';

  @override
  String get themeDark => 'गहरी';

  @override
  String get settingsSync => 'सिंक';

  @override
  String syncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बदलाव सिंक होना बाकी हैं',
      one: '1 बदलाव सिंक होना बाकी है',
      zero: 'सब कुछ सिंक हो गया है',
    );
    return '$_temp0';
  }

  @override
  String get openSyncQueue => 'सिंक कतार खोलें';

  @override
  String get settingsAbout => 'ऐप के बारे में';

  @override
  String aboutVersion(String version, String code) {
    return 'संस्करण $version (बिल्ड $code)';
  }

  @override
  String get signOut => 'साइन आउट';

  @override
  String get signOutConfirm => 'इस फ़ोन से साइन आउट करें?';

  @override
  String signOutPendingWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count बदलाव अभी सिंक नहीं हुए हैं। वे इसी फ़ोन पर रहेंगे और दोबारा साइन इन करने पर सिंक होंगे।',
      one:
          '1 बदलाव अभी सिंक नहीं हुआ है। वह इसी फ़ोन पर रहेगा और दोबारा साइन इन करने पर सिंक होगा।',
    );
    return '$_temp0';
  }

  @override
  String get cancel => 'रद्द करें';

  @override
  String get syncQueueTitle => 'सिंक कतार';

  @override
  String get syncNow => 'अभी सिंक करें';

  @override
  String get syncNeedsAttention => 'ध्यान देना ज़रूरी';

  @override
  String get syncWaiting => 'सिंक का इंतज़ार';

  @override
  String syncNextTry(String time) {
    return 'अगली कोशिश $time पर';
  }

  @override
  String get syncFiles => 'अपलोड होने वाली फ़ाइलें';

  @override
  String get syncEmpty => 'कुछ बाकी नहीं है। आपके सभी बदलाव सर्वर पर हैं।';

  @override
  String get retry => 'फिर कोशिश करें';

  @override
  String get discard => 'हटाएँ';

  @override
  String get discardConfirm =>
      'यह बदलाव हटाएँ? सर्वर ने इसे अस्वीकार किया है और यह खो जाएगा।';

  @override
  String get offlineBanner =>
      'ऑफ़लाइन। आपके बदलाव सुरक्षित हैं और बाद में सिंक होंगे।';

  @override
  String get updatedJustNow => 'अभी अपडेट हुआ';

  @override
  String updatedAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes मिनट पहले अपडेट हुआ',
      one: '1 मिनट पहले अपडेट हुआ',
    );
    return '$_temp0';
  }

  @override
  String get errorTitle => 'कुछ गड़बड़ हो गई';

  @override
  String get emptyTitle => 'अभी यहाँ कुछ नहीं है';

  @override
  String homeWelcome(String name) {
    return 'नमस्ते, $name';
  }

  @override
  String get homeComingSoon => 'इस ऐप की स्क्रीन अगली रिलीज़ में आएँगी।';

  @override
  String get updateRequiredTitle => 'अपडेट ज़रूरी है';

  @override
  String get updateRequiredBody =>
      'यह संस्करण अब समर्थित नहीं है। जारी रखने के लिए नया संस्करण इंस्टॉल करें।';

  @override
  String get statusSafe => 'सुरक्षित';

  @override
  String get statusWatch => 'सावधान';

  @override
  String get statusCritical => 'गंभीर';

  @override
  String get statusInfo => 'जानकारी';

  @override
  String get voiceInput => 'मान बोलें';
}
