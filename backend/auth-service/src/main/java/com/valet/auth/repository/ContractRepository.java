package com.valet.auth.repository;

import com.valet.auth.domain.Contract;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ContractRepository extends JpaRepository<Contract, UUID> {

    /** Contracts for a company, newest first. */
    List<Contract> findByCompanyIdOrderByCreatedAtDesc(UUID companyId);

    /** Paged: contracts for a company, newest first. */
    Page<Contract> findByCompanyIdOrderByCreatedAtDesc(UUID companyId, Pageable pageable);
}
