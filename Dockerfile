FROM eclipse-temurin:21-jdk
RUN apt-get update && apt-get install -y libxml2-utils

# Set the environment variable MODERNE_CONNECTOR_VERSION
ARG MODERNE_CONNECTOR_VERSION
ENV MODERNE_CONNECTOR_VERSION=${MODERNE_CONNECTOR_VERSION}

WORKDIR /app
USER root

# If necessary, download the Moderne tenant SSL certificate and add it to the default Java TrustStore.
# RUN openssl s_client -showcerts -connect <tenant_name>.moderne.io:443 </dev/null 2>/dev/null | openssl x509 -outform DER > moderne_cert.der
# RUN /opt/java/openjdk/bin/keytool -import -trustcacerts -keystore /opt/java/openjdk/lib/security/cacerts -storepass changeit -noprompt -alias moderne-cert -file moderne_cert.der

RUN groupadd -r app && useradd --no-log-init -r -m -g app app && chown -R app:app /app
USER app

# Download the specified version of moderne-connector JAR file if MODERNE_CONNECTOR_VERSION is provided,
# otherwise download the latest version.
RUN  if [ -n "${MODERNE_CONNECTOR_VERSION}" ]; then \
          echo "Downloading version: ${MODERNE_CONNECTOR_VERSION}"; \
          curl -s --insecure --request GET --url "https://repo1.maven.org/maven2/io/moderne/connector/${MODERNE_CONNECTOR_VERSION}/connector-${MODERNE_CONNECTOR_VERSION}.jar" --output connector.jar; \
     else \
          LATEST_VERSION=$(curl -s --insecure --request GET --url "https://repo1.maven.org/maven2/io/moderne/connector/maven-metadata.xml" | xmllint --xpath 'string(/metadata/versioning/latest)' -); \
          if [ -z "${LATEST_VERSION}" ]; then \
               echo "Failed to retrieve the latest version"; \
               exit 1; \
          fi; \
          echo "Downloading latest version: ${LATEST_VERSION}"; \
          curl -s --insecure --request GET --url "https://repo1.maven.org/maven2/io/moderne/connector/${LATEST_VERSION}/connector-${LATEST_VERSION}.jar" --output connector.jar; \
     fi

EXPOSE 8080

ENTRYPOINT ["java"]
CMD ["-XX:-OmitStackTraceInFastThrow", \
     "-XX:MaxRAMPercentage=65.0", \
     "-XX:MaxDirectMemorySize=2G", \
     "-XX:+HeapDumpOnOutOfMemoryError", \
     "-XX:+ExitOnOutOfMemoryError", \
     "-XX:+UseStringDeduplication", \
     "-jar", "/app/connector.jar"]
