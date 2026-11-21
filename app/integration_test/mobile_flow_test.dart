import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixture = String.fromEnvironment('PASS_PACE_TEST_API');
  testWidgets('Android에서 팀 API의 회원·목표·계획·상담과 로그인 복원을 확인한다', (t) async {
    // Write tests run only against a separately seeded, disposable server.
    expect(Uri.parse(fixture).host, anyOf('10.0.2.2', '127.0.0.1'));
    expect(Uri.parse(fixture).port, 43315);
    final client = http.Client();
    addTearDown(client.close);
    final session = Session(AndroidStore(), client);
    await session.changeOrigin(fixture);
    final unique = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final id = 'ui_$unique',
        secret =
            'Pp@${List.generate(18, (_) => Random.secure().nextInt(36).toRadixString(36)).join()}';
    Future<void> until(
      bool Function() condition, {
      String why = '화면 표시',
    }) async {
      final timeout = DateTime.now().add(const Duration(seconds: 55));
      while (!condition() && DateTime.now().isBefore(timeout)) {
        await t.pump(const Duration(milliseconds: 120));
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
      expect(condition(), isTrue, reason: why);
    }

    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 220));
    }

    Future<void> input(Finder f, String v) async {
      await t.ensureVisible(f);
      await t.enterText(f, v);
      await t.pump();
    }

    Future<void> capture(String name) async {
      ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
          .hideCurrentSnackBar();
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      final bytes = await binding.takeScreenshot(name);
      await File('${Directory.systemTemp.path}/passpace-$name.png')
          .writeAsBytes(bytes);
    }

    await t.pumpWidget(PassPaceApp(session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await t.pumpAndSettle();
    await capture('login');
    await tap(find.widgetWithText(OutlinedButton, '회원가입'));
    await t.pumpAndSettle();
    await capture('signup');
    for (final (i, v) in [
      id,
      secret,
      secret,
      '모바일검증',
      'mobile-$unique@example.invalid',
    ].indexed) {
      await input(find.byType(TextFormField).at(i), v);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await tap(find.text('유사전공').last);
    await t.pumpAndSettle();
    await tap(find.widgetWithText(FilledButton, '가입 완료'));
    await until(
      () => find.textContaining('회원가입이 완료됐어요').evaluate().isNotEmpty,
      why: '가입 완료 후 로그인 복귀',
    );
    expect(
      (t.widget<TextFormField>(find.byType(TextFormField).at(0)))
          .controller!
          .text,
      id,
    );
    await input(find.byType(TextFormField).at(1), secret);
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await tap(find.widgetWithText(FilledButton, '로그인'));
    await until(
      () => find.text('모바일검증님의 학습').evaluate().isNotEmpty,
      why: '로그인 후 대시보드',
    );
    final api = session.account!;
    expect(await api.saved(), isNull);
    final goal = await api.goal();
    final today = dayInSeoul(), finish = isoDay(plusDays(today, 35));
    final knowledge = <String, int>{
      if (goal.subjects.isNotEmpty)
        goal.subjects.first['subjectId'].toString(): 2,
    };
    await api.updateGoal({
      'examRoundId': null,
      'targetExamDate': finish,
      'dailyMinutes': 125,
      'familiarity': knowledge,
    });
    expect((await api.goal()).minutes, 125);
    await tap(find.text('내 정보'));
    await t.pumpAndSettle();
    await tap(find.text('학습계획 관리'));
    await until(() => find.text('목표와 기본 설정').evaluate().isNotEmpty);
    await capture('learning-plan');
    await tap(find.text('설정 수정'));
    await until(() => find.byType(TextField).evaluate().isNotEmpty);
    await capture('goal');
    expect(
      (t.widget<TextField>(find.byType(TextField).first)).controller!.text,
      '125',
    );
    await tap(find.text('목표 저장'));
    await until(() => find.text('목표를 저장했어요').evaluate().isNotEmpty);
    await capture('goal-saved');
    expect(await api.saved(), isNull);
    final cat = await api.catalog();
    final exam = cat.exams.firstWhere(
      (e) =>
          e.subjects.isNotEmpty &&
          e.subjects.every((s) => s['baseHours'] != null),
    );
    await tap(find.text('이 설정으로 계획 만들기'));
    await until(() => find.text('하루 최대 학습 시간').evaluate().isNotEmpty);
    await capture('plan-time');
    await input(find.byType(TextField).first, '125');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await tap(find.widgetWithText(FilledButton, '다음'));
    await until(() => find.text('준비할 시험').evaluate().isNotEmpty);
    await tap(find.widgetWithText(CheckboxListTile, exam.name));
    await t.pumpAndSettle();
    final examDay = find.widgetWithText(OutlinedButton, '목표 시험일');
    await tap(examDay);
    await t.pumpAndSettle();
    if (exam.suggested == null ||
        !exam.suggested!.isAfter(today) ||
        exam.suggested!.isAfter(plusDays(today, 540))) {
      await t.tap(find.byTooltip('다음 달'));
      await t.pumpAndSettle();
      await t.tap(find.text('15').last);
      await t.pumpAndSettle();
    }
    await tap(find.text('확인').last);
    await t.pumpAndSettle();
    await capture('plan-exams');
    await tap(find.widgetWithText(FilledButton, '다음'));
    await t.pumpAndSettle();
    final ratings = find.widgetWithText(ChoiceChip, '보통');
    for (int i = 0; i < exam.subjects.length; i++) {
      await tap(ratings.at(i));
    }
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect((await session.planDraft.read())!.step, 2);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    final resumedSession = Session(AndroidStore(), client);
    await resumedSession.restore();
    await t.pumpWidget(PassPaceApp(resumedSession));
    await t.pumpAndSettle();
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('학습계획'),
      ),
    );
    await t.pumpAndSettle();
    await tap(find.text('학습계획 만들기').last);
    await until(() => find.text('이어서 작성할 계획이 있어요').evaluate().isNotEmpty);
    await tap(find.text('이어서 작성'));
    await t.pumpAndSettle();
    expect(find.text('나에게 맞는 학습량'), findsOneWidget);
    expect(find.text('이미 공부한 과목이 있나요?'), findsNothing);
    expect(find.text('학습량 산정 근거'), findsNothing);
    expect(find.text('계획 계산 기준'), findsNothing);
    await capture('plan-input');
    await tap(find.widgetWithText(FilledButton, '계획 미리보기'));
    await until(
      () => find.text('주간 배정').evaluate().isNotEmpty,
      why: '서버 계산 미리보기',
    );
    await capture('preview');
    expect(await api.saved(), isNull);
    await tap(find.text('이 계획 저장'));
    await t.pumpAndSettle();
    await tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(await api.saved(), isNull);
    await tap(find.text('이 계획 저장'));
    await t.pumpAndSettle();
    await tap(find.text('저장하기'));
    await until(
      () => find.text('날짜별 학습').evaluate().isNotEmpty,
      why: '확인 후 서버 저장 및 계획 탭 복귀',
    );
    await capture('plan');
    await tap(find.text('오늘').last);
    await t.pumpAndSettle();
    await capture('home');
    await tap(find.text('내 정보').last);
    await t.pumpAndSettle();
    await capture('profile');
    await tap(find.text('상담').last);
    await t.pumpAndSettle();
    await capture('chat');
    await input(find.byType(TextField).first, 'SQLD 준비 방법을 알려 주세요.');
    await tap(find.byTooltip('질문 보내기'));
    await until(() => find.text('기본 학습 안내').evaluate().isNotEmpty);
    await capture('chat-reply');
    final original = (await api.saved())!;
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('학습계획'),
      ),
    );
    await t.pumpAndSettle();
    await tap(find.text('새 계획 미리보기'));
    await until(() => find.text('기존 값 불러오기').evaluate().isNotEmpty);
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '125',
    );
    await tap(find.widgetWithText(FilledButton, '다음'));
    await tap(find.widgetWithText(CheckboxListTile, exam.name));
    if (exam.suggested == null ||
        !exam.suggested!.isAfter(today) ||
        exam.suggested!.isAfter(plusDays(today, 540))) {
      await tap(find.widgetWithText(OutlinedButton, '목표 시험일'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('다음 달'));
      await t.pumpAndSettle();
      await t.tap(find.text('15').last);
      await t.pumpAndSettle();
      await tap(find.text('확인').last);
    }
    await tap(find.widgetWithText(FilledButton, '다음'));
    await t.pumpAndSettle();
    for (int i = 0; i < exam.subjects.length; i++) {
      await tap(find.widgetWithText(ChoiceChip, '보통').at(i));
    }
    await tap(find.widgetWithText(ChoiceChip, '익숙함').first);
    await t.pumpAndSettle();
    await tap(find.text('계획 미리보기'));
    await until(() => find.text('현재 계획과 변경 비교').evaluate().isNotEmpty);
    await capture('comparison-summary');
    final details = find.textContaining('변경 상세');
    expect(details, findsOneWidget);
    await tap(details);
    await t.pumpAndSettle();
    expect(find.text('계획 변경 상세'), findsOneWidget);
    await capture('comparison');
    await tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await tap(find.text('이 계획 저장'));
    await t.pumpAndSettle();
    await tap(find.text('취소'));
    await t.pumpAndSettle();
    expect((await api.saved())!.id, original.id);
    await tap(find.text('이 계획 저장'));
    await t.pumpAndSettle();
    await tap(find.text('저장하기'));
    await until(() => find.text('날짜별 학습').evaluate().isNotEmpty);
    final replaced = (await api.saved())!;
    expect(replaced.id, isNot(original.id));
    expect(replaced.version, original.version + 1);
    expect(await resumedSession.planDraft.read(), isNull);
    final webToken = await PassApi(client, fixture).login(id, secret);
    final fromAnotherLogin = await PassApi(
      client,
      fixture,
      token: webToken,
    ).saved();
    expect(fromAnotherLogin!.byDay, isNotEmpty);
    expect(await resumedSession.planDraft.read(), isNull);
    final reply = await api.chat('SQLD 준비 방법을 알려 주세요.', null);
    expect(reply.answer, isNotEmpty);
    expect(reply.conversation, greaterThan(0));
    final next = await api.chat('하루 두 시간이면 어떻게 준비하나요?', reply.conversation);
    expect(next.conversation, reply.conversation);
    final reopened = Session(AndroidStore(), client);
    await reopened.restore();
    expect(reopened.user!.id, id);
    expect((await reopened.account!.saved())!.name, fromAnotherLogin.name);
    await reopened.updateProfile(
      '수정한이름',
      'mobile-$unique@example.invalid',
      'MAJOR',
    );
    expect((await reopened.account!.profile()).name, '수정한이름');
    await reopened.changeOrigin(emulatorOrigin);
    await t.pumpAndSettle();
  }, skip: fixture.isEmpty);
}
