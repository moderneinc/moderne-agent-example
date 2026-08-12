# Moderne Connector Example

Example configurations for deploying the [Moderne Connector](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/connector-configuration/connector-configuration), which bridges your private network with the Moderne SaaS platform.

## What is the Moderne Connector?

The Moderne Connector is a Spring Boot service that runs in your infrastructure to:

- Connect your source code repositories (GitHub, GitLab, Bitbucket, Azure DevOps) to the Moderne SaaS
- Discover and serve Lossless Semantic Trees (LSTs) from your artifact repositories (Artifactory, Maven)
- Enable secure, AES-encrypted access to your code without sending source through Moderne
- Resolve customer-published recipes from your private recipe marketplace
- Forward webhook events (PR status, build status) and Moddy LLM traffic through a single outbound RSocket tunnel

The connector is the successor to the legacy Moderne Agent. It uses a hierarchical configuration model (`moderne.connector.*`, `moderne.scm.*`, `moderne.organization.*`, `moderne.recipe.*`) and migrates legacy `moderne.agent.*` properties automatically on startup.

## Prerequisites

1. **Moderne tenant access** — contact Moderne to obtain:
   - API gateway URI (e.g. `https://api.<tenant>.moderne.io/connector`)
   - Connector authentication token

2. **Encryption key** — generate a 256-bit AES key:
   ```bash
   openssl enc -aes-256-cbc -k secret -P -md sha256
   ```
   Use the value after `key=` for `moderne.connector.crypto.symmetric-key`.

   **Important:** keep this key stable. Changing it makes LSTs encrypted with the old key unreadable.

3. **Code Genome Project credentials** — the username and download token Moderne issued you for
   [`artifacts.codegenomeproject.org`](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/accessing-the-code-genome-project/).
   The connector JAR is a proprietary artifact, so the token must carry the `customer`
   entitlement. See [Artifact source](#artifact-source) below.

The production `Dockerfile` automatically downloads the connector JAR from the Code Genome Project during the build. For a minimal reference implementation, see [Minimum Docker image](#minimum-docker-image).

## Artifact source

The connector is published to the Code Genome Project (CGP) Maven repository at
`https://artifacts.codegenomeproject.org/maven`, under the coordinates
`io.moderne:connector`. Every download from it is authenticated: use your Moderne-supplied
username with the download token as the password (the token also works as a bearer token, and
any username is accepted alongside it).

Export the credentials before building; both the `Dockerfile` and `docker-compose.yml` read them
as BuildKit secrets, which keeps them out of the image layers and out of `docker history`:

```bash
export CGP_USERNAME='you@example.com'
export CGP_PASSWORD='<download token>'
```

| Build argument            | Default                                        | Purpose                                                        |
| ------------------------- | ---------------------------------------------- | -------------------------------------------------------------- |
| `MODERNE_ARTIFACT_REPO`   | `https://artifacts.codegenomeproject.org/maven` | Repository the connector JAR is resolved from                   |
| `MODERNE_CONNECTOR_VERSION` | *(latest release)*                            | Pin a version instead of resolving `<release>` from the metadata |

If your build hosts have no egress, mirror `io.moderne:connector` into your own repository
manager and point `MODERNE_ARTIFACT_REPO` at it — the layout is a plain Maven 2 layout, so
nothing else changes. Moderne recommends placing CGP below your internal repositories and above
Maven Central in a virtual repository. When the mirror allows anonymous reads, omit the secrets
entirely:

```bash
docker build --build-arg MODERNE_ARTIFACT_REPO=https://nexus.internal/repository/moderne -t moderne-connector .
```

Common failures: **401** means the credentials are missing, wrong, or revoked; **403** means they
authenticated but lack the `customer` entitlement the connector requires.

## Configuration

The connector is configured via a Spring Boot `application.yml` file. The Docker images set `WORKDIR /app`, which is on Spring Boot's default config search path — so any `application.yml` mounted into `/app/application.yml` at runtime is layered on top of the JAR's embedded defaults without any extra launch flags.

### Step 1: Build your application.yml

Copy the template and customize for your environment:

```bash
cp application.yml.example application.yml
```

Edit `application.yml` and configure at minimum:

**Required:**
- `moderne.connector.api-gateway-rsocket-uri` — your Moderne API endpoint (path `/connector`; legacy `/rsocket` paths are auto-rewritten)
- `moderne.connector.token` — authentication token from Moderne
- `moderne.connector.crypto.symmetric-key` — your generated encryption key
- `moderne.connector.nickname` — identifier for this connector (e.g. `prod-1`)

**Recommended (configure at least one of each):**

**SCM integration** — OAuth for your source control:
- GitHub: `moderne.scm.github`
- GitLab: `moderne.scm.gitlab`
- Bitbucket Data Center: `moderne.scm.bitbucket-datacenter`
- Bitbucket Cloud: `moderne.scm.bitbucket-cloud`
- Azure DevOps: `moderne.scm.azure-devops`

**Artifact repository** — where LSTs are stored. Configured per source under `moderne.organization.sources.{http,s3,file}[*].poll`:
- Artifactory: `...poll.artifactory` (recommended)
- Maven: `...poll.maven`

See `application.yml.example` for all available options with detailed comments.

### Step 2: Build the Docker image

The build pulls the connector JAR from the Code Genome Project, so pass your CGP credentials as
BuildKit secrets (see [Artifact source](#artifact-source)):

```bash
export CGP_USERNAME='you@example.com'
export CGP_PASSWORD='<download token>'

docker build \
  --secret id=cgp_username,env=CGP_USERNAME \
  --secret id=cgp_password,env=CGP_PASSWORD \
  -t moderne-connector .
```

On buildx older than v0.13, write the values to files and use `src=` instead of `env=`:
`--secret id=cgp_username,src=./cgp_username`.

### Step 3: Run the connector

```bash
docker run -d \
  -p 8080:8080 \
  -v "$(pwd)/application.yml:/app/application.yml:ro" \
  --name moderne-connector \
  moderne-connector
```

Or use the provided `docker-compose.yml`, which passes the same credentials through as build
secrets (so `CGP_USERNAME` / `CGP_PASSWORD` must be exported in your shell):

```bash
docker compose up -d
```

### Step 4: Verify the connector is running

Check health status:
```bash
curl http://localhost:8080/actuator/health
```

Expected response:
```json
{"status":"UP"}
```

Check readiness:
```bash
curl http://localhost:8080/actuator/health/readiness
```

## Endpoints

All endpoints are available on port `8080`.

### Health probes

- `GET /actuator/health` — overall health status
- `GET /actuator/health/liveness` — liveness probe
- `GET /actuator/health/readiness` — readiness probe
- `GET /actuator/info` — build info

### Metrics

The connector tunnels its metrics back through the RSocket connection to Moderne (no `/actuator/prometheus` endpoint is exposed). Health, throughput, and gateway-connectivity metrics for your connector are visible in your Moderne tenant's monitoring views — no Prometheus scraping required from your side.

## Organizational hierarchy configuration (repos.csv)

The connector loads the organization hierarchy from one or more repos.csv sources. The same file format is used by mass-ingest and the Moderne CLI.

### repos.csv format

```csv
cloneUrl,branch,origin,path,org1,org2,org3
https://github.com/org/repo,main,github.com,org/repo,Team,Department,ALL
```

**Required columns:**
- `cloneUrl` — Git clone URL for the repository
- `branch` — branch to analyze
- `origin` — source control origin (e.g. `github.com`)
- `path` — repository path (e.g. `org/repo`)

**Optional columns:**
- `org1`, `org2` … `orgN` — organizational hierarchy of arbitrary depth (left is child of right)

### Loading from a remote URL

```yaml
moderne:
  organization:
    sources:
      http:
        - uri: https://example.com/repos.csv
```

### Loading from S3

```yaml
moderne:
  organization:
    sources:
      s3:
        - uri: s3://my-bucket/path/repos-lock.csv
          region: us-west-2
```

### Loading from a local file

Mount a local repos.csv into the container and reference it from `application.yml`:

```bash
docker run -d \
  -p 8080:8080 \
  -v "$(pwd)/application.yml:/app/application.yml:ro" \
  -v /path/to/your/repos.csv:/app/repos.csv:ro \
  moderne-connector
```

```yaml
moderne:
  organization:
    sources:
      file:
        - path: /app/repos.csv
```

The provided `docker-compose.yml` already mounts `example-repos.csv` at `/app/repos.csv`; reference that path in `application.yml` to use it.

## Scaling

Multiple connectors can run concurrently for high availability and load distribution. Each connector must have a unique `moderne.connector.nickname` — either set it directly in each instance's `application.yml`, or override at launch via the `MODERNE_CONNECTOR_NICKNAME` env var (Spring Boot's relaxed binding maps env vars onto the same property tree):

```bash
docker run -d -p 8080:8080 \
  -v "$(pwd)/application.yml:/app/application.yml:ro" \
  -e MODERNE_CONNECTOR_NICKNAME=connector-1 \
  moderne-connector
docker run -d -p 8081:8080 \
  -v "$(pwd)/application.yml:/app/application.yml:ro" \
  -e MODERNE_CONNECTOR_NICKNAME=connector-2 \
  moderne-connector
```

## Troubleshooting

### Connector fails to connect to Moderne

- Verify `moderne.connector.api-gateway-rsocket-uri` is correct (path should end with `/connector`)
- Check that `moderne.connector.token` is valid
- Ensure outbound network connectivity to Moderne's API endpoint
- If behind a proxy, set `moderne.connector.api-gateway.proxy.host` and `moderne.connector.api-gateway.proxy.port`
- Check connector logs: `docker logs moderne-connector`

### No repositories visible in Moderne

- Verify SCM OAuth configuration is correct
- Check that `allowable-organizations` includes your org (where applicable)
- Test SCM connectivity from inside the connector container
- Verify the OAuth app has appropriate permissions

### LSTs not appearing

- Verify artifact repository configuration (Artifactory or Maven)
- For Artifactory: check the `lst-query-filters` AQL expressions
- For Maven: ensure repository indexing has completed
- Tune polling cadence per source with `...poll.artifactory[*].interval` / `...poll.maven[*].interval`, or set the connector-wide default `moderne.connector.organization.interval`
- Verify LSTs are actually published to the configured repository

### Debugging connectivity issues

Set `skip-validate-connectivity: true` on a specific source (Artifactory, Maven, HTTP tool) to skip the startup connectivity check while you investigate. For example:

```yaml
moderne:
  organization:
    sources:
      http:
        - uri: https://example.com/repos.csv
          poll:
            artifactory:
              - uri: https://artifactory.mycompany.com/artifactory
                skip-validate-connectivity: true
```

To enable verbose logging:

```yaml
logging:
  level:
    io.moderne.connector: DEBUG
```

## Migrating from the Moderne Agent

If you previously ran the Moderne Agent, the connector will automatically translate legacy `moderne.agent.*` properties to their connector equivalents on startup, and write the migrated configuration to `moderne.yml`. Common rewrites:

| Legacy agent property                     | Connector property                                   |
|-------------------------------------------|------------------------------------------------------|
| `moderne.agent.api-gateway-rsocket-uri`   | `moderne.connector.api-gateway-rsocket-uri`          |
| `moderne.agent.token`                     | `moderne.connector.token`                            |
| `moderne.agent.crypto.symmetric-key`      | `moderne.connector.crypto.symmetric-key`             |
| `moderne.agent.nickname`                  | `moderne.connector.nickname`                         |
| `moderne.agent.github[*]`                 | `moderne.scm.github[*]`                              |
| `moderne.agent.gitlab[*]`                 | `moderne.scm.gitlab[*]`                              |
| `moderne.agent.bitbucket[*]`              | `moderne.scm.bitbucket-datacenter[*]`                |
| `moderne.agent.bitbucket-cloud`           | `moderne.scm.bitbucket-cloud`                        |
| `moderne.agent.azure-dev-ops[*]`          | `moderne.scm.azure-devops[*]`                        |
| `moderne.agent.pypi[*]`                   | `moderne.recipe.marketplace.repositories.pypi[*]`    |
| `moderne.agent.organization.repos-csv`    | `moderne.organization.sources.http[0].uri`           |
| `moderne.agent.s3[*]`                     | `moderne.organization.sources.s3[*]`                 |
| `moderne.agent.http-tool[*]`              | `moderne.connector.http-tool[*]`                     |
| `moderne.agent.recipe.*`                  | `moderne.connector.recipe.*`                         |
| `moderne.agent.default-commit-options[*]` | `moderne.scm.default-commit-options[*]`              |
| `moderne.agent.cli`                       | `moderne.connector.cli`                              |
| `moderne.agent.ui.*`                      | `moderne.ui.*`                                       |
| `moderne.agent.personal-access-tokens.*`  | `moderne.authorization.access-tokens.*`              |
| `moderne.agent.llm.*`                     | `moderne.moddy.<provider>.*`                         |

**Not auto-migrated:** legacy `moderne.agent.artifactory[*]` and `moderne.agent.maven[*]` pollers cannot be translated automatically, because the connector cannot know which source's repos.csv each poller relates to. The connector fails fast at startup if it finds them. Move each entry manually under the source it polls, at `moderne.organization.sources.{http,s3,file}[*].poll.{artifactory,maven}[*]`.

Field renames applied during migration:
- `.url` → `.uri`
- `.ast-query-filters` / `astQueryFilters` → `.lst-query-filters` / `lstqueryfilters`
- `apiGatewayRsocketUri` ending in `/rsocket` → `/connector`

Properties no longer supported (warned, then ignored): `moderne.agent.organization.devCenter`, `moderne.agent.organization.updateIntervalSeconds`, `moderne.agent.tenantDomain`, `moderne.agent.apiGateway.bearerToken`, `moderne.agent.visualization.useOnlyConfigured`, `moderne.agent.recipe.useOnlyConfigured`.

## Minimum Docker image

`Dockerfile.minimal` demonstrates the absolute minimum requirements for running the connector. The main `Dockerfile` includes additional tooling (`libxml2-utils`, automatic JAR download) that simplifies production deployments but isn't strictly required.

**To use the minimal Dockerfile:**

1. **Manually download the connector JAR** from the Code Genome Project:
   ```bash
   # Replace VERSION with the version you want; browse the available ones at
   # https://artifacts.codegenomeproject.org/maven/io/moderne/connector/
   curl -u "$CGP_USERNAME:$CGP_PASSWORD" -o connector-VERSION.jar \
     https://artifacts.codegenomeproject.org/maven/io/moderne/connector/VERSION/connector-VERSION.jar
   ```

2. **Build:**
   ```bash
   docker build -f Dockerfile.minimal -t moderne-connector:minimal .
   ```

3. **Run:**
   ```bash
   docker run -d \
     -p 8080:8080 \
     -v "$(pwd)/application.yml:/app/application.yml:ro" \
     moderne-connector:minimal
   ```

## Repository structure

```
.
├── Dockerfile              # Production-grade connector container (downloads JAR)
├── Dockerfile.minimal      # Minimal connector container (expects local JAR)
├── docker-compose.yml      # Quick-start compose definition
├── application.yml.example # Comprehensive configuration template
├── example-repos.csv       # Sample repos.csv for trial deployments
└── README.md               # This file
```

## Resources

- [Moderne Documentation](https://docs.moderne.io)
- [Connector Configuration Guide](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/connector-configuration/connector-configuration)
- [Accessing the Code Genome Project](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/accessing-the-code-genome-project/)
- [Code Genome Project — Moderne Connector](https://artifacts.codegenomeproject.org/maven/io/moderne/connector/)
- [Moderne Platform](https://www.moderne.io)

## Requirements

- **CPU**: 2 cores minimum, 4+ recommended
- **Memory**: 8 GB minimum
- **Storage**: 10 GB minimum for LST caching (ephemeral)
- **Network**: outbound HTTPS access to the Moderne API endpoint
- **Java**: 21+ (provided in the Docker image)

## Support

For questions or issues:
- [Moderne Documentation](https://docs.moderne.io)
- Contact your Moderne representative
- [GitHub Issues](https://github.com/moderneinc/connector-example/issues)
