package com.passpace.error.exception;

import com.passpace.error.ErrorCode;
import lombok.Getter;

/**
 * 우리 서비스 예외의 부모. 모든 도메인 예외(AuthException·UserException 등)는 이 클래스를 상속한다.
 * GlobalExceptionHandler 는 이 부모 하나만 잡으면 모든 도메인 예외를 같은 모양으로 응답할 수 있다.
 * RuntimeException 을 상속하므로 throws 를 적지 않아도 되고, @Transactional 에서 롤백된다.
 */
@Getter
public abstract class BaseAppException extends RuntimeException {

    private final ErrorCode errorCode;
    private final String detail;

    protected BaseAppException(ErrorCode errorCode) {
        this(errorCode, null);
    }

    protected BaseAppException(ErrorCode errorCode, String detail) {
        super(errorCode.name());
        this.errorCode = errorCode;
        this.detail = detail;
    }
}
