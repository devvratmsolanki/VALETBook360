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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
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
    private final com.valet.auth.repository.ContractRepository contracts;
    private final PasswordEncoder passwordEncoder;

    /** Upper bound on a single bulk key-slot generation (legacy MAX_BULK_SLOTS). */
    private static final int MAX_BULK_SLOTS = 500;

    /**
     * Hard ceiling on a location's key capacity. Mirrors {@code @Max(10_000)} on
     * the create/update DTOs, but re-enforced here so a pre-existing oversized
     * row (persisted before that bound existed) can't make
     * {@link #operatorKeySlots} stream billions of slot strings → OOM.
     */
    private static final int MAX_KEY_CAPACITY = 10_000;

    /** Hard ceiling on a bulk slot starting sequence (mirrors the DTO's @Max). */
    private static final int MAX_SLOT_START = 1_000_000;

    public CompanyAdminService(CompanyRepository companies, LocationRepository locations,
                               UserRepository users,
                               com.valet.auth.repository.KeySlotRepository keySlots,
                               com.valet.auth.repository.ContractRepository contracts,
                               PasswordEncoder passwordEncoder) {
        this.companies = companies;
        this.locations = locations;
        this.users = users;
        this.keySlots = keySlots;
        this.contracts = contracts;
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

    /**
     * Paged companies. Admin → all (name-ordered, bounded by {@code pageable});
     * manager → their single company as a one-element page.
     */
    @Transactional(readOnly = true)
    public Page<CompanyResponse> listCompanies(AuthPrincipal caller, Pageable pageable) {
        if (isAdmin(caller)) {
            return companies.findAllByOrderByCompanyNameAsc(pageable)
                    .map(CompanyResponse::from);
        }
        Company own = requireOwnCompany(caller);
        return new PageImpl<>(List.of(CompanyResponse.from(own)), pageable, 1);
    }

    /** Single company overview. Admin → any; manager → own only (else 403). */
    @Transactional(readOnly = true)
    public CompanyResponse getCompany(AuthPrincipal caller, UUID companyId) {
        Company company = loadCompanyAuthorized(caller, companyId);
        return CompanyResponse.from(company);
    }

    /**
     * ADMIN-only hard delete of a company and everything it owns, in one
     * transaction: every location's key slots, the locations, the company's
     * contracts, and all its user accounts (including the owner), then the
     * company row. Destructive and irreversible — the controller restricts this
     * to ADMIN and the UI must confirm. A caller may not delete the company they
     * belong to (admins are tenant-less, so this only guards a misconfigured
     * tenant-bound admin). Historical {@code valet_transactions} in the core DB
     * keep their denormalized company/location ids (no cross-service FK).
     */
    @Transactional
    public void deleteCompany(AuthPrincipal caller, UUID companyId) {
        requireAdmin(caller);
        Company company = companies.findById(companyId)
                .orElseThrow(() -> ServiceException.notFound("COMPANY_NOT_FOUND",
                        "That company could not be found."));
        if (companyId.equals(caller.companyId())) {
            throw ServiceException.conflict("CANNOT_DELETE_OWN_COMPANY",
                    "You can't delete the company your own account belongs to.");
        }

        List<Location> locs = locations.findByCompanyIdOrderByNameAsc(companyId);
        for (Location loc : locs) {
            keySlots.deleteAll(
                    keySlots.findByLocationIdOrderBySortOrderAscSlotNameAsc(loc.getId()));
        }
        locations.deleteAll(locs);
        contracts.deleteAll(contracts.findByCompanyIdOrderByCreatedAtDesc(companyId));
        users.deleteAll(users.findByCompanyId(companyId));
        companies.delete(company);
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
     * Delete a location. Admin → any; manager → own only (authorized against the
     * location's owning company). Cascade within the auth DB: its key slots are
     * removed and any users pinned to it are unassigned (location_id → null) so
     * no row is left dangling. Historical {@code valet_transactions} in the core
     * DB keep their denormalized {@code location_id} snapshot (no cross-service
     * FK) — they are not affected.
     */
    @Transactional
    public void deleteLocation(AuthPrincipal caller, UUID locationId) {
        Location loc = locations.findById(locationId)
                .orElseThrow(() -> ServiceException.notFound("LOCATION_NOT_FOUND",
                        "That location could not be found."));
        loadCompanyAuthorized(caller, loc.getCompanyId());

        // Unassign anyone pinned to this location.
        List<User> pinned = users.findByLocationId(locationId);
        for (User u : pinned) {
            u.setLocationId(null);
        }
        if (!pinned.isEmpty()) {
            users.saveAll(pinned);
        }
        // Remove the location's key slots, then the location itself.
        keySlots.deleteAll(
                keySlots.findByLocationIdOrderBySortOrderAscSlotNameAsc(locationId));
        locations.delete(loc);
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

    /** ADMIN-only paged variant of {@link #listAllLocations(AuthPrincipal)}. */
    @Transactional(readOnly = true)
    public Page<LocationResponse> listAllLocations(AuthPrincipal caller, Pageable pageable) {
        requireAdmin(caller);
        Map<UUID, String> names = companyNameIndex();
        return locations.findAllByOrderByNameAsc(pageable)
                .map(l -> LocationResponse.from(l, names.get(l.getCompanyId())));
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
     * The effective key-slot pool for the CALLER'S OWN location (from the JWT),
     * for the operator panel. Operators (valet) can't reach the admin/manager
     * slot endpoints, so this is the single read-only projection they get,
     * scoped to their own location — no cross-tenant exposure. Returns the custom
     * slot names (ordered) if the company set them up, otherwise the generated
     * sequence "1".."keyCapacity".
     */
    @Transactional(readOnly = true)
    public com.valet.auth.dto.OperatorKeySlotsResponse operatorKeySlots(AuthPrincipal caller) {
        // Floor-staff only. The security chain leaves /key-slots at
        // anyRequest().authenticated(), so without this a driver token (which can
        // carry a locationId) could read its location's slot pool. Drivers have
        // no use for it — exclude them explicitly (defence in depth).
        if ("driver".equalsIgnoreCase(caller.role())) {
            throw ServiceException.forbidden("NOT_AN_OPERATOR",
                    "Key slots are only available to floor staff.");
        }
        UUID locationId = caller.locationId();
        if (locationId == null) {
            throw ServiceException.badRequest("NO_LOCATION",
                    "Your account isn't assigned to a location, so no key slots are available.");
        }
        Location loc = locations.findById(locationId)
                .orElseThrow(() -> ServiceException.notFound("LOCATION_NOT_FOUND",
                        "Your assigned location could not be found."));
        List<com.valet.auth.domain.KeySlot> custom =
                keySlots.findByLocationIdOrderBySortOrderAscSlotNameAsc(locationId);
        List<String> names;
        if (!custom.isEmpty()) {
            names = custom.stream()
                    .map(com.valet.auth.domain.KeySlot::getSlotName)
                    .toList();
        } else {
            // Clamp BEFORE the IntStream: a row whose key_capacity predates the
            // @Max(10_000) DTO bound (or was set via some other path) must not be
            // able to allocate billions of strings here and OOM the service.
            int cap = Math.min(MAX_KEY_CAPACITY, Math.max(0, loc.getKeyCapacity()));
            names = java.util.stream.IntStream.rangeClosed(1, cap)
                    .mapToObj(Integer::toString)
                    .toList();
        }
        return new com.valet.auth.dto.OperatorKeySlotsResponse(
                locationId, loc.getKeyCapacity(), names);
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

        // Bulletproof bounds re-enforced at the service layer (the DTO @Min/@Max
        // already guard the validated path; this also protects any non-validated
        // caller and a hostile body that somehow slips a larger value through).
        int count = Math.max(0, Math.min(MAX_BULK_SLOTS, req.count()));
        if (count == 0) {
            return List.of();
        }
        String prefix = req.prefix() == null ? "" : req.prefix().trim();
        int start = Math.min(MAX_SLOT_START, Math.max(0, req.startFrom()));

        // Reject up-front if any generated name collides with an existing slot at
        // this location (the ux_slot_name_per_location unique constraint would
        // otherwise surface as a generic 409 CONFLICT). Batch names are unique by
        // construction (seq strictly increments), so only existing rows can clash.
        List<String> names = new java.util.ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            names.add(prefix + (start + i));
        }
        List<String> taken = keySlots.findByLocationIdAndSlotNameIn(locationId, names)
                .stream().map(com.valet.auth.domain.KeySlot::getSlotName).toList();
        if (!taken.isEmpty()) {
            throw ServiceException.conflict("SLOT_NAME_TAKEN",
                    "One or more of those slot names already exist at this location: "
                            + String.join(", ", taken) + ".");
        }

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
        String trimmed = slotName.trim();
        // Reject a clash with another slot at the same location before the
        // ux_slot_name_per_location unique constraint turns it into a generic 409.
        if (keySlots.existsByLocationIdAndSlotNameAndIdNot(
                slot.getLocationId(), trimmed, slot.getId())) {
            throw ServiceException.conflict("SLOT_NAME_TAKEN",
                    "Another slot at this location already uses the name '" + trimmed + "'.");
        }
        slot.setSlotName(trimmed);
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
    //  Contracts (company panel → Contracts tab)
    // =====================================================================

    /** Contracts for a company, newest first, enriched with location info. */
    @Transactional(readOnly = true)
    public List<com.valet.auth.dto.ContractResponse> listContracts(AuthPrincipal caller,
                                                                   UUID companyId) {
        loadCompanyAuthorized(caller, companyId);
        Map<UUID, Location> locIndex = locations.findByCompanyIdOrderByNameAsc(companyId)
                .stream().collect(java.util.stream.Collectors.toMap(Location::getId, l -> l));
        return contracts.findByCompanyIdOrderByCreatedAtDesc(companyId).stream()
                .map(c -> {
                    Location l = c.getLocationId() == null ? null : locIndex.get(c.getLocationId());
                    return com.valet.auth.dto.ContractResponse.from(c,
                            l == null ? null : l.getName(),
                            l == null ? null : l.getCity(),
                            l == null ? null : l.getState());
                })
                .toList();
    }

    /** Paged variant of {@link #listContracts(AuthPrincipal, UUID)}. */
    @Transactional(readOnly = true)
    public Page<com.valet.auth.dto.ContractResponse> listContracts(AuthPrincipal caller,
                                                                   UUID companyId, Pageable pageable) {
        loadCompanyAuthorized(caller, companyId);
        Map<UUID, Location> locIndex = locations.findByCompanyIdOrderByNameAsc(companyId)
                .stream().collect(Collectors.toMap(Location::getId, l -> l));
        return contracts.findByCompanyIdOrderByCreatedAtDesc(companyId, pageable)
                .map(c -> {
                    Location l = c.getLocationId() == null ? null : locIndex.get(c.getLocationId());
                    return com.valet.auth.dto.ContractResponse.from(c,
                            l == null ? null : l.getName(),
                            l == null ? null : l.getCity(),
                            l == null ? null : l.getState());
                });
    }

    /** Create a contract under a company. Admin → any; manager → own only. */
    @Transactional
    public com.valet.auth.dto.ContractResponse createContract(AuthPrincipal caller,
            UUID companyId, com.valet.auth.dto.CreateContractRequest req) {
        loadCompanyAuthorized(caller, companyId);
        // If a location is supplied, it must belong to THIS company.
        if (req.locationId() != null) {
            Location loc = locations.findById(req.locationId())
                    .orElseThrow(() -> ServiceException.notFound("LOCATION_NOT_FOUND",
                            "That location could not be found."));
            if (!companyId.equals(loc.getCompanyId())) {
                throw ServiceException.forbidden("CROSS_TENANT",
                        "That location belongs to another company.");
            }
        }
        com.valet.auth.domain.Contract c = new com.valet.auth.domain.Contract(
                UUID.randomUUID(), companyId, req.locationId(), req.name().trim(),
                trimToNull(req.type()), trimToNull(req.status()),
                req.active() == null || req.active(),
                trimToNull(req.managerName()), trimToNull(req.managerPhone()),
                trimToNull(req.managerEmail()));
        contracts.save(c);
        Location l = req.locationId() == null ? null
                : locations.findById(req.locationId()).orElse(null);
        return com.valet.auth.dto.ContractResponse.from(c,
                l == null ? null : l.getName(),
                l == null ? null : l.getCity(),
                l == null ? null : l.getState());
    }

    // =====================================================================
    //  User lifecycle (activate / deactivate / delete) — company panel
    // =====================================================================

    /**
     * Toggle a user's active flag. Authorized against the user's own company.
     * Only {@code valet}/{@code driver} accounts may be toggled here (a manager
     * cannot disable another manager/admin).
     */
    @Transactional
    public AdminUserResponse setUserActive(AuthPrincipal caller, UUID userId, boolean active) {
        User u = loadStaffUserAuthorized(caller, userId);
        u.setActive(active);
        users.save(u);
        return AdminUserResponse.from(u);
    }

    /**
     * Delete a {@code valet}/{@code driver} user. Authorized against the user's
     * company; managers/admins cannot be deleted here, nor can the caller delete
     * themselves. Historical transaction rows in the (separate) core DB keep the
     * now-dangling driver id as audit data — there is no cross-DB FK to break.
     */
    @Transactional
    public void deleteUser(AuthPrincipal caller, UUID userId) {
        User u = loadStaffUserAuthorized(caller, userId);
        if (userId.equals(caller.userId())) {
            throw ServiceException.conflict("CANNOT_DELETE_SELF",
                    "You can't delete your own account.");
        }
        users.delete(u);
    }

    /**
     * Load a user, assert they belong to a company the caller may manage, and
     * that they are a staff account (valet/driver) — never a manager/admin.
     */
    private User loadStaffUserAuthorized(AuthPrincipal caller, UUID userId) {
        User u = users.findById(userId)
                .orElseThrow(() -> ServiceException.notFound("USER_NOT_FOUND",
                        "That user could not be found."));
        if (u.getCompanyId() == null) {
            throw ServiceException.forbidden("CROSS_TENANT",
                    "That user is not part of a manageable company.");
        }
        loadCompanyAuthorized(caller, u.getCompanyId());
        if (u.getRole() != Role.VALET && u.getRole() != Role.DRIVER) {
            throw ServiceException.forbidden("PROTECTED_ACCOUNT",
                    "Only operator and driver accounts can be changed here.");
        }
        return u;
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

    /** Paged variant of {@link #listCompanyUsers(AuthPrincipal, UUID, Role)}. */
    @Transactional(readOnly = true)
    public Page<AdminUserResponse> listCompanyUsers(AuthPrincipal caller, UUID companyId,
                                                    Role roleFilter, Pageable pageable) {
        loadCompanyAuthorized(caller, companyId);
        Page<User> found = (roleFilter == null)
                ? users.findByCompanyIdOrderByRoleAscNameAsc(companyId, pageable)
                : users.findByCompanyIdAndRoleOrderByNameAsc(companyId, roleFilter, pageable);
        return found.map(AdminUserResponse::from);
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
     * Edit a staff member's name, role (valet|driver) and location assignment.
     * Authorized identically to {@link #setUserActive}/{@link #deleteUser}: the
     * target must be a valet/driver in a company the caller manages (admin → any;
     * manager → own only). A supplied {@code locationId} must belong to that same
     * company; {@code null} unassigns. Email/password are not editable here.
     */
    @Transactional
    public AdminUserResponse updateStaff(AuthPrincipal caller, UUID userId,
                                         com.valet.auth.dto.UpdateStaffRequest req) {
        User u = loadStaffUserAuthorized(caller, userId);

        Role role = req.role();
        if (role != Role.VALET && role != Role.DRIVER) {
            throw ServiceException.badRequest("INVALID_STAFF_ROLE",
                    "Staff role must be 'valet' (operator) or 'driver'.");
        }

        // A (re)assigned location must belong to THIS user's company.
        if (req.locationId() != null) {
            Location loc = locations.findById(req.locationId())
                    .orElseThrow(() -> ServiceException.badRequest("LOCATION_NOT_FOUND",
                            "That location could not be found."));
            if (!Objects.equals(loc.getCompanyId(), u.getCompanyId())) {
                throw ServiceException.forbidden("CROSS_TENANT",
                        "That location belongs to another company.");
            }
        }

        u.setName(req.name().trim());
        u.setRole(role);
        u.setLocationId(req.locationId());
        users.save(u);
        return AdminUserResponse.from(u);
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

    /** ADMIN-only paged variant of {@link #listAllUsers(AuthPrincipal)}. */
    @Transactional(readOnly = true)
    public Page<AdminUserResponse> listAllUsers(AuthPrincipal caller, Pageable pageable) {
        requireAdmin(caller);
        Map<UUID, String> names = companyNameIndex();
        return users.findAllByOrderByNameAsc(pageable)
                .map(u -> AdminUserResponse.from(u,
                        u.getCompanyId() == null ? null : names.get(u.getCompanyId())));
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
