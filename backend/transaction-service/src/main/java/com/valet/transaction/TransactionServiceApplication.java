package com.valet.transaction;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Vālet transaction + driver microservice.
 *
 * <p>Owns the canonical valet lifecycle state machine and the driver-facing
 * mission endpoints. This is a JWT <em>resource server</em>: it validates the
 * HS256 access tokens issued by the auth-service but never mints its own.</p>
 */
@SpringBootApplication
public class TransactionServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(TransactionServiceApplication.class, args);
    }
}
