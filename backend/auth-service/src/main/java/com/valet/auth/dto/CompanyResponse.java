package com.valet.auth.dto;

import com.valet.auth.domain.Company;

import java.time.Instant;
import java.util.UUID;

/**
 * Company projection for the admin/company panels. camelCase JSON; never leaks
 * staff credentials. {@code valetCompanyId} is intentionally the same as
 * {@code id} (the legacy locations FK column name) — callers reference a company
 * by {@code id}.
 */
public record CompanyResponse(
        UUID id,
        String companyName,
        String ownerName,
        String phone,
        String email,
        Instant createdAt
) {
    public static CompanyResponse from(Company c) {
        return new CompanyResponse(
                c.getId(),
                c.getCompanyName(),
                c.getOwnerName(),
                c.getPhone(),
                c.getEmail(),
                c.getCreatedAt()
        );
    }
}
