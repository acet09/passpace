package com.passpace.user.withdrawal;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.JsonNode;
import io.swagger.v3.oas.annotations.media.Schema;

/** [한결] 회원탈퇴 전용 계약. 비밀번호는 응답이나 toString에 포함하지 않는다. */
public final class WithdrawalDtos {
    private WithdrawalDtos() { }

    public record Request(
            @Schema(description = "현재 계정의 비밀번호", accessMode = Schema.AccessMode.WRITE_ONLY,
                    requiredMode = Schema.RequiredMode.REQUIRED)
            String password,
            @Schema(description = "정확히 로그인아이디회원탈퇴 형식의 확인 문구", requiredMode = Schema.RequiredMode.REQUIRED)
            String confirmation,
            @Schema(description = "계정과 본인의 계획·기록·대화 영구 삭제 확인. 반드시 true",
                    requiredMode = Schema.RequiredMode.REQUIRED)
            boolean deletePersonalData) {
        @JsonCreator
        public static Request from(@JsonProperty("password") JsonNode password,
                                   @JsonProperty("confirmation") JsonNode confirmation,
                                   @JsonProperty("deletePersonalData") JsonNode deletePersonalData) {
            if (password == null || !password.isTextual() ||
                    confirmation == null || !confirmation.isTextual() ||
                    deletePersonalData == null || !deletePersonalData.isBoolean() ||
                    !deletePersonalData.booleanValue()) {
                throw new IllegalArgumentException("비밀번호·확인 문구와 영구 삭제 동의를 확인해 주세요.");
            }
            return new Request(password.textValue(), confirmation.textValue(), true);
        }

        @JsonAnySetter
        public void rejectUnknown(String name, JsonNode value) {
            throw new IllegalArgumentException("지원하지 않는 회원탈퇴 입력 항목입니다.");
        }

        @Override
        public String toString() {
            return "WithdrawalRequest[redacted]";
        }
    }

    public record Response(boolean withdrawn, boolean personalDataDeleted) { }
}
