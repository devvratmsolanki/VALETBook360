package com.valet.auth.repository;

import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

/**
 * Read-only projection over the {@code users} table used by the operator's
 * driver picker. Lives alongside {@link UserRepository} but is intentionally a
 * separate, narrowly-scoped repository so the directory query patterns stay
 * isolated from the identity/credentials access in the auth flow.
 *
 * <p>Every query here is tenant-anchored by {@code companyId} — there is no
 * "list all drivers" method, by design. Only active drivers surface in the
 * picker; a deactivated account should not be dispatchable.</p>
 */
public interface DriverDirectoryRepository extends JpaRepository<User, UUID> {

    /**
     * Active users with the given role in the given company, name-ordered for a
     * stable, human-friendly picker. The repository never widens scope beyond
     * the supplied companyId — the caller derives that from the JWT, never the
     * request body.
     */
    List<User> findByRoleAndCompanyIdAndActiveTrueOrderByNameAsc(Role role, UUID companyId);
}
