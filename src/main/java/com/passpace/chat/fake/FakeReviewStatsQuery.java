package com.passpace.chat.fake;

import com.passpace.common.stats.ReviewSample;
import com.passpace.common.stats.ReviewStatsQuery;
import com.passpace.common.stats.StatsCondition;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/**
 * [동건] 가짜 후기 조회 - 용성의 수집·SQL 없이 챗봇만 개발할 때 사용.
 * 실행: IntelliJ 실행 설정 Active profiles 에 fake 입력 (또는 --spring.profiles.active=fake)
 * fake 프로필에서는 용성의 JdbcReviewStatsQuery 가 꺼지므로 같은 인터페이스 Bean 이 두 개가 되지 않는다.
 * (DB 연결은 회원·대화 저장 때문에 여전히 필요)
 */
@Component
@Profile("fake")
public class FakeReviewStatsQuery implements ReviewStatsQuery {

    @Override
    public List<ReviewSample> findSamples(StatsCondition c) {
        // 조건의 준비 기간 범위 안에서 지어낸 후기 12건 (합격 10, 불합격 2)
        List<ReviewSample> list = new ArrayList<>();
        int[] daily = {120, 150, 150, 180, 180, 180, 210, 240, 120, 150};
        for (int i = 0; i < daily.length; i++) {
            int prep = c.minPrepDays() + (c.maxPrepDays() - c.minPrepDays()) * i / daily.length;
            list.add(new ReviewSample(true, daily[i], BigDecimal.valueOf(prep * daily[i] / 60 * 0.8), prep,
                    c.majorType() == null ? "NON_MAJOR" : c.majorType().name(),
                    i % 3 == 0 ? "BALANCED" : "PAST_EXAM", "데이터베이스 구축",
                    "(가짜) " + prep + "일 동안 하루 " + daily[i] + "분씩 기출을 반복했다.",
                    "https://example.com/fake/" + i));
        }
        list.add(new ReviewSample(false, 60, null, c.minPrepDays(), null, "THEORY", null, null, null));
        list.add(new ReviewSample(false, 45, null, c.maxPrepDays(), null, "THEORY", null, null, null));
        return list;
    }
}
