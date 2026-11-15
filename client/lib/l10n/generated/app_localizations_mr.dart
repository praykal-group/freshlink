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

  @override
  String get acceptReroute => 'नवीन मार्ग स्वीकारा';

  @override
  String get declineReroute => 'सध्याचा मार्ग ठेवा';

  @override
  String get acknowledge => 'स्वीकारले';

  @override
  String get alertTemp => 'तापमान मर्यादेबाहेर';

  @override
  String get alertTempDo =>
      'रीफर चालू आहे आणि सेटपॉइंट बरोबर आहे ते तपासा. दारे बंद ठेवा.';

  @override
  String get alertDriverFix => 'तापमान हळूहळू वाढत आहे';

  @override
  String get alertDriverFixDo =>
      'दाराचे सील, रीफर सेटपॉइंट आणि हवेचा मार्ग मोकळा आहे ते तपासा. 15 मिनिटांनी पुन्हा तपासणी होईल.';

  @override
  String get alertSpoilage => 'माल खराब होण्याचा धोका';

  @override
  String get alertSpoilageDo =>
      'कंट्रोल टॉवरकडून नवीन मार्गाची वाट पाहा आणि तो स्वीकारा.';

  @override
  String get alertHumidity => 'आर्द्रता मर्यादेबाहेर';

  @override
  String get alertHumidityDo => 'दारे आणि रीफर तपासा.';

  @override
  String get alertEthylene => 'इथिलीन जास्त';

  @override
  String get alertEthyleneDo =>
      'सुरक्षित असल्यास हवा खेळती ठेवा आणि कंट्रोल टॉवरला कळवा.';

  @override
  String get alertShock => 'जोराचा धक्का नोंदला';

  @override
  String get alertShockDo => 'सुरक्षित ठिकाणी थांबून माल तपासा.';

  @override
  String get alertDevice => 'सेन्सर बंद';

  @override
  String get alertDeviceDo => 'सेन्सर पॉडची वीज आणि केबल तपासा.';

  @override
  String get alertGeneric => 'मालाची सूचना';

  @override
  String get alertGenericDo => 'संदेश वाचा आणि कंट्रोल टॉवरच्या सूचना पाळा.';

  @override
  String get allStopsDone => 'सर्व थांबे पूर्ण. डेपोला परत जा.';

  @override
  String get allUploaded => 'सर्व अपलोड झाले';

  @override
  String pendingUploads(int count) {
    return '$count गोष्टी अपलोड व्हायच्या बाकी';
  }

  @override
  String get arrived => 'मी पोहोचलो';

  @override
  String get deliverHere => 'येथे डिलिव्हरी करा';

  @override
  String get cargoStatus => 'माल';

  @override
  String get cargoTemp => 'तापमान';

  @override
  String get cargoHumidity => 'आर्द्रता';

  @override
  String cargoLowestShelfLife(String value) {
    return 'सर्वात कमी टिकाऊपणा: $value';
  }

  @override
  String cargoAsOf(String time) {
    return 'शेवटचा अपडेट $time (ऑफलाइन)';
  }

  @override
  String get cargoEmpty => 'गाडीत माल नाही';

  @override
  String cargoSafeRange(String min, String max) {
    return 'सुरक्षित $min ते $max °C';
  }

  @override
  String get clear => 'पुसा';

  @override
  String get gpsOff => 'लोकेशन बंद आहे. ट्रिप सुरू करण्यासाठी चालू करा.';

  @override
  String get gpsDenied => 'ट्रिप ट्रॅक करण्यासाठी लोकेशनची परवानगी हवी.';

  @override
  String get gpsDeniedForever =>
      'लोकेशनची परवानगी बंद आहे. सेटिंग्जमध्ये चालू करा.';

  @override
  String get gpsFailed => 'ट्रिप ट्रॅकिंग सुरू झाले नाही. पुन्हा प्रयत्न करा.';

  @override
  String get notificationsDenied =>
      'सूचना चालू करा म्हणजे ट्रिप ट्रॅक होत आहे ते दिसेल.';

  @override
  String get openSettings => 'सेटिंग्ज उघडा';

  @override
  String historyPods(int count) {
    return 'नोंदलेल्या डिलिव्हरी: $count';
  }

  @override
  String get noHistory => 'अजून ट्रिप नाही';

  @override
  String get tripHistory => 'ट्रिप इतिहास';

  @override
  String get incDelay => 'उशीर';

  @override
  String get incBreakdown => 'गाडी बंद पडली';

  @override
  String get incAccident => 'अपघात';

  @override
  String get incRoadblock => 'रस्ता बंद';

  @override
  String get incReeferFault => 'रीफर बिघाड';

  @override
  String get incPhoto => 'फोटो जोडा';

  @override
  String get incPhotoDone => 'फोटो जोडला';

  @override
  String get incPhotoHint => 'समस्या दाखवा';

  @override
  String get incVoice => 'आवाज संदेश';

  @override
  String incVoiceDone(int seconds) {
    return 'आवाज संदेश $seconds से.';
  }

  @override
  String incVoiceStop(int seconds) {
    return 'थांबवा ($seconds से. बाकी)';
  }

  @override
  String get incSend => 'अहवाल पाठवा';

  @override
  String get incSent => 'अहवाल जतन झाला. नेटवर्क मिळताच पाठवला जाईल.';

  @override
  String get incQueuedHint => 'नेटवर्कशिवायही चालते: नंतर पाठवले जाते.';

  @override
  String get reportIncident => 'घटना कळवा';

  @override
  String get micDenied => 'आवाज संदेशासाठी माइकची परवानगी हवी.';

  @override
  String get navigate => 'मार्ग दाखवा';

  @override
  String get nextStop => 'पुढचा थांबा';

  @override
  String get noTripToday => 'आज ट्रिप नाही';

  @override
  String get noTripTodayHint => 'पुन्हा तपासण्यासाठी खाली ओढा.';

  @override
  String openAlerts(int count) {
    return '$count उघड्या सूचना: पाहण्यासाठी दाबा';
  }

  @override
  String get openTrip => 'ट्रिप उघडा';

  @override
  String get preCheck => 'ट्रिपपूर्व तपासणी';

  @override
  String get preCheckAgain => 'पुन्हा तपासा';

  @override
  String get pcReeferOn => 'रीफर चालू आहे';

  @override
  String get pcSetpointChecked => 'सेट तापमान तपासले';

  @override
  String get pcDoorsClosed => 'दारे बंद आहेत';

  @override
  String get pcSetpoint => 'रीफर सेट तापमान';

  @override
  String get pcSubmit => 'तपासणी जतन करा';

  @override
  String get pcAllNeeded => 'पुढे जाण्यासाठी तिन्ही तपासण्या चालू करा.';

  @override
  String get pcFailed => 'तपासणी अयशस्वी';

  @override
  String get pcReeferOff => 'रीफर बंद आहे';

  @override
  String get pcDoorsOpen => 'दार उघडे आहे';

  @override
  String get pcSetpointOut => 'हे सेट तापमान या मालासाठी चुकीचे आहे';

  @override
  String get pcIncompatible =>
      'ही उत्पादने एकत्र जाऊ शकत नाहीत. कंट्रोल टॉवरला कॉल करा.';

  @override
  String pcAllowedRange(String min, String max) {
    return 'परवानगी: $min ते $max °C';
  }

  @override
  String get podAccepted => 'स्वीकारले';

  @override
  String get podPartial => 'अंशतः';

  @override
  String get podRejected => 'नाकारले';

  @override
  String get podAcceptedKg => 'स्वीकारलेले वजन';

  @override
  String podBatchWeight(String kg) {
    return 'वजन $kg किलो';
  }

  @override
  String get podReason => 'कारण';

  @override
  String get podReceiver => 'घेणाऱ्याचे नाव';

  @override
  String get podSignature => 'घेणाऱ्याची सही';

  @override
  String get podPhoto => 'डिलिव्हरीचा फोटो';

  @override
  String get podPhotoDone => 'फोटो घेतला';

  @override
  String get podPhotoHint => 'घेणाऱ्याकडील क्रेट दाखवा';

  @override
  String get podSubmit => 'डिलिव्हरी सादर करा';

  @override
  String get podSaved => 'डिलिव्हरी जतन झाली. नेटवर्क मिळताच पाठवली जाईल.';

  @override
  String get podDone => 'या थांब्याची डिलिव्हरी नोंदली आहे.';

  @override
  String podScanTitle(int done, int total) {
    return 'प्रत्येक क्रेट स्कॅन करा: $total पैकी $done';
  }

  @override
  String podOtherStop(String code) {
    return 'क्रेट $code दुसऱ्या थांब्याचा आहे. गाडीत ठेवा.';
  }

  @override
  String podUnknownCrate(String code) {
    return '$code या गाडीत नाही.';
  }

  @override
  String get podNeedScan => 'क्रेट स्कॅन करा';

  @override
  String get podWrongTag => 'चुकीचा क्रेट';

  @override
  String get podNeedKg => 'स्वीकारलेले वजन टाका (पूर्ण वजनापेक्षा कमी)';

  @override
  String get podNeedReason => 'कारण लिहा';

  @override
  String get podNeedReceiver => 'घेणाऱ्याचे नाव टाका';

  @override
  String get podNeedSignature => 'घेणाऱ्याची सही घ्या';

  @override
  String get podNeedPhoto => 'डिलिव्हरीचा फोटो घ्या';

  @override
  String get reasonDelay => 'रस्त्यात उशीर: थांब्यांचा जलद क्रम';

  @override
  String get reasonIncident => 'घटना: माल वाचवण्यासाठी मार्ग बदलला';

  @override
  String get reasonDiversion =>
      'वळण: माल खराब होण्याआधी जवळच्या खरेदीदाराला द्या';

  @override
  String get reasonRescue => 'बचाव: माल दुसऱ्या गाडीला द्या';

  @override
  String get reasonManual => 'कंट्रोल टॉवरने मार्ग बदलला';

  @override
  String get rerouteTitle => 'नवीन मार्ग';

  @override
  String get rerouteOld => 'आधी जात होता';

  @override
  String get rerouteNew => 'आता जा';

  @override
  String rerouteExtraKm(String km) {
    return '$km किमी जास्त';
  }

  @override
  String rerouteShorterKm(String km) {
    return '$km किमी कमी';
  }

  @override
  String get rerouteMustAccept =>
      'हा मार्ग माल वाचवतो आणि स्वीकारणे आवश्यक आहे.';

  @override
  String get rerouteWaiting => 'नवीन मार्ग वाट पाहत आहे: पाहण्यासाठी दाबा';

  @override
  String shelfLifeDays(int days, int hours) {
    return '$days दिवस $hours तास बाकी';
  }

  @override
  String shelfLifeHm(int hours, int minutes) {
    return '$hours तास $minutes मिनिटे बाकी';
  }

  @override
  String get shelfLifeExpired => 'टिकाऊपणा संपला';

  @override
  String get shelfLifeUnknown => 'टिकाऊपणा अजून माहीत नाही';

  @override
  String get sos => 'SOS';

  @override
  String get sosSent => 'SOS पाठवला';

  @override
  String get sosSentBody =>
      'तुमचे लोकेशन कंट्रोल टॉवर आणि आपत्कालीन संपर्काला जाते. सुरक्षित राहा; मदत येत आहे.';

  @override
  String get speedLockTitle => 'गाडी चालू आहे';

  @override
  String get speedLockBody =>
      'ही स्क्रीन वापरण्यासाठी गाडी थांबवा. मार्ग आणि SOS चालू राहतील.';

  @override
  String get startTrip => 'ट्रिप सुरू करा';

  @override
  String get startNeedsPreCheck => 'आधी ट्रिपपूर्व तपासणी करा.';

  @override
  String get stopArriveHint => 'गाडी या थांब्यावर पोहोचल्यावर दाबा.';

  @override
  String get stopPickupHint => 'पिकअप थांबा: येथे काही द्यायचे नाही.';

  @override
  String get stopNotFound => 'हा थांबा आता मार्गावर नाही.';

  @override
  String get stopPickup => 'पिकअप';

  @override
  String get stopDrop => 'डिलिव्हरी';

  @override
  String get stopDiversion => 'वळण खरेदीदार';

  @override
  String get stopRescuePickup => 'बचाव पिकअप';

  @override
  String get stopRescueDrop => 'बचाव गाडीला द्या';

  @override
  String get stopColdStorage => 'शीतगृह';

  @override
  String stopEta(String time) {
    return 'पोहोच $time';
  }

  @override
  String stopWindow(String window) {
    return 'वेळ $window';
  }

  @override
  String tripBatches(int count) {
    return 'बॅच: $count';
  }

  @override
  String tripInProgress(String code) {
    return 'ट्रिप $code सुरू आहे';
  }

  @override
  String get tripInProgressText => 'लोकेशन कंट्रोल टॉवरसोबत शेअर होत आहे';

  @override
  String tripStarts(String time) {
    return 'सुरू $time';
  }

  @override
  String tripVehicle(String regNo) {
    return 'गाडी $regNo';
  }
}
