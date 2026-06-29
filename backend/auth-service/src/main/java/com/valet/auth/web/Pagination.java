package com.valet.auth.web;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;

import java.util.List;

/**
 * Header-based pagination for the admin list endpoints (GitHub / RFC&nbsp;5988
 * style).
 *
 * <p>The JSON body stays a bare array — identical to the un-paginated contract —
 * so existing clients keep parsing it unchanged. Page metadata travels in
 * response headers a paging-aware client can read:
 * <ul>
 *   <li>{@code X-Total-Count} — total matching rows across all pages</li>
 *   <li>{@code X-Total-Pages} — number of pages at the requested size</li>
 *   <li>{@code X-Page} — zero-based index of the returned page</li>
 *   <li>{@code X-Page-Size} — effective page size (after clamping)</li>
 *   <li>{@code X-Has-Next} — {@code true} when a further page exists</li>
 * </ul>
 *
 * <p>The {@link #DEFAULT_SIZE default size} is deliberately large so a client
 * that sends no {@code size} still receives the full working set (bounded, never
 * an unbounded table scan) — mirroring the existing {@code findTop500} cap on
 * transaction history. Clients that opt into smaller pages get real "load more"
 * paging via {@code X-Has-Next}.
 */
public final class Pagination {

    private Pagination() {
    }

    /** Page size used when the caller sends no (or a non-positive) {@code size}. */
    public static final int DEFAULT_SIZE = 500;

    /** Hard ceiling so a caller can't request an unbounded page. */
    public static final int MAX_SIZE = 500;

    /**
     * Build a clamped {@link PageRequest} from raw request params. Negative pages
     * floor to 0; a non-positive size falls back to {@link #DEFAULT_SIZE}; any
     * size is capped at {@link #MAX_SIZE}. Sort is left to the repository's
     * method-name ordering.
     */
    public static PageRequest of(int page, int size) {
        int p = Math.max(0, page);
        int s = size <= 0 ? DEFAULT_SIZE : Math.min(size, MAX_SIZE);
        return PageRequest.of(p, s);
    }

    /**
     * Wrap a {@link Page} as a {@code 200 OK} whose body is the page content
     * (bare array) and whose headers carry the pagination metadata.
     */
    public static <T> ResponseEntity<List<T>> body(Page<T> page) {
        HttpHeaders headers = new HttpHeaders();
        headers.add("X-Total-Count", Long.toString(page.getTotalElements()));
        headers.add("X-Total-Pages", Integer.toString(page.getTotalPages()));
        headers.add("X-Page", Integer.toString(page.getNumber()));
        headers.add("X-Page-Size", Integer.toString(page.getSize()));
        headers.add("X-Has-Next", Boolean.toString(page.hasNext()));
        return ResponseEntity.ok().headers(headers).body(page.getContent());
    }
}
