package com.valet.transaction.domain;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * Maps {@link ValetStatus} to/from its snake_case {@code valet_status} enum
 * value in Postgres. With {@code stringtype=unspecified} on the JDBC URL the
 * String is coerced into the native enum without a custom Hibernate type.
 */
@Converter(autoApply = true)
public class ValetStatusConverter implements AttributeConverter<ValetStatus, String> {

    @Override
    public String convertToDatabaseColumn(ValetStatus attribute) {
        return attribute == null ? null : attribute.dbValue();
    }

    @Override
    public ValetStatus convertToEntityAttribute(String dbData) {
        return dbData == null ? null : ValetStatus.fromDbValue(dbData);
    }
}
