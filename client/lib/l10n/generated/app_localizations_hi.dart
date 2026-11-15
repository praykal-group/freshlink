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

  @override
  String get ok => 'ठीक है';

  @override
  String get close => 'बंद करें';

  @override
  String get next => 'आगे';

  @override
  String get back => 'पीछे';

  @override
  String get skip => 'छोड़ें';

  @override
  String get send => 'भेजें';

  @override
  String get saved => 'सहेजा गया';

  @override
  String todayAtSite(String site) {
    return 'आज $site पर';
  }

  @override
  String get countRegistered => 'दर्ज';

  @override
  String get countGraded => 'ग्रेड हुए';

  @override
  String get countStored => 'भंडारण में';

  @override
  String get countDispatched => 'भेजे गए';

  @override
  String get newFishBatch => 'नया मछली बैच';

  @override
  String get newProduceBatch => 'नया फल-सब्ज़ी बैच';

  @override
  String get receive => 'प्राप्त करें';

  @override
  String get loadTruck => 'ट्रक लोड करें';

  @override
  String get batches => 'बैच';

  @override
  String get printer => 'प्रिंटर';

  @override
  String get resumeDraft => 'शुरू किया गया बैच पूरा करें';

  @override
  String get discardDraft => 'हटाएँ';

  @override
  String get stepForm => 'विवरण';

  @override
  String get stepTag => 'टैग';

  @override
  String get stepPhotos => 'फ़ोटो';

  @override
  String get stepGrade => 'ग्रेड';

  @override
  String get stepStorage => 'भंडारण';

  @override
  String get stepLabel => 'लेबल';

  @override
  String get stepDone => 'पूरा';

  @override
  String stepOf(int n, int total) {
    return 'चरण $n / $total';
  }

  @override
  String get product => 'उत्पाद';

  @override
  String get catchTime => 'पकड़ने का समय';

  @override
  String get harvestTime => 'कटाई का समय';

  @override
  String get weight => 'वज़न';

  @override
  String get vesselId => 'नाव संख्या';

  @override
  String get farmRef => 'खेत संख्या';

  @override
  String get iceRatio => 'बर्फ़-मछली अनुपात';

  @override
  String get coreTemp => 'अंदर का तापमान';

  @override
  String get maturity => 'पकने का स्तर';

  @override
  String get brix => 'ब्रिक्स';

  @override
  String get fieldTemp => 'खेत का तापमान';

  @override
  String get fieldHumidity => 'खेत की नमी';

  @override
  String get listening => 'सुन रहे हैं… संख्या बोलें';

  @override
  String get voiceNotHeard => 'संख्या सुनाई नहीं दी। फिर बोलें या लिखें।';

  @override
  String get mastersMissing =>
      'मास्टर सूचियाँ अभी डाउनलोड नहीं हुईं। एक बार इंटरनेट से जुड़ें।';

  @override
  String get tagChoose => 'क्रेट पर टैग लगाएँ';

  @override
  String get tagNfc => 'NFC टैग छुआएँ';

  @override
  String get tagQr => 'QR स्कैन करें';

  @override
  String get tagWedge => 'RFID रीडर';

  @override
  String tagRead(String uid) {
    return 'टैग $uid';
  }

  @override
  String get tagInvalid => 'यह सही टैग नहीं है';

  @override
  String get tagWedgeTitle => 'RFID रीडर से स्कैन करें';

  @override
  String get tagWedgeHelp =>
      'रीडर का बटन दबाएँ, या टैग नंबर लिखकर Enter दबाएँ।';

  @override
  String get nfcHold => 'टैग को फ़ोन के पीछे लगाएँ';

  @override
  String get nfcUnavailable =>
      'NFC बंद है या उपलब्ध नहीं। QR या RFID रीडर इस्तेमाल करें।';

  @override
  String get scanQr => 'QR स्कैन करें';

  @override
  String get scanQrHelp => 'कैमरे को QR कोड की ओर करें';

  @override
  String get photoTop => 'ऊपर से';

  @override
  String get photoSide => 'बगल से';

  @override
  String get photoCloseup => 'पास से';

  @override
  String get photoHelpTop => 'ऊपर से: पूरा क्रेट फ़्रेम में';

  @override
  String get photoHelpSide => 'बगल से: क्रेट की गहराई दिखाएँ';

  @override
  String get photoHelpCloseup => 'पास से: एक मछली या फल पूरे फ़्रेम में';

  @override
  String get retake => 'फिर लें';

  @override
  String get photosNeeded => 'तीनों फ़ोटो लें';

  @override
  String get cameraUnavailable => 'कैमरा उपलब्ध नहीं है';

  @override
  String get gradeWaiting => 'ग्रेड हो रहा है…';

  @override
  String get gradeQueued =>
      'ग्रेडिंग कतार में है। फ़ोन ऑनलाइन होने पर ग्रेड मिलेगा।';

  @override
  String get gradeUnavailable => 'अभी ग्रेडिंग उपलब्ध नहीं है। यह कतार में है।';

  @override
  String gradeResult(String grade) {
    return 'ग्रेड $grade';
  }

  @override
  String confidence(int pct) {
    return 'भरोसा $pct%';
  }

  @override
  String get defects => 'खराबियाँ';

  @override
  String get noDefects => 'कोई खराबी नहीं मिली';

  @override
  String get dispute => 'आपत्ति';

  @override
  String get disputeReason => 'ग्रेड गलत क्यों है?';

  @override
  String get disputeSent => 'आपत्ति मैनेजर को भेजी गई';

  @override
  String get pathBlastChiller => 'ब्लास्ट चिलर';

  @override
  String get pathRipening => 'पकाने का कक्ष';

  @override
  String get pathColdRoom => 'कोल्ड रूम';

  @override
  String get sellFirst => 'पहले बेचें';

  @override
  String recommendedUnit(String unit, String free) {
    return 'सुझाव: $unit ($free किलो खाली)';
  }

  @override
  String get noUnit => 'इस साइट पर कोई सही यूनिट खाली नहीं है';

  @override
  String get assign => 'सौंपें';

  @override
  String assigned(String unit) {
    return '$unit में रखा गया';
  }

  @override
  String get storageOffline =>
      'यह फ़ोन की सूची से दिखाया गया है। ऑनलाइन होने पर सौंपें।';

  @override
  String get print => 'प्रिंट करें';

  @override
  String get shareImage => 'फ़ोटो भेजें';

  @override
  String get labelOffline => 'बैच सिंक होने के बाद लेबल तैयार होगा।';

  @override
  String get noPrinter => 'कोई प्रिंटर सेट नहीं है';

  @override
  String get printed => 'लेबल प्रिंटर को भेजा गया';

  @override
  String get printFailed => 'प्रिंट नहीं हुआ। लेबल को फ़ोटो की तरह भेजें।';

  @override
  String get doneTitle => 'बैच दर्ज हो गया';

  @override
  String doneTime(int seconds) {
    return '$seconds सेकंड में पूरा';
  }

  @override
  String get newBatch => 'नया बैच';

  @override
  String get goHome => 'होम';

  @override
  String get pendingSync => 'अभी सिंक नहीं हुआ';

  @override
  String get searchBatches => 'कोड या टैग खोजें';

  @override
  String get all => 'सभी';

  @override
  String get stRegistered => 'दर्ज';

  @override
  String get stGraded => 'ग्रेड हुआ';

  @override
  String get stStored => 'रखा गया';

  @override
  String get stAllocated => 'आवंटित';

  @override
  String get stLoaded => 'लोड हुआ';

  @override
  String get stInTransit => 'रास्ते में';

  @override
  String get stDiverted => 'मोड़ा गया';

  @override
  String get stDelivered => 'पहुँचाया';

  @override
  String get stPartial => 'आंशिक पहुँचा';

  @override
  String get stRejected => 'अस्वीकृत';

  @override
  String get stSpoiled => 'ख़राब';

  @override
  String shelfLifeHours(String hours) {
    return 'शेल्फ़ लाइफ़ $hours घंटे';
  }

  @override
  String get history => 'इतिहास';

  @override
  String get chainVerified => 'रिकॉर्ड शृंखला सत्यापित';

  @override
  String get chainBroken => 'रिकॉर्ड शृंखला सत्यापित नहीं';

  @override
  String get edit => 'बदलें';

  @override
  String get requestEdit => 'बदलाव का अनुरोध';

  @override
  String editMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'बदलने के लिए $minutes मिनट बाकी',
      one: 'बदलने के लिए 1 मिनट बाकी',
    );
    return '$_temp0';
  }

  @override
  String get editClosed => '30 मिनट का समय खत्म हो गया। मैनेजर से अनुरोध करें।';

  @override
  String get reason => 'कारण';

  @override
  String get requestSent => 'अनुरोध मैनेजर को भेजा गया';

  @override
  String get printLabel => 'लेबल प्रिंट करें';

  @override
  String get tags => 'टैग';

  @override
  String get onlineOnly => 'इसके लिए इंटरनेट ज़रूरी है।';

  @override
  String get scanBatch => 'बैच स्कैन करें';

  @override
  String notFound(String value) {
    return '$value का कोई बैच नहीं मिला';
  }

  @override
  String get condition => 'हालत';

  @override
  String get condGood => 'अच्छी';

  @override
  String get condFair => 'ठीक';

  @override
  String get condPoor => 'ख़राब';

  @override
  String get damagePhotos => 'नुकसान की फ़ोटो';

  @override
  String get addPhoto => 'फ़ोटो जोड़ें';

  @override
  String get outcome => 'नतीजा';

  @override
  String get accept => 'स्वीकार';

  @override
  String get partial => 'आंशिक';

  @override
  String get reject => 'अस्वीकार';

  @override
  String get acceptedWeight => 'स्वीकार वज़न';

  @override
  String get submit => 'जमा करें';

  @override
  String get receiveSaved => 'प्राप्ति सहेजी गई। ऑनलाइन होने पर सिंक होगी।';

  @override
  String get noTrips => 'आज लोड करने के लिए कोई ट्रिप नहीं';

  @override
  String loadedCount(int n, int total) {
    return '$total में से $n लोड';
  }

  @override
  String wrongBatch(String code) {
    return 'यह इस ट्रिप का नहीं: $code';
  }

  @override
  String get alreadyScanned => 'पहले ही स्कैन हुआ';

  @override
  String get confirmLoad => 'लोडिंग पक्की करें';

  @override
  String get loadSaved => 'लोडिंग सहेजी गई। ऑनलाइन होने पर सिंक होगी।';

  @override
  String get scanNext => 'अगला क्रेट स्कैन करें';

  @override
  String get pairedPrinters => 'जुड़े हुए प्रिंटर';

  @override
  String get noPairedPrinters =>
      'कोई प्रिंटर नहीं जुड़ा। पहले फ़ोन की ब्लूटूथ सेटिंग में प्रिंटर जोड़ें।';

  @override
  String get testPrint => 'टेस्ट प्रिंट';

  @override
  String get selectedPrinter => 'चुना गया';

  @override
  String get bluetoothOff => 'ब्लूटूथ बंद है। प्रिंट के लिए चालू करें।';

  @override
  String get acceptReroute => 'नया रास्ता स्वीकार करें';

  @override
  String get declineReroute => 'मौजूदा रास्ता रखें';

  @override
  String get acknowledge => 'स्वीकार करें';

  @override
  String get alertTemp => 'तापमान सीमा से बाहर';

  @override
  String get alertTempDo =>
      'रीफर चालू है और सेटपॉइंट सही है, जाँचें। दरवाज़े बंद रखें।';

  @override
  String get alertDriverFix => 'तापमान धीरे-धीरे बढ़ रहा है';

  @override
  String get alertDriverFixDo =>
      'दरवाज़े की सील, रीफर सेटपॉइंट और हवा का रास्ता जाँचें। 15 मिनट में फिर जाँच होगी।';

  @override
  String get alertSpoilage => 'माल खराब होने का खतरा';

  @override
  String get alertSpoilageDo =>
      'कंट्रोल टावर से नए रास्ते का इंतज़ार करें और उसे स्वीकार करें।';

  @override
  String get alertHumidity => 'नमी सीमा से बाहर';

  @override
  String get alertHumidityDo => 'दरवाज़े और रीफर जाँचें।';

  @override
  String get alertEthylene => 'एथिलीन ज़्यादा';

  @override
  String get alertEthyleneDo =>
      'सुरक्षित हो तो हवा आने दें और कंट्रोल टावर को बताएँ।';

  @override
  String get alertShock => 'तेज़ झटका दर्ज हुआ';

  @override
  String get alertShockDo => 'सुरक्षित जगह रुककर माल जाँचें।';

  @override
  String get alertDevice => 'सेंसर बंद';

  @override
  String get alertDeviceDo => 'सेंसर पॉड की बिजली और केबल जाँचें।';

  @override
  String get alertGeneric => 'माल चेतावनी';

  @override
  String get alertGenericDo => 'संदेश पढ़ें और कंट्रोल टावर के निर्देश मानें।';

  @override
  String get allStopsDone => 'सभी स्टॉप पूरे। डिपो लौटें।';

  @override
  String get allUploaded => 'सब अपलोड हो गया';

  @override
  String pendingUploads(int count) {
    return '$count चीज़ें अपलोड होने को बाकी';
  }

  @override
  String get arrived => 'मैं पहुँच गया';

  @override
  String get deliverHere => 'यहाँ डिलीवरी करें';

  @override
  String get cargoStatus => 'माल';

  @override
  String get cargoTemp => 'तापमान';

  @override
  String get cargoHumidity => 'नमी';

  @override
  String cargoLowestShelfLife(String value) {
    return 'सबसे कम शेल्फ लाइफ: $value';
  }

  @override
  String cargoAsOf(String time) {
    return 'आखिरी अपडेट $time (ऑफ़लाइन)';
  }

  @override
  String get cargoEmpty => 'गाड़ी में माल नहीं';

  @override
  String cargoSafeRange(String min, String max) {
    return 'सुरक्षित $min से $max °C';
  }

  @override
  String get clear => 'मिटाएँ';

  @override
  String get gpsOff => 'लोकेशन बंद है। ट्रिप शुरू करने के लिए चालू करें।';

  @override
  String get gpsDenied => 'ट्रिप ट्रैक करने के लिए लोकेशन की अनुमति चाहिए।';

  @override
  String get gpsDeniedForever =>
      'लोकेशन की अनुमति बंद है। सेटिंग्स में चालू करें।';

  @override
  String get gpsFailed => 'ट्रिप ट्रैकिंग शुरू नहीं हुई। फिर कोशिश करें।';

  @override
  String get notificationsDenied =>
      'सूचनाएँ चालू करें ताकि दिखे कि ट्रिप ट्रैक हो रही है।';

  @override
  String get openSettings => 'सेटिंग्स खोलें';

  @override
  String historyPods(int count) {
    return 'दर्ज डिलीवरी: $count';
  }

  @override
  String get noHistory => 'अभी कोई ट्रिप नहीं';

  @override
  String get tripHistory => 'ट्रिप इतिहास';

  @override
  String get incDelay => 'देरी';

  @override
  String get incBreakdown => 'गाड़ी खराब';

  @override
  String get incAccident => 'दुर्घटना';

  @override
  String get incRoadblock => 'रास्ता बंद';

  @override
  String get incReeferFault => 'रीफर खराब';

  @override
  String get incPhoto => 'फ़ोटो जोड़ें';

  @override
  String get incPhotoDone => 'फ़ोटो जुड़ गई';

  @override
  String get incPhotoHint => 'समस्या दिखाएँ';

  @override
  String get incVoice => 'आवाज़ संदेश';

  @override
  String incVoiceDone(int seconds) {
    return 'आवाज़ संदेश $seconds सेकंड';
  }

  @override
  String incVoiceStop(int seconds) {
    return 'रोकें ($seconds सेकंड बाकी)';
  }

  @override
  String get incSend => 'रिपोर्ट भेजें';

  @override
  String get incSent => 'रिपोर्ट सेव हुई। नेटवर्क मिलते ही भेजी जाएगी।';

  @override
  String get incQueuedHint => 'बिना नेटवर्क भी चलता है: बाद में भेजा जाता है।';

  @override
  String get reportIncident => 'घटना बताएँ';

  @override
  String get micDenied => 'आवाज़ संदेश के लिए माइक की अनुमति चाहिए।';

  @override
  String get navigate => 'रास्ता दिखाएँ';

  @override
  String get nextStop => 'अगला स्टॉप';

  @override
  String get noTripToday => 'आज कोई ट्रिप नहीं';

  @override
  String get noTripTodayHint => 'फिर जाँचने के लिए नीचे खींचें।';

  @override
  String openAlerts(int count) {
    return '$count खुली चेतावनियाँ: देखने के लिए दबाएँ';
  }

  @override
  String get openTrip => 'ट्रिप खोलें';

  @override
  String get preCheck => 'ट्रिप से पहले जाँच';

  @override
  String get preCheckAgain => 'फिर से जाँचें';

  @override
  String get pcReeferOn => 'रीफर चालू है';

  @override
  String get pcSetpointChecked => 'सेट तापमान जाँचा';

  @override
  String get pcDoorsClosed => 'दरवाज़े बंद हैं';

  @override
  String get pcSetpoint => 'रीफर सेट तापमान';

  @override
  String get pcSubmit => 'जाँच सेव करें';

  @override
  String get pcAllNeeded => 'आगे बढ़ने के लिए तीनों जाँच चालू करें।';

  @override
  String get pcFailed => 'जाँच असफल';

  @override
  String get pcReeferOff => 'रीफर बंद है';

  @override
  String get pcDoorsOpen => 'दरवाज़ा खुला है';

  @override
  String get pcSetpointOut => 'यह सेट तापमान इस माल के लिए गलत है';

  @override
  String get pcIncompatible =>
      'ये उत्पाद साथ नहीं जा सकते। कंट्रोल टावर को कॉल करें।';

  @override
  String pcAllowedRange(String min, String max) {
    return 'मान्य: $min से $max °C';
  }

  @override
  String get podAccepted => 'स्वीकार';

  @override
  String get podPartial => 'आंशिक';

  @override
  String get podRejected => 'अस्वीकार';

  @override
  String get podAcceptedKg => 'स्वीकृत वज़न';

  @override
  String podBatchWeight(String kg) {
    return 'वज़न $kg किलो';
  }

  @override
  String get podReason => 'कारण';

  @override
  String get podReceiver => 'प्राप्तकर्ता का नाम';

  @override
  String get podSignature => 'प्राप्तकर्ता के हस्ताक्षर';

  @override
  String get podPhoto => 'डिलीवरी की फ़ोटो';

  @override
  String get podPhotoDone => 'फ़ोटो ली गई';

  @override
  String get podPhotoHint => 'प्राप्तकर्ता के पास क्रेट दिखाएँ';

  @override
  String get podSubmit => 'डिलीवरी जमा करें';

  @override
  String get podSaved => 'डिलीवरी सेव हुई। नेटवर्क मिलते ही भेजी जाएगी।';

  @override
  String get podDone => 'इस स्टॉप की डिलीवरी दर्ज है।';

  @override
  String podScanTitle(int done, int total) {
    return 'हर क्रेट स्कैन करें: $total में से $done';
  }

  @override
  String podOtherStop(String code) {
    return 'क्रेट $code दूसरे स्टॉप का है। गाड़ी में रखें।';
  }

  @override
  String podUnknownCrate(String code) {
    return '$code इस गाड़ी में नहीं है।';
  }

  @override
  String get podNeedScan => 'क्रेट स्कैन करें';

  @override
  String get podWrongTag => 'गलत क्रेट';

  @override
  String get podNeedKg => 'स्वीकृत वज़न डालें (पूरे वज़न से कम)';

  @override
  String get podNeedReason => 'कारण लिखें';

  @override
  String get podNeedReceiver => 'प्राप्तकर्ता का नाम डालें';

  @override
  String get podNeedSignature => 'प्राप्तकर्ता से हस्ताक्षर करवाएँ';

  @override
  String get podNeedPhoto => 'डिलीवरी की फ़ोटो लें';

  @override
  String get reasonDelay => 'रास्ते में देरी: स्टॉप का तेज़ क्रम';

  @override
  String get reasonIncident => 'घटना: माल बचाने के लिए रास्ता बदला';

  @override
  String get reasonDiversion =>
      'मोड़: माल खराब होने से पहले पास के खरीदार को दें';

  @override
  String get reasonRescue => 'बचाव: माल दूसरी गाड़ी को दें';

  @override
  String get reasonManual => 'कंट्रोल टावर ने रास्ता बदला';

  @override
  String get rerouteTitle => 'नया रास्ता';

  @override
  String get rerouteOld => 'पहले जा रहे थे';

  @override
  String get rerouteNew => 'अब जाएँ';

  @override
  String rerouteExtraKm(String km) {
    return '$km किमी ज़्यादा';
  }

  @override
  String rerouteShorterKm(String km) {
    return '$km किमी कम';
  }

  @override
  String get rerouteMustAccept =>
      'यह रास्ता माल को बचाता है और स्वीकार करना ज़रूरी है।';

  @override
  String get rerouteWaiting => 'नया रास्ता इंतज़ार में: देखने के लिए दबाएँ';

  @override
  String shelfLifeDays(int days, int hours) {
    return '$days दिन $hours घंटे बाकी';
  }

  @override
  String shelfLifeHm(int hours, int minutes) {
    return '$hours घंटे $minutes मिनट बाकी';
  }

  @override
  String get shelfLifeExpired => 'शेल्फ लाइफ खत्म';

  @override
  String get shelfLifeUnknown => 'शेल्फ लाइफ अभी पता नहीं';

  @override
  String get sos => 'SOS';

  @override
  String get sosSent => 'SOS भेजा गया';

  @override
  String get sosSentBody =>
      'आपकी लोकेशन कंट्रोल टावर और आपातकालीन संपर्क को जाती है। सुरक्षित रहें; मदद आ रही है।';

  @override
  String get speedLockTitle => 'गाड़ी चल रही है';

  @override
  String get speedLockBody =>
      'यह स्क्रीन इस्तेमाल करने के लिए गाड़ी रोकें। रास्ता और SOS चलते रहेंगे।';

  @override
  String get startTrip => 'ट्रिप शुरू करें';

  @override
  String get startNeedsPreCheck => 'पहले ट्रिप से पहले की जाँच करें।';

  @override
  String get stopArriveHint => 'गाड़ी इस स्टॉप पर पहुँचे तब दबाएँ।';

  @override
  String get stopPickupHint => 'पिकअप स्टॉप: यहाँ कुछ देना नहीं है।';

  @override
  String get stopNotFound => 'यह स्टॉप अब रास्ते में नहीं है।';

  @override
  String get stopPickup => 'पिकअप';

  @override
  String get stopDrop => 'डिलीवरी';

  @override
  String get stopDiversion => 'मोड़ खरीदार';

  @override
  String get stopRescuePickup => 'बचाव पिकअप';

  @override
  String get stopRescueDrop => 'बचाव गाड़ी को सौंपें';

  @override
  String get stopColdStorage => 'कोल्ड स्टोरेज';

  @override
  String stopEta(String time) {
    return 'पहुँच $time';
  }

  @override
  String stopWindow(String window) {
    return 'समय $window';
  }

  @override
  String tripBatches(int count) {
    return 'बैच: $count';
  }

  @override
  String tripInProgress(String code) {
    return 'ट्रिप $code चल रही है';
  }

  @override
  String get tripInProgressText => 'लोकेशन कंट्रोल टावर से साझा है';

  @override
  String tripStarts(String time) {
    return 'शुरू $time';
  }

  @override
  String tripVehicle(String regNo) {
    return 'गाड़ी $regNo';
  }
}
