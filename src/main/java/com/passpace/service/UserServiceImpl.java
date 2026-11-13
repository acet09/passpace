package com.passpace.service;

import com.passpace.dto.user.UpdateUserRequestDto;
import com.passpace.dto.user.UserViews.UserProfile;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.UserException;
import com.passpace.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** [한결] 마이페이지 회원정보 구현 */
@Service
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;

    public UserServiceImpl(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public UserProfile getProfile(Long userId) {
        return userRepository.findProfile(userId)
                .orElseThrow(() -> new UserException(ErrorCode.NOT_FOUND_USER));
    }

    @Override
    @Transactional
    public void updateProfile(Long userId, UpdateUserRequestDto request) {
        getProfile(userId);   // 없는 회원이면 여기서 404

        if (userRepository.existsByEmail(request.email(), userId)) {
            throw new UserException(ErrorCode.DUPLICATED_EMAIL);
        }

        userRepository.updateProfile(userId, request.nickname(), request.email(), request.majorType());
    }
}
