package com.passpace.service;

import com.passpace.dto.user.UserViews.UpcomingExam;
import com.passpace.repository.HomeRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;

import java.util.List;

/** [한결] 메인 페이지 구현 */
@Service
public class HomeServiceImpl implements HomeService {

    private static final Logger log = LoggerFactory.getLogger(HomeServiceImpl.class);

    private final HomeRepository homeRepository;
    private final String examCode;

    public HomeServiceImpl(HomeRepository homeRepository,
                           @Value("${passpace.certification-code}") String examCode) {
        this.homeRepository = homeRepository;
        this.examCode = examCode;
    }

    @Override
    public List<UpcomingExam> getUpcomingExams() {
        // TODO(한결): 구현
        try {
            return homeRepository.findUpcomingExams(examCode, 3);

        } catch (DataAccessException e) {
            // 추가된 코드: DB 조회 실패 원인을 실행 창에 기록
            log.warn("시험 일정 조회에 실패했습니다.", e);

            // 기존 반환문을 오류 처리 안에서 사용
            // 화면에서 '일정 준비 중'을 표시할 수 있도록 빈 목록 반환
            return List.of();
        }
    }
}
