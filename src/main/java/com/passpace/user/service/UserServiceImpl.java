package com.passpace.user.service;

import com.passpace.common.LoginUser;
import com.passpace.user.dto.ProfileForm;
import com.passpace.user.dto.SignUpForm;
import com.passpace.user.dto.UserViews.UserAccount;
import com.passpace.user.dto.UserViews.UserProfile;
import com.passpace.user.exception.DuplicateUserException;
import com.passpace.user.exception.LoginFailedException;
import com.passpace.user.repository.UserRepository;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;

/** [한결] 회원 기능 구현 */
@Service
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;
    /** 비밀번호는 BCrypt 해시로만 저장한다. 평문은 이 클래스 밖으로 나가지 않는다. */
    private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

    public UserServiceImpl(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public LoginUser signUp(SignUpForm form) {
        // TODO(한결): 구현
        if (userRepository.existsByLoginId(form.getLoginId())) {
            throw new DuplicateUserException(
                    "loginId", "이미 사용 중인 아이디입니다."
            );
    }
        if (userRepository.existsByEmail(form.getEmail(), null)) {
            throw new DuplicateUserException(
                    "email", "이미 사용 중인 이메일입니다."
            );
        }

        String passwordHash = passwordEncoder.encode(form.getPassword());

        Long userId = userRepository.insert(
                form.getLoginId(),
                passwordHash,
                form.getNickname(),
                form.getEmail(),
                form.getMajorType()
        );

        return new LoginUser(
                userId,
                form.getLoginId(),
                form.getNickname(),
                form.getMajorType()
        );
    }


    @Override
    public LoginUser login(String loginId, String rawPassword) {
        // TODO(한결): 구현
        UserAccount account = userRepository.findAccountByLoginId(loginId)
                .orElseThrow(LoginFailedException::new);

        if (!passwordEncoder.matches(rawPassword, account.passwordHash())) {
            throw new LoginFailedException();
        }

        return new LoginUser(
                account.userId(),
                account.loginId(),
                account.nickname(),
                account.majorType()
        );
    }

    @Override
    public UserProfile getProfile(Long userId) {
        // TODO(한결): 구현
        return userRepository.findProfile(userId)
                .orElseThrow(() ->
                        new IllegalArgumentException(
                                "회원 정보를 찾을 수 없습니다."
                        )
                );
    }

    @Override
    public LoginUser updateProfile(Long userId, ProfileForm form) {
        // TODO(한결): 구현
        UserProfile current = getProfile(userId);

        if (userRepository.existsByEmail(form.getEmail(), userId)) {
            throw new DuplicateUserException(
                    "email", "이미 사용 중인 이메일입니다."
            );
        }

        userRepository.updateProfile(
                userId,
                form.getNickname(),
                form.getEmail(),
                form.getMajorType()
        );

        return new LoginUser(
                current.userId(),
                current.loginId(),
                form.getNickname(),
                form.getMajorType()
        );
    }
}
