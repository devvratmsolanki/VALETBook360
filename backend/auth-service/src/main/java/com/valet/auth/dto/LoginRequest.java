package com.valet.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record LoginRequest(
        @NotBlank @Email
        String email,

        // Bounded so an absurdly long password can't be used to force expensive
        // password-hash work (a cheap DoS vector). Real passwords are well under.
        @NotBlank @Size(max = 128)
        String password
) {
}
