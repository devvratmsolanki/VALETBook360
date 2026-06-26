package com.valet.auth.domain;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * Maps the {@link Role} Java enum (uppercase constants) to/from the lowercase
 * PostgreSQL {@code user_role} enum values ({@code admin|manager|valet|driver}).
 *
 * <p>Why not {@code @Enumerated(STRING)}: that would persist/read the uppercase
 * constant name ("DRIVER"), which does NOT match the lowercase DB enum value and
 * blows up on read with "No enum constant ... driver". This converter is the
 * single source of truth for the DB case mapping.</p>
 *
 * <p>The JDBC URL carries {@code stringtype=unspecified} so the plain string
 * this converter produces is coerced into the native {@code user_role} enum by
 * PostgreSQL without a custom Hibernate type.</p>
 */
@Converter(autoApply = true)
public class RoleConverter implements AttributeConverter<Role, String> {

    @Override
    public String convertToDatabaseColumn(Role role) {
        return role == null ? null : role.wire();
    }

    @Override
    public Role convertToEntityAttribute(String dbValue) {
        return Role.fromWire(dbValue);
    }
}
