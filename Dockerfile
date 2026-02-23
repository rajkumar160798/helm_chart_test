# ─────────────────────────────────────────────
# Stage 1: Build
# ─────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /app

# Copy pom.xml first and download dependencies (layer caching)
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and build the fat JAR
COPY src ./src
RUN mvn clean package -DskipTests -B

# ─────────────────────────────────────────────
# Stage 2: Runtime (slim image)
# ─────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine AS runtime

LABEL maintainer="rajkumarmyakala"
LABEL app="helloworld"
LABEL version="1.0.0"

WORKDIR /app

# Copy only the fat JAR from the build stage
COPY --from=build /app/target/helloworld-1.0.0.jar app.jar

# Non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080

# Health check (Docker-native, also useful for local testing)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
