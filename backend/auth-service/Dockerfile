# ---- Stage 1: build (Java 21 + Maven) -------------------------------------
# Build happens inside the image, so no local JDK 21 / Maven is required on the
# host. Dependencies are cached in their own layer for fast incremental builds.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

# Resolve dependencies first (cached unless pom.xml changes).
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Then build the app. Tests need Docker (Testcontainers) which isn't available
# inside this build stage, so we skip them here and run them in CI / locally.
COPY src ./src
RUN mvn -B -q clean package -DskipTests

# ---- Stage 2: runtime (slim JRE, non-root) --------------------------------
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

# Run as an unprivileged user.
RUN addgroup -S valet && adduser -S valet -G valet
USER valet

COPY --from=build /workspace/target/auth-service.jar app.jar

EXPOSE 8081

# Container-aware JVM flags; allow extra opts via env.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0"
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
