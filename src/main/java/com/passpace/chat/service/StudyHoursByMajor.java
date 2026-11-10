package com.passpace.chat.service;

import com.passpace.common.code.MajorType;

import java.util.List;
import java.util.Set;

/**
 * [동건] 과목별 기준시간의 전공 구분·자료 출처를 명시하는 레지스트리.
 *
 * 분리 원칙:
 *  - MAJOR / RELATED / NON_MAJOR 는 다른 집단이며 서로 합쳐 '전공자 평균'으로 표시하지 않는다.
 *  - 출처에서 전공 여부가 확인되지 않은 기록은 UNCLASSIFIED로 관리한다.
 *  - 현재 각 과목 50명 표본은 어느 집단에도 없다. '집단 평균'을 만들지 않는다.
 *  - 집단별 자료가 없을 때는 (선택된 집단의 평균이라고 가장하지 않고)
 *    원래의 공개 사례 기반 시간을 계산 시연용 대체값으로만 사용한다.
 *  - 개인 사전 이해도는 이 집단별 데이터와 독립이며 계산기에서 0.7/1/1.3을 적용한다.
 *
 * 장기적으로 용성 담당 데이터 수집 및 집단별 검증 DB와 통합할 때 교체할 모듈이다.
 */
public final class StudyHoursByMajor {
    private StudyHoursByMajor() { }

    public enum Qualification { IP_WRITTEN_2027, IP_PRACTICAL, SQLD }

    /** 작성자 중복 없이, 전공 여부가 원문에서 확인된 과목별 기록 사례 수. */
    public record Counts(int major, int related, int nonMajor, int unclassified,
                         int sameSyllabusMajor, int sameSyllabusNonMajor) { }

    /** 집단별 자료 선택 결과. reference는 '임시 계산자료'이며 실측 평균이 아님. */
    public record GroupBaseline(MajorType userMajor, String userMajorLabel,
                                String sourceGroup, int groupAuthors,
                                int matchingSyllabusGroupAuthors,
                                boolean sameGroupReference,
                                boolean fallback, String status, String warning,
                                Counts groupCounts,
                                StudyHoursEvidence.CertificateEstimate reference) { }

    /** 출처에서 확인된 작성자·과목 기록. majorType=null이면 전공 여부 미확인. */
    public record SourceAuthor(String sourceId, Qualification qualification, MajorType majorType,
                               boolean targetSyllabus, String url, Set<String> recordedSubjects) { }

    // 자료의 주요 출처는 기존 StudyHoursEvidence의 Observation에 보존된다.
    // 아래 목록은 같은 작성자를 과목 개수만큼 중복 계산하지 않기 위한 '작성자 단위' 인덱스.
    private static final List<SourceAuthor> AUTHORS = List.of(
            new SourceAuthor("IP_2026_01", Qualification.IP_WRITTEN_2027, MajorType.MAJOR, false,
                    "https://hwankr.tistory.com/entry/정보처리기사-필기-후기",
                    Set.of("소프트웨어 개발", "데이터베이스 구축", "프로그래밍 언어 활용", "정보시스템 구축관리")),
            new SourceAuthor("SQLD_2026_01", Qualification.SQLD, null, true,
                    "https://letsgomin.com/2727/",
                    Set.of("데이터 모델링의 이해", "SQL 기본 및 활용")),
            new SourceAuthor("SQLD_2025_01", Qualification.SQLD, null, true,
                    "https://bedenblog.tistory.com/273",
                    Set.of("데이터 모델링의 이해")),
            new SourceAuthor("IP_PRACTICAL_2025_01", Qualification.IP_PRACTICAL, null, true,
                    "https://kicdor.tistory.com/63",
                    Set.of("정보처리 실무"))
    );

    public static List<SourceAuthor> authors() { return AUTHORS; }

    public static Counts counts(Qualification qualification) {
        int major = 0, related = 0, nonMajor = 0, unknown = 0, matchingMajor = 0, matchingNonMajor = 0;
        for (SourceAuthor author : AUTHORS) {
            if (author.qualification() != qualification) continue;
            if (author.majorType() == null) unknown++;
            else if (author.majorType() == MajorType.MAJOR) {
                major++;
                if (author.targetSyllabus()) matchingMajor++;
            } else if (author.majorType() == MajorType.RELATED) related++;
            else if (author.majorType() == MajorType.NON_MAJOR) {
                nonMajor++;
                if (author.targetSyllabus()) matchingNonMajor++;
            }
        }
        return new Counts(major, related, nonMajor, unknown, matchingMajor, matchingNonMajor);
    }

    /** 해당 과목에 대해 지정 집단/출제기준의 직접 부분기록을 남긴 '서로 다른' 작성자 수. */
    public static int subjectAuthors(Qualification qualification, MajorType group,
                                     String subject, boolean requireSameSyllabus) {
        if (group == null || subject == null) return 0;
        return (int) AUTHORS.stream().filter(a -> a.qualification() == qualification
                && a.majorType() == group && a.recordedSubjects().contains(subject)
                && (!requireSameSyllabus || a.targetSyllabus()))
                .map(SourceAuthor::sourceId).distinct().count();
    }

    public static GroupBaseline resolve(Qualification qualification, MajorType group) {
        if (group == null)
            throw new IllegalArgumentException("전공 구분이 설정되지 않았습니다. 마이페이지에서 전공 여부를 먼저 선택하세요.");

        StudyHoursEvidence.CertificateEstimate reference = switch (qualification) {
            case IP_WRITTEN_2027 -> StudyHoursEvidence.informationProcessingWritten2027();
            case SQLD -> StudyHoursEvidence.sqld();
            case IP_PRACTICAL -> StudyHoursEvidence.informationProcessingPractical();
        };
        Counts counts = counts(qualification);
        int groupAuthors = switch (group) {
            case MAJOR -> counts.major();
            case RELATED -> counts.related();
            case NON_MAJOR -> counts.nonMajor();
        };
        int matched = switch (group) {
            case MAJOR -> counts.sameSyllabusMajor();
            case RELATED -> 0;
            case NON_MAJOR -> counts.sameSyllabusNonMajor();
        };

        String sourceGroup = qualification == Qualification.IP_WRITTEN_2027
                ? "MAJOR" : "UNCLASSIFIED";
        boolean sameGroup = switch (group) {
            case MAJOR -> "MAJOR".equals(sourceGroup);
            case RELATED -> "RELATED".equals(sourceGroup);
            case NON_MAJOR -> "NON_MAJOR".equals(sourceGroup);
        };
        boolean fallback = !sameGroup;
        String status = sameGroup ? "SAME_GROUP_LEGACY_PROVISIONAL"
                : "FALLBACK_NOT_GROUP_AVERAGE";

        String warning;
        if (sameGroup) {
            warning = "원문에서 전공자임이 명시된 이전(2026년) 출제기준 1명의 기록입니다. " +
                    "2027년 4과목에 임시 재분류했고 새 출제기준의 전공자 실측은 0명입니다. " +
                    "전공자 집단 평균이 아니며 과목별 50명 기준에 못 미칩니다.";
        } else if ("MAJOR".equals(sourceGroup)) {
            warning = "현재 " + group.getLabel() + " 과목별 확인 표본은 0명입니다. " +
                    "일정 계산이 가능하도록 다른 집단(전공자) 1명의 2026년 기록을 임시 참조합니다. " +
                    "이 시간은 " + group.getLabel() + " 평균이 아니며 2027년 출제기준 직접 기록도 아닙니다.";
        } else {
            warning = "현재 " + group.getLabel() + " 여부가 확인된 과목별 기록은 0명입니다. " +
                    "전공 구분이 확인되지 않은 공개 합격자 사례를 계산용 대체값으로 사용합니다. " +
                    "이 시간은 " + group.getLabel() + " 평균이 아닙니다.";
        }
        return new GroupBaseline(group, group.getLabel(), sourceGroup, groupAuthors,
                matched, sameGroup, fallback, status, warning, counts, reference);
    }
}
