package com.valet.auth.service;

import com.valet.auth.domain.Company;
import com.valet.auth.domain.Location;
import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
import com.valet.auth.dto.AdminUserResponse;
import com.valet.auth.dto.CompanyResponse;
import com.valet.auth.dto.CreateCompanyRequest;
import com.valet.auth.dto.CreateLocationRequest;
import com.valet.auth.dto.CreateStaffRequest;
import com.valet.auth.dto.LocationResponse;
import com.valet.auth.dto.UpdateLocationRequest;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.repository.CompanyRepository;
import com.valet.auth.repository.LocationRepository;
import com.valet.auth.repository.UserRepository;
import com.valet.auth.security.AuthPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Admin + company-owner management of tenants (companies), their locations, and
 * their staff. Lives in the auth service because tenants + identities share this
 * DB. The legacy surface it re-platforms:
 *
 * <ul>
 *   <li>{@code companyService.createCompanyWithOwner} — but TRANSACTIONAL: the
 *       company row + the owner {@code users} row commit or roll back together,
 *       replacing the legacy manual "delete the company if staff creation
 *       fails" compensation.</li>
 *   <li>{@code locationService} create/list/update.</li>
 *   <li>{@code userService}/{@code createStaff} — operator/driver provisioning.</li>
 * </ul>
 *
 * <p><b>Authorization model (enforced HERE, in addition to the security chain's
 * {@code hasAnyRole(ADMIN,MANAGER)} on these paths).</b>
 * <ul>
 *   <li>role {@code admin} → any company.</li>
 *   <li>role {@code manager} (UI "company") → ONLY its own {@code companyId}
 *       (taken from the JWT). Touching another company's id → 403
 *       {@code CROSS_TENANT}. A manager with no company → 403 {@code NO_TENANT}.</li>
 *   <li>{@code valet}/{@code driver} never reach here (chain returns 403), but
 *       the role guard below is defence-in-depth.</li>
 * </ul>
 * Create-company is admin-only; the chain restricts the POST and this service
 * re-checks.</p>
 */
@Service
public class CompanyAdminService {

    private final CompanyRepository companies;
    private final LocationRepository locations;
    private final UserRepository users;
    private final com.valet.auth.repository.KeySlotRepository keySlots;
    private final PasswordEncoder passwordEncoder;

    /** Upper bound on a single bulk key-slot generation (legacy MAX_BULK_SLOTS). */
    private static final int MAX_BULK_SLOTS = 500;

    public CompanyAdminService(CompanyRepository companies, LocationRepository locations,
                               UserRepository users,
                               com.valet.auth.repository.KeySlotRepository keySlots,
                               PasswordEncoder passwordEncoder) {
        this.companies = companies;
        this.locations = locations;
        this.users = users;
        this.keySlots = keySlots;
        this.passwordEncoder = passwordEncoder;
    }

    // =====================================================================
    //  Companies
    // =====================================================================

    /**
     * List companies. Admin → all (name-ordered); manager → just their own
     * (single-element list). A manager with no tenant → 403.
     */
    @Transactional(readOnly = true)
    public List<CompanyResponse> listCompanies(AuthPrincipal caller) {
        if (isAdmin(caller)) {
            return companies.findAllByOrderByCompanyNameAsc().stream()
                    .map(CompanyResponse::from)
                    .toList();
        }
        // Manager: their own company only.
        Company own = requireOwnCompany(caller);
        return List.of(CompanyResponse.from(own));
    }

    /** Single company overview. Admin → any; manager → own only (else 403). */
    @Transactional(readOnly = true)
    public CompanyResponse getCompany(AuthPrincipal caller, UUID companyId) {
        Company company = loadCompanyAuthorized(caller, companyId);
        return CompanyResponse.from(company);
    }

    /**
     * ADMIN-only create-company-with-owner. Inserts the {@code valet_companies}
     * row and the owner {@code users} row (role {@code manager}) in a single
     * transaction — if the owner insert fails (e.g. duplicate email) the whole
     * thing rolls back, so no orphan company is left behind and the admin can
     * retry the same email. Returns the created company.
     */
    @Transactional
    public CompanyResponse createCompanyWithOwner(AuthPrincipal caller, CreateCompanyRequest req) {
        if (!isAdmin(caller)) {
            throw ServiceException.forbidden("INSUFFICIENT_PERMISSIONS",
                    "Only an administrator can create a company.");
        }

        String ownerEmail = normalizeEmail(req.email());
        // Fail fast with a friendly message rather than relying on the DB unique
        // index throwing mid-transaction (still safe either way — the tx rolls back).
        if (users.existsByEmail(ownerEmail)) {
            throw ServiceException.conflict("EMAIL_TAKEN",
                    "An account with that email already exists.");
        }

        UUID companyId = UUID.randomUUID();
        Company company = new Company(
                companyId,
                req.companyName().trim(),
                req.ownerName() == null ? null : req.ownerName().trim(),
                req.phone() == null ? null : req.phone().trim(),
                ownerEmail
        );
        // save() may return a managed merge-copy for an assigned-id entity; use it
        // so the @PrePersist-populated createdAt is reflected in the response.
        company = companies.save(company);

        // Owner login: role manager (UI "company"), bound to the new company.
        User owner = new User(
                UUID.randomUUID(),
                ownerEmail,
                passwordEncoder.encode(req.password()),
                Role.MANAGER,
                companyId,
                null,
                req.ownerName() == null || req.ownerName().isBlank()
                        ? req.companyName().trim() + " Owner"
                        : req.ownerName().trim(),
                true
        );
        // If this throws (e.g. a race on the unique email index), the @Transactional
        // boundary rolls back the company insert above — no orphan row.
        users.save(owner);

        return CompanyResponse.from(company);
    }

    // =====================================================================
    //  Locations
    // =====================================================================

    /** Locations for a company. Admin → any; manager → own only. */
    @Transactional(readOnly = true)
    public List<LocationResponse> listLocations(AuthPrincipal caller, UUID companyId) {
        loadCompanyAuthorized(caller, companyId); // authz + existence
        return locations.findByCompanyIdOrderByNameAsc(companyId).stream()
                .map(LocationResponse::from)
                .toList();
    }

    /** Create a location under a company. Admin → any; manager → own only. */
    @Transactional
    public LocationResponse createLocation(AuthPrincipal caller, UUID companyId,
                                           CreateLocationRequest req) {
        loadCompanyAuthorized(caller, companyId);
        Location loc = new Location(
                UUID.randomUUID(),
                companyId,
                req.name().trim(),
                trimToNull(req.address()),
                trimToNull(req.city()),
                trimToNull(req.state()),
                trimToNull(req.country()),
                req.keyCapacity()
        );
        loc = locations.save(loc);
        return LocationResponse.from(loc);
    }

    /**
     * Edit a location. The owning company is derived from the stored row (never
     * the request), then authorized: admin → any; manager → only if the location
     * belongs to their company.
     */
    @Transactional
    public LocationResponse updateLocation(AuthPrincipal caller, UUID locationId,
                                           UpdateLocationRequest req) {
        Location loc = locations.findById(locationId)
                .orElseThrow(() -> ServiceException.notFound("LOCATION_NOT_FOUND",
                        "That location could not be found."));
        // Authorize against the location's OWNING company.
        loadCompanyAuthorized(caller, loc.getCompanyId());

        loc.setName(req.name().trim());
        loc.setAddress(trimToNull(req.address()));
        loc.setCity(trimToNull(req.city()));
        loc.setState(trimToNull(req.state()));
        loc.setCountry(trimToNull(req.country()));
        loc.setKeyCapacity(req.keyCapacity());
        locations.save(loc);
        return LocationResponse.from(loc);
    }

    /**
     * ADMIN-only: every location across every company, each carrying its
     * {@code companyName} for the grouped "all locations" admin view.
     */
    @Transactional(readOnly = true)
    public List<LocationResponse> listAllLocations(AuthPrincipal caller) {
        requireAdmin(caller);
        Map<UUID, String> names = companyNameIndex();
        return locations.findAllByOrderByNameAsc().stream()
                .map(l -> LocationResponse.from(l, names.get(l.getCompanyId())))
                .toList();
    }

    // =====================================================================
    //  Key slots (Location Detail → Key Slots tab)
    // =====================================================================

    /** All custom key slots for a location. Admin → any; manager → own only. */
    @Transactional(readOnly = true)
    public List<com.valet.auth.dto.KeySlotResponse> listSlots(AuthPrincipal caller,
                                                              UUID locationId) {
        authorizeLocation(caller, locationId);
        return keySlots.findByLocationIdOrderBySortOrderAscSlotNameAsc(locationId)
                .stream().map(com.valet.auth.dto.KeySlotResponse::from).toList();
    }

    /**
     * Bulk-generate slots named {@code <prefix><startFrom + i>} for i in
     * [0, count). Mirrors the legacy generator: count is clamped to [0, 500];
     * each slot's {@code sortOrder} is {@code startFrom + i} so display order
     * follows the sequence. Admin → any; manager → own only.
     */
    @Transactional
    public List<com.valet.auth.dto.KeySlotResponse> bulkGenerateSlots(
            AuthPrincipal caller, UUID locationId,
            com.valet.auth.dto.BulkGenerateSlotsRequest req) {
        authorizeLocation(caller, locationId);

        int count = Math.max(0, Math.min(MAX_BULK_SLOTS, req.count()));
        if (count == 0) {
            return List.of();
        }
        String prefix = req.prefix() == null ? "" : req.prefix().trim();
        int start = Math.max(0, req.startFrom());

        List<com.valet.auth.domain.KeySlot> toSave = new java.util.ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            int seq = start + i;
            toSave.add(new com.valet.auth.domain.KeySlot(
                    UUID.randomUUID(), locationId, prefix + seq, seq));
        }
        return keySlots.saveAll(toSave).stream()
                .map(com.valet.auth.dto.KeySlotResponse::from).toList();
    }

    /** Rename one slot. Authorized against the slot's location's company. */
    @Transactional
    public com.valet.auth.dto.KeySlotResponse renameSlot(AuthPrincipal caller, UUID slotId,
                                                         String slotName) {
        com.valet.auth.domain.KeySlot slot = loadSlotAuthorized(caller, slotId);
        slot.setSlotName(slotName.trim());
        keySlots.save(slot);
        return com.valet.auth.dto.KeySlotResponse.from(slot);
    }

    /** Delete one slot. Authorized against the slot's location's company. */
    @Transactional
    public void deleteSlot(AuthPrincipal caller, UUID slotId) {
        com.valet.auth.domain.KeySlot slot = loadSlotAuthorized(caller, slotId);
        keySlots.delete(slot);
    }

    /** Load a location, then authorize the caller against its owning company. */
    private void authorizeLocation(AuthPrincipal caller, UUID locationId) {
        Location loc = locations.findById(locationId)
                .orElseThrow(() -> ServiceException.notFound("LOCATION_NOT_FOUND",
                        "That location could not be found."));
        loadCompanyAuthorized(caller, loc.getCompanyId());
    }

    /** Load a slot, then authorize the caller against its location's company. */
    private com.valet.auth.domain.KeySlot loadSlotAuthorized(AuthPrincipal caller, UUID slotId) {
        com.valet.auth.domain.KeySlot slot = keySlots.findById(slotId)
                .orElseThrow(() -> ServiceException.notFound("SLOT_NOT_FOUND",
                        "That key slot could not be found."));
        authorizeLocation(caller, slot.getLocationId());
        return slot;
    }

    // =====================================================================
    //  Users / staff
    // =====================================================================

    /**
     * List users for a company, optionally filtered by role (operators=valet,
     * drivers=driver, owners=manager). Admin → any; manager → own only.
     */
    @Transactional(readOnly = true)
    public List<AdminUserResponse> listCompanyUsers(AuthPrincipal caller, UUID companyId,
                                                    Role roleFilter) {
        loadCompanyAuthorized(caller, companyId);
        List<User> found = (roleFilter == null)
                ? users.findByCompanyIdOrderByRoleAscNameAsc(companyId)
                : users.findByCompanyIdAndRoleOrderByNameAsc(companyId, roleFilter);
        return found.stream().map(AdminUserResponse::from).toList();
    }

    /**
     * Create an operator ({@code valet}) or driver ({@code driver}) login under a
     * company. Admin → any company; manager → own only. The role MUST be
     * valet|driver — neither admin nor manager may be minted here (a manager
     * cannot escalate by creating another manager/admin). The company comes from
     * the path; {@code locationId} (optional) must belong to that company.
     */
    @Transactional
    public AdminUserResponse createStaff(AuthPrincipal caller, UUID companyId,
                                         CreateStaffRequest req) {
        loadCompanyAuthorized(caller, companyId);

        Role role = req.role();
        if (role != Role.VALET && role != Role.DRIVER) {
            throw ServiceException.badRequest("INVALID_STAFF_ROLE",
                    "Staff role must be 'valet' (operator) or 'driver'.");
        }

        // If a location is supplied it must belong to THIS company (no cross-tenant
        // pinning).
        if (req.locationId() != null) {
            Location loc = locations.findById(req.locationId())
                    .orElseThrow(() -> ServiceException.badRequest("LOCATION_NOT_FOUND",
                            "That location could not be found."));
            if (!Objects.equals(loc.getCompanyId(), companyId)) {
                throw ServiceException.forbidden("CROSS_TENANT",
                        "That location belongs to another company.");
            }
        }

        String email = normalizeEmail(req.email());
        if (users.existsByEmail(email)) {
            throw ServiceException.conflict("EMAIL_TAKEN",
                    "An account with that email already exists.");
        }

        User staff = new User(
                UUID.randomUUID(),
                email,
                passwordEncoder.encode(req.password()),
                role,
                companyId,
                req.locationId(),
                req.name().trim(),
                true
        );
        staff = users.save(staff);
        return AdminUserResponse.from(staff);
    }

    /**
     * ADMIN-only hierarchical user list: every user across every tenant, each
     * carrying its {@code companyName} so the Flutter Users screen can bucket
     * them under their company.
     */
    @Transactional(readOnly = true)
    public List<AdminUserResponse> listAllUsers(AuthPrincipal caller) {
        requireAdmin(caller);
        Map<UUID, String> names = companyNameIndex();
        return users.findAllByOrderByNameAsc().stream()
                .map(u -> AdminUserResponse.from(u,
                        u.getCompanyId() == null ? null : names.get(u.getCompanyId())))
                .toList();
    }

    // =====================================================================
    //  Authorization + helpers
    // =====================================================================

    private static boolean isAdmin(AuthPrincipal caller) {
        return "admin".equalsIgnoreCase(caller.role());
    }

    private static boolean isManager(AuthPrincipal caller) {
        return "manager".equalsIgnoreCase(caller.role());
    }

    private void requireAdmin(AuthPrincipal caller) {
        if (!isAdmin(caller)) {
            throw ServiceException.forbidden("INSUFFICIENT_PERMISSIONS",
                    "This action is only available to administrators.");
        }
    }

    /**
     * Load a company and authorize the caller for it:
     * admin → any; manager → must equal their own JWT company; everyone else 403.
     * A missing company is 404.
     */
    private Company loadCompanyAuthorized(AuthPrincipal caller, UUID companyId) {
        if (isManager(caller)) {
            if (caller.companyId() == null) {
                throw ServiceException.forbidden("NO_TENANT",
                        "Your account is not linked to a company.");
            }
            if (!Objects.equals(caller.companyId(), companyId)) {
                throw ServiceException.forbidden("CROSS_TENANT",
                        "You can only manage your own company.");
            }
        } else if (!isAdmin(caller)) {
            // Defence in depth — the security chain already blocks valet/driver.
            throw ServiceException.forbidden("INSUFFICIENT_PERMISSIONS",
                    "You don't have permission to manage companies.");
        }
        return companies.findById(companyId)
                .orElseThrow(() -> ServiceException.notFound("COMPANY_NOT_FOUND",
                        "That company could not be found."));
    }

    /** A manager's own company, or 403 if they have none / it's missing. */
    private Company requireOwnCompany(AuthPrincipal caller) {
        if (caller.companyId() == null) {
            throw ServiceException.forbidden("NO_TENANT",
                    "Your account is not linked to a company.");
        }
        return companies.findById(caller.companyId())
                .orElseThrow(() -> ServiceException.notFound("COMPANY_NOT_FOUND",
                        "Your company record could not be found."));
    }

    private Map<UUID, String> companyNameIndex() {
        return companies.findAll().stream()
                .collect(Collectors.toMap(Company::getId, Company::getCompanyName,
                        (a, b) -> a, HashMap::new));
    }

    private static String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase();
    }

    private static String trimToNull(String s) {
        if (s == null) {
            return null;
        }
        String t = s.trim();
        return t.isEmpty() ? null : t;
    }
}
