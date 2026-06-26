package com.valet.auth.repository;

import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
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

    /** Users in a company filtered to a single role (e.g. operators/drivers). */
    List<User> findByCompanyIdAndRoleOrderByNameAsc(UUID companyId, Role role);

    /** Every user across every tenant, name-ordered (admin hierarchical list). */
    List<User> findAllByOrderByNameAsc();
}
