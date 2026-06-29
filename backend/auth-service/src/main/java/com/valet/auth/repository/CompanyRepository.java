package com.valet.auth.repository;

import com.valet.auth.domain.Company;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface CompanyRepository extends JpaRepository<Company, UUID> {

    List<Company> findAllByOrderByCompanyNameAsc();

    /** Paged variant for the admin companies list (bounds the result set). */
    Page<Company> findAllByOrderByCompanyNameAsc(Pageable pageable);
}
