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

  @override
  String get ok => 'ठीक आहे';

  @override
  String get close => 'बंद करा';

  @override
  String get next => 'पुढे';

  @override
  String get back => 'मागे';

  @override
  String get skip => 'वगळा';

  @override
  String get send => 'पाठवा';

  @override
  String get saved => 'जतन केले';

  @override
  String todayAtSite(String site) {
    return 'आज $site येथे';
  }

  @override
  String get countRegistered => 'नोंदवले';

  @override
  String get countGraded => 'ग्रेड झाले';

  @override
  String get countStored => 'साठवणुकीत';

  @override
  String get countDispatched => 'पाठवले';

  @override
  String get newFishBatch => 'नवीन मासे बॅच';

  @override
  String get newProduceBatch => 'नवीन फळ-भाजी बॅच';

  @override
  String get receive => 'स्वीकारा';

  @override
  String get loadTruck => 'ट्रक भरा';

  @override
  String get batches => 'बॅच';

  @override
  String get printer => 'प्रिंटर';

  @override
  String get resumeDraft => 'सुरू केलेली बॅच पूर्ण करा';

  @override
  String get discardDraft => 'काढून टाका';

  @override
  String get stepForm => 'तपशील';

  @override
  String get stepTag => 'टॅग';

  @override
  String get stepPhotos => 'फोटो';

  @override
  String get stepGrade => 'ग्रेड';

  @override
  String get stepStorage => 'साठवण';

  @override
  String get stepLabel => 'लेबल';

  @override
  String get stepDone => 'पूर्ण';

  @override
  String stepOf(int n, int total) {
    return 'पायरी $n / $total';
  }

  @override
  String get product => 'उत्पादन';

  @override
  String get catchTime => 'पकडण्याची वेळ';

  @override
  String get harvestTime => 'काढणीची वेळ';

  @override
  String get weight => 'वजन';

  @override
  String get vesselId => 'बोट क्रमांक';

  @override
  String get farmRef => 'शेत क्रमांक';

  @override
  String get iceRatio => 'बर्फ-मासे प्रमाण';

  @override
  String get coreTemp => 'आतील तापमान';

  @override
  String get maturity => 'पिकण्याचा स्तर';

  @override
  String get brix => 'ब्रिक्स';

  @override
  String get fieldTemp => 'शेतातील तापमान';

  @override
  String get fieldHumidity => 'शेतातील आर्द्रता';

  @override
  String get listening => 'ऐकत आहे… संख्या बोला';

  @override
  String get voiceNotHeard =>
      'संख्या ऐकू आली नाही. पुन्हा बोला किंवा टाइप करा.';

  @override
  String get mastersMissing =>
      'मास्टर याद्या अजून डाउनलोड झाल्या नाहीत. एकदा इंटरनेटशी जोडा.';

  @override
  String get tagChoose => 'क्रेटला टॅग लावा';

  @override
  String get tagNfc => 'NFC टॅग लावा';

  @override
  String get tagQr => 'QR स्कॅन करा';

  @override
  String get tagWedge => 'RFID रीडर';

  @override
  String tagRead(String uid) {
    return 'टॅग $uid';
  }

  @override
  String get tagInvalid => 'हा योग्य टॅग नाही';

  @override
  String get tagWedgeTitle => 'RFID रीडरने स्कॅन करा';

  @override
  String get tagWedgeHelp =>
      'रीडरचे बटण दाबा, किंवा टॅग क्रमांक लिहून Enter दाबा.';

  @override
  String get nfcHold => 'टॅग फोनच्या मागे धरा';

  @override
  String get nfcUnavailable =>
      'NFC बंद आहे किंवा उपलब्ध नाही. QR किंवा RFID रीडर वापरा.';

  @override
  String get scanQr => 'QR स्कॅन करा';

  @override
  String get scanQrHelp => 'कॅमेरा QR कोडकडे धरा';

  @override
  String get photoTop => 'वरून';

  @override
  String get photoSide => 'बाजूने';

  @override
  String get photoCloseup => 'जवळून';

  @override
  String get photoHelpTop => 'वरून: संपूर्ण क्रेट फ्रेममध्ये';

  @override
  String get photoHelpSide => 'बाजूने: क्रेटची खोली दाखवा';

  @override
  String get photoHelpCloseup => 'जवळून: एक मासा किंवा फळ पूर्ण फ्रेममध्ये';

  @override
  String get retake => 'पुन्हा घ्या';

  @override
  String get photosNeeded => 'तिन्ही फोटो घ्या';

  @override
  String get cameraUnavailable => 'कॅमेरा उपलब्ध नाही';

  @override
  String get gradeWaiting => 'ग्रेड होत आहे…';

  @override
  String get gradeQueued =>
      'ग्रेडिंग रांगेत आहे. फोन ऑनलाइन झाल्यावर ग्रेड मिळेल.';

  @override
  String get gradeUnavailable => 'आत्ता ग्रेडिंग उपलब्ध नाही. ते रांगेत आहे.';

  @override
  String gradeResult(String grade) {
    return 'ग्रेड $grade';
  }

  @override
  String confidence(int pct) {
    return 'खात्री $pct%';
  }

  @override
  String get defects => 'दोष';

  @override
  String get noDefects => 'कोणताही दोष आढळला नाही';

  @override
  String get dispute => 'आक्षेप';

  @override
  String get disputeReason => 'ग्रेड चुकीचा का आहे?';

  @override
  String get disputeSent => 'आक्षेप मॅनेजरला पाठवला';

  @override
  String get pathBlastChiller => 'ब्लास्ट चिलर';

  @override
  String get pathRipening => 'पिकवण्याचा कक्ष';

  @override
  String get pathColdRoom => 'कोल्ड रूम';

  @override
  String get sellFirst => 'आधी विका';

  @override
  String recommendedUnit(String unit, String free) {
    return 'शिफारस: $unit ($free किलो रिकामे)';
  }

  @override
  String get noUnit => 'या साइटवर योग्य युनिट रिकामे नाही';

  @override
  String get assign => 'नेमा';

  @override
  String assigned(String unit) {
    return '$unit मध्ये ठेवले';
  }

  @override
  String get storageOffline =>
      'हे फोनवरील यादीतून दाखवले आहे. ऑनलाइन झाल्यावर नेमा.';

  @override
  String get print => 'प्रिंट करा';

  @override
  String get shareImage => 'फोटो पाठवा';

  @override
  String get labelOffline => 'बॅच सिंक झाल्यावर लेबल तयार होईल.';

  @override
  String get noPrinter => 'कोणताही प्रिंटर सेट नाही';

  @override
  String get printed => 'लेबल प्रिंटरला पाठवले';

  @override
  String get printFailed => 'प्रिंट झाले नाही. लेबल फोटो म्हणून पाठवा.';

  @override
  String get doneTitle => 'बॅच नोंदवली';

  @override
  String doneTime(int seconds) {
    return '$seconds सेकंदात पूर्ण';
  }

  @override
  String get newBatch => 'नवीन बॅच';

  @override
  String get goHome => 'होम';

  @override
  String get pendingSync => 'अजून सिंक झाले नाही';

  @override
  String get searchBatches => 'कोड किंवा टॅग शोधा';

  @override
  String get all => 'सर्व';

  @override
  String get stRegistered => 'नोंदवले';

  @override
  String get stGraded => 'ग्रेड झाले';

  @override
  String get stStored => 'साठवले';

  @override
  String get stAllocated => 'वाटप केले';

  @override
  String get stLoaded => 'भरले';

  @override
  String get stInTransit => 'वाटेत';

  @override
  String get stDiverted => 'वळवले';

  @override
  String get stDelivered => 'पोहोचवले';

  @override
  String get stPartial => 'अंशतः पोहोचवले';

  @override
  String get stRejected => 'नाकारले';

  @override
  String get stSpoiled => 'खराब';

  @override
  String shelfLifeHours(String hours) {
    return 'शेल्फ लाइफ $hours तास';
  }

  @override
  String get history => 'इतिहास';

  @override
  String get chainVerified => 'नोंद साखळी पडताळली';

  @override
  String get chainBroken => 'नोंद साखळी पडताळली नाही';

  @override
  String get edit => 'बदला';

  @override
  String get requestEdit => 'बदलाची विनंती';

  @override
  String editMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'बदलण्यासाठी $minutes मिनिटे बाकी',
      one: 'बदलण्यासाठी 1 मिनिट बाकी',
    );
    return '$_temp0';
  }

  @override
  String get editClosed => '30 मिनिटांची वेळ संपली. मॅनेजरला विनंती करा.';

  @override
  String get reason => 'कारण';

  @override
  String get requestSent => 'विनंती मॅनेजरला पाठवली';

  @override
  String get printLabel => 'लेबल प्रिंट करा';

  @override
  String get tags => 'टॅग';

  @override
  String get onlineOnly => 'यासाठी इंटरनेट आवश्यक आहे.';

  @override
  String get scanBatch => 'बॅच स्कॅन करा';

  @override
  String notFound(String value) {
    return '$value साठी बॅच सापडली नाही';
  }

  @override
  String get condition => 'स्थिती';

  @override
  String get condGood => 'चांगली';

  @override
  String get condFair => 'ठीक';

  @override
  String get condPoor => 'खराब';

  @override
  String get damagePhotos => 'नुकसानीचे फोटो';

  @override
  String get addPhoto => 'फोटो जोडा';

  @override
  String get outcome => 'निकाल';

  @override
  String get accept => 'स्वीकारा';

  @override
  String get partial => 'अंशतः';

  @override
  String get reject => 'नाकारा';

  @override
  String get acceptedWeight => 'स्वीकारलेले वजन';

  @override
  String get submit => 'जमा करा';

  @override
  String get receiveSaved => 'स्वीकृती जतन केली. ऑनलाइन झाल्यावर सिंक होईल.';

  @override
  String get noTrips => 'आज भरण्यासाठी कोणतीही ट्रिप नाही';

  @override
  String loadedCount(int n, int total) {
    return '$total पैकी $n भरले';
  }

  @override
  String wrongBatch(String code) {
    return 'हे या ट्रिपचे नाही: $code';
  }

  @override
  String get alreadyScanned => 'आधीच स्कॅन केले';

  @override
  String get confirmLoad => 'भरणे निश्चित करा';

  @override
  String get loadSaved => 'भरणे जतन केले. ऑनलाइन झाल्यावर सिंक होईल.';

  @override
  String get scanNext => 'पुढचा क्रेट स्कॅन करा';

  @override
  String get pairedPrinters => 'जोडलेले प्रिंटर';

  @override
  String get noPairedPrinters =>
      'कोणताही प्रिंटर जोडलेला नाही. आधी फोनच्या ब्लूटूथ सेटिंगमध्ये प्रिंटर जोडा.';

  @override
  String get testPrint => 'चाचणी प्रिंट';

  @override
  String get selectedPrinter => 'निवडले';

  @override
  String get bluetoothOff => 'ब्लूटूथ बंद आहे. प्रिंटसाठी सुरू करा.';
}
