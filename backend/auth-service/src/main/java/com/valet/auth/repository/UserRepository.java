package com.valet.auth.repository;

import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserRepository extends JpaRepository<User, UUID> {

    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    boolean existsByRole(Role role);

    /** All users in a company, role-then-name ordered (company drilldown). */
    List<User> findByCompanyIdOrderByRoleAscNameAsc(UUID companyId);

    /** Paged: all users in a company, role-then-name ordered. */
    Page<User> findByCompanyIdOrderByRoleAscNameAsc(UUID companyId, Pageable pageable);

    /** Users in a company filtered to a single role (e.g. operators/drivers). */
    List<User> findByCompanyIdAndRoleOrderByNameAsc(UUID companyId, Role role);

    /** Users pinned to a location — used to unassign them when it's deleted. */
    List<User> findByLocationId(UUID locationId);

    /** All users in a company — used for the company cascade delete. */
    List<User> findByCompanyId(UUID companyId);

    /** Paged: users in a company filtered to a single role. */
    Page<User> findByCompanyIdAndRoleOrderByNameAsc(UUID companyId, Role role, Pageable pageable);

    /** Every user across every tenant, name-ordered (admin hierarchical list). */
    List<User> findAllByOrderByNameAsc();

    /** Paged: every user across every tenant, name-ordered. */
    Page<User> findAllByOrderByNameAsc(Pageable pageable);
}
