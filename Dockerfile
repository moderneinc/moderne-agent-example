FROM eclipse-temurin:21-jdk
RUN apt-get update && apt-get install -y libxml2-utils

# Set the environment variable MODERNE_CONNECTOR_VERSION
ARG MODERNE_CONNECTOR_VERSION
ENV MODERNE_CONNECTOR_VERSION=${MODERNE_CONNECTOR_VERSION}

# The connector is published to the Code Genome Project (CGP) artifact repository.
# Override to resolve the same coordinates from an internal mirror of CGP.
ARG MODERNE_ARTIFACT_REPO=https://artifacts.codegenomeproject.org/maven

WORKDIR /app
USER root

# If necessary, download the Moderne tenant SSL certificate and add it to the default Java TrustStore.
# RUN openssl s_client -showcerts -connect <tenant_name>.moderne.io:443 </dev/null 2>/dev/null | openssl x509 -outform DER > moderne_cert.der
# RUN /opt/java/openjdk/bin/keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts -storepass changeit -noprompt -alias moderne-cert -file moderne_cert.der

# Download the specified version of the moderne-connector JAR file if MODERNE_CONNECTOR_VERSION
# is provided, otherwise the latest release.
#
# CGP is credentialed — the connector is a proprietary artifact, so the Moderne-supplied
# username and download token must carry the `customer` entitlement. Pass them as BuildKit
# secrets so they stay out of the image layers and out of `docker history`:
#
#   docker build \
#     --secret id=cgp_username,env=CGP_USERNAME \
#     --secret id=cgp_password,env=CGP_PASSWORD \
#     -t moderne-connector .
#
# (`src=<file>` works in place of `env=` on older buildx.) Omit both secrets only when
# MODERNE_ARTIFACT_REPO points at a mirror that allows anonymous reads.
RUN --mount=type=secret,id=cgp_username --mount=type=secret,id=cgp_password \
     set -e; \
     CGP_USERNAME="$(cat /run/secrets/cgp_username 2>/dev/null || true)"; \
     CGP_PASSWORD="$(cat /run/secrets/cgp_password 2>/dev/null || true)"; \
     if [ -n "${CGP_USERNAME}" ] || [ -n "${CGP_PASSWORD}" ]; then \
          set -- --user "${CGP_USERNAME}:${CGP_PASSWORD}"; \
     else \
          set --; \
     fi; \
     VERSION="${MODERNE_CONNECTOR_VERSION}"; \
     if [ -z "${VERSION}" ]; then \
          VERSION=$(curl -fsSL "$@" "${MODERNE_ARTIFACT_REPO}/io/moderne/connector/maven-metadata.xml" | xmllint --xpath 'string(/metadata/versioning/release)' -); \
          if [ -z "${VERSION}" ]; then \
               echo "Failed to retrieve the latest release version from ${MODERNE_ARTIFACT_REPO}; pass --build-arg MODERNE_CONNECTOR_VERSION=<version> to pin one"; \
               exit 1; \
          fi; \
     fi; \
     echo "Downloading connector ${VERSION} from ${MODERNE_ARTIFACT_REPO}"; \
     curl -fsSL "$@" -o connector.jar "${MODERNE_ARTIFACT_REPO}/io/moderne/connector/${VERSION}/connector-${VERSION}.jar"

RUN groupadd -r app && useradd --no-log-init -r -m -g app app && chown -R app:app /app
USER app

EXPOSE 8080

ENTRYPOINT ["java"]
CMD ["-XX:-OmitStackTraceInFastThrow", \
     "-XX:MaxRAMPercentage=65.0", \
     "-XX:MaxDirectMemorySize=2G", \
     "-XX:+HeapDumpOnOutOfMemoryError", \
     "-XX:+ExitOnOutOfMemoryError", \
     "-XX:+UseStringDeduplication", \
     "-jar", "/app/connector.jar"]
