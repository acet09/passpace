import 'package:flutter/material.dart';

import 'design.dart';

class AuthIntro extends StatelessWidget {
  const AuthIntro({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          SizedBox(width: 20, child: Divider(color: blue, thickness: 2)),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              '자격증 준비, 나만의 페이스로',
              style: TextStyle(
                color: blue,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Entrance(
        child: Semantics(
          header: true,
          child: const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '시험까지의 계획을,\n'),
                TextSpan(
                  text: '오늘의 공부로.',
                  style: TextStyle(color: blue),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w800,
              height: 1.3,
              letterSpacing: -1,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      const HelpText('목표와 가능한 시간을 정하고,\n내 계획에 맞춰 차근차근 준비하세요.'),
    ],
  );
}
