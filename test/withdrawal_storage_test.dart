import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/plan_draft.dart';

import 'support/study_fixture.dart';

void main() {
  test('탈퇴 확인 뒤에만 해당 계정의 로컬 초안·타이머·과목 색상을 정리한다', () async {
    var prepared = false;
    final fixture = StudyFixture(
      override: (request) async {
        if (request.method == 'DELETE' && request.url.path == '/users/me') {
          expect(prepared, isTrue);
          return studyEnvelope({
            'withdrawn': true,
            'personalDataDeleted': true,
          });
        }
        return null;
      },
    );
    addTearDown(fixture.dispose);
    final session = fixture.session;
    await session.restore();
    final login = session.user!.id;
    final draft = session.planDraft.key;
    final timer = accountStorageKey('study-timer', session.origin, login);
    final subjectColors = accountStorageKey(
      'subject-colors',
      session.origin,
      login,
    );
    final otherColors = accountStorageKey(
      'subject-colors',
      session.origin,
      'SAMPLE_OTHER',
    );
    final other = accountStorageKey(
      'study-timer',
      session.origin,
      'SAMPLE_OTHER',
    );
    for (final key in [draft, timer, subjectColors, other, otherColors]) {
      await session.drafts.write(key, 'SAMPLE');
    }
    await session.withdrawAccount(
      'SAMPLE password',
      '$login회원탈퇴',
      prepare: () async {
        prepared = true;
        expect(await session.drafts.read(draft), 'SAMPLE');
        return true;
      },
    );
    expect(session.user, isNull);
    expect(await session.drafts.read(draft), isNull);
    expect(await session.drafts.read(timer), isNull);
    expect(await session.drafts.read(subjectColors), isNull);
    expect(await session.drafts.read(otherColors), 'SAMPLE');
    expect(await session.drafts.read(other), 'SAMPLE');
    expect(session.notice, contains('회원탈퇴가 완료'));
  });
}
