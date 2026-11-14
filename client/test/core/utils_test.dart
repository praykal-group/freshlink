import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/core/errors/app_exception.dart';
import 'package:iccms/core/utils/backoff.dart';
import 'package:iccms/core/utils/single_flight.dart';
import 'package:iccms/core/utils/validators.dart';

void main() {
  group('validators', () {
    test('Indian mobile: 10 digits starting 6–9, spaces/dashes ignored', () {
      expect(Validators.indianMobile('9876543210'), isNull);
      expect(Validators.indianMobile('98765 43210'), isNull);
      expect(Validators.indianMobile('98765-43210'), isNull);
      expect(Validators.indianMobile('')!.error, ValidationError.required);
      expect(Validators.indianMobile('5876543210')!.error, ValidationError.phoneInvalid);
      expect(Validators.indianMobile('987654321')!.error, ValidationError.phoneInvalid);
      expect(Validators.indianMobile('98765432100')!.error, ValidationError.phoneInvalid);
      expect(Validators.indianMobile('98765abcde')!.error, ValidationError.phoneInvalid);
      expect(Validators.toE164India('98765 43210'), '+919876543210');
    });

    test('OTP: exactly 6 digits', () {
      expect(Validators.otp('123456'), isNull);
      expect(Validators.otp(' 123456 '), isNull);
      expect(Validators.otp('12345')!.error, ValidationError.otpInvalid);
      expect(Validators.otp('12a456')!.error, ValidationError.otpInvalid);
      expect(Validators.otp(null)!.error, ValidationError.required);
    });

    test('email and password', () {
      expect(Validators.email('manager@iccms.in'), isNull);
      expect(Validators.email('a.b+c@x.co.in'), isNull);
      expect(Validators.email('no-at-sign')!.error, ValidationError.emailInvalid);
      expect(Validators.email('a@b')!.error, ValidationError.emailInvalid);
      expect(Validators.password('12345678'), isNull);
      expect(Validators.password('1234567'), const ValidationResult(ValidationError.passwordTooShort, limit: 8));
    });

    test('numeric range from the products master (FO-NFR-07), decimal comma accepted', () {
      // e.g. initial core temperature of fish 0–4 °C
      expect(Validators.numberInRange('2.5', min: 0, max: 4), isNull);
      expect(Validators.numberInRange('2,5', min: 0, max: 4), isNull);
      expect(Validators.numberInRange('4', min: 0, max: 4), isNull);
      expect(Validators.numberInRange('-0.1', min: 0, max: 4), const ValidationResult(ValidationError.belowMin, limit: 0));
      expect(Validators.numberInRange('4.01', min: 0, max: 4), const ValidationResult(ValidationError.aboveMax, limit: 4));
      expect(Validators.numberInRange('abc', min: 0)!.error, ValidationError.notANumber);
      expect(Validators.numberInRange('', min: 0)!.error, ValidationError.required);
      expect(Validators.numberInRange('', min: 0, required: false), isNull);
    });
  });

  group('backoff (sync retries)', () {
    test('doubles from 5 s and caps at 30 min', () {
      const b = Backoff(jitter: false);
      expect([1, 2, 3, 4].map((a) => b.delay(a).inSeconds), [5, 10, 20, 40]);
      expect(b.delay(9).inMinutes, 21); // 5 s × 256 = 1280 s
      expect(b.delay(10), const Duration(minutes: 30));
      expect(b.delay(50), const Duration(minutes: 30));
      expect(b.delay(0), Duration.zero);
    });

    test('jitter stays between half and the full delay', () {
      const b = Backoff();
      expect(b.delay(3, random: 0).inSeconds, 10);
      expect(b.delay(3, random: 0.999).inMilliseconds, closeTo(20000, 10));
      expect(syncBackoff.delay(100, random: 1).inMinutes, 30);
    });
  });

  test('AppException: transient vs permanent (Section 10.2 sync rules)', () {
    expect(const AppException('NETWORK', 'x').isTransient, isTrue);
    for (final s in [500, 502, 408, 429]) {
      expect(AppException('X', 'x', status: s).isTransient, isTrue, reason: '$s');
    }
    for (final s in [400, 403, 404, 409, 422]) {
      expect(AppException('X', 'x', status: s).isPermanent, isTrue, reason: '$s');
    }
  });

  test('single flight: concurrent callers share one run; the next call starts a new one', () {
    fakeAsync((async) {
      final sf = SingleFlight<int>();
      var runs = 0;
      Future<int> task() async {
        runs++;
        await Future<void>.delayed(const Duration(seconds: 1));
        return runs;
      }

      final results = <int>[];
      for (var i = 0; i < 10; i++) {
        sf.run(task).then(results.add);
      }
      async.elapse(const Duration(seconds: 2));
      expect(runs, 1);
      expect(results, List.filled(10, 1));
      sf.run(task).then(results.add);
      async.elapse(const Duration(seconds: 2));
      expect(runs, 2);
    });
  });
}
