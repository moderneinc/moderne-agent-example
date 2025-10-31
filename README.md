# Moderne Agent Example

Example configurations for deploying the [Moderne Agent](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/agent-configuration/agent-configuration), which connects your development infrastructure to the Moderne Platform.

## What is the Moderne Agent?

The Moderne Agent is a service that runs in your infrastructure to:
- Connect your source code repositories (GitHub, GitLab, Bitbucket, Azure DevOps) to Moderne
- Serve Lossless Semantic Trees (LSTs) from your artifact repositories (Artifactory, Maven)
- Enable secure access to your code without sending source code to Moderne's SaaS

## Prerequisites

1. **Moderne tenant access** - Contact Moderne to obtain:
   - API Gateway URI (e.g., `https://api.tenant.moderne.io`)
   - Agent authentication token

2. **Encryption key** - Generate a 256-bit AES key:
   ```bash
   openssl enc -aes-256-cbc -k secret -P -md sha256
   ```
   Use the value after `key=` for `MODERNE_AGENT_CRYPTO_SYMMETRICKEY`

   **Important:** Keep this key stable. Changing it will make LSTs encrypted with the old key unreadable.

The production `Dockerfile` automatically downloads the agent JAR from Maven Central during the build. For a minimal reference implementation, see [Minimum Docker image](#minimum-docker-image).

## Configuration

### Step 1: Configure Environment Variables

Copy the example configuration and customize for your environment:

```bash
cp .env.example .env
```

Edit `.env` and configure at minimum:

**Required:**
- `MODERNE_AGENT_APIGATEWAYRSOCKETURI` - Your Moderne API endpoint
- `MODERNE_AGENT_TOKEN` - Authentication token from Moderne
- `MODERNE_AGENT_CRYPTO_SYMMETRICKEY` - Your generated encryption key
- `MODERNE_AGENT_NICKNAME` - Identifier for this agent (e.g., `prod-1`)

**Recommended (add at least one):**

**SCM Integration** - Configure OAuth for your source control:
- GitHub: `MODERNE_AGENT_GITHUB_*` variables
- GitLab: `MODERNE_AGENT_GITLAB_*` variables
- Bitbucket: `MODERNE_AGENT_BITBUCKET_*` variables
- Azure DevOps: `MODERNE_AGENT_AZURE_*` variables

**Artifact Repository** - Configure where LSTs are stored:
- Artifactory: `MODERNE_AGENT_ARTIFACTORY_*` variables (recommended)
- Maven: `MODERNE_AGENT_MAVEN_*` variables

See `.env.example` for all available configuration options with detailed comments.

### Step 2: Build Docker Image

```bash
docker build -t moderne-agent .
```

### Step 3: Run the Agent

```bash
docker run -d \
  -p 8080:8080 \
  --env-file .env \
  --name moderne-agent \
  moderne-agent
```

### Step 4: Verify Agent is Running

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

- `GET /actuator/health` - Overall health status
- `GET /actuator/health/liveness` - Liveness probe
- `GET /actuator/health/readiness` - Readiness probe

Health probes are enabled by default since `0.238.0`.

### Metrics

- `GET /actuator/prometheus` - Prometheus metrics endpoint

## Monitoring

### Prometheus Metrics

The agent exposes Prometheus-compatible metrics at `/actuator/prometheus`:

```bash
curl http://localhost:8080/actuator/prometheus
```

Configure Prometheus to scrape this endpoint:

```yaml
scrape_configs:
  - job_name: 'moderne-agent'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['<agent-host>:8080']
```

### Grafana Dashboard

A pre-built Grafana dashboard is available in the [`grafana/`](grafana/) directory.

**To deploy:**
1. Import `grafana/moderne-agent-dashboard-v1.json` into your Grafana instance
2. When prompted, select your Prometheus datasource for the `DS_PROMETHEUS` variable
3. View metrics for gateway connectivity, system resources, JVM, LST operations, and more

## Organizational hierarchy configuration (repos.csv)

The agent can be configured to load the organisational hierarchy from a repos.csv file. This can be the same file as used in mass-ingest.

### repos.csv format

```csv
cloneUrl,branch,origin,path,org1,org2,org3
https://github.com/org/repo,main,github.com,org/repo,Team,Department,ALL
```

**Required columns:**
- `cloneUrl` - Git clone URL for the repository
- `branch` - Branch to analyze
- `origin` - Source control origin (e.g., `github.com`)
- `path` - Repository path (e.g., `org/repo`)

**Optional columns:**
- `org1`, `org2` ... `orgN` - Organizational hierarchy of arbitrary depth (left is child of right)

### Loading from remote URL

Set the environment variable to load repos.csv from an HTTP(S) endpoint:

```bash
MODERNE_AGENT_ORGANIZATION_REPOSCSV=https://example.com/repos.csv
```

Add to your `.env` file or pass via `-e` flag when running the container.

### Loading from local file

Mount a local repos.csv file into the container:

```bash
docker run -d \
  -p 8080:8080 \
  --env-file .env \
  -v /path/to/your/repos.csv:/app/repos.csv \
  -e MODERNE_AGENT_ORGANIZATION_REPOSCSV=file:///app/repos.csv \
  moderne-agent
```

This mounts your local file at `/app/repos.csv` inside the container and configures the agent to read from it.


## Scaling

Multiple agents can run concurrently for high availability and load distribution. Each agent must have a unique `MODERNE_AGENT_NICKNAME`.

Example with Docker:
```bash
docker run -d -p 8080:8080 --env-file .env -e MODERNE_AGENT_NICKNAME=agent-1 moderne-agent
docker run -d -p 8081:8080 --env-file .env -e MODERNE_AGENT_NICKNAME=agent-2 moderne-agent
```

## Troubleshooting

### Agent fails to connect to Moderne

- Verify `MODERNE_AGENT_APIGATEWAYRSOCKETURI` is correct
- Check that `MODERNE_AGENT_TOKEN` is valid
- Ensure network connectivity to Moderne's API endpoint
- Check agent logs: `docker logs moderne-agent`

### No repositories visible in Moderne

- Verify SCM OAuth configuration is correct
- Check that `ALLOWABLE_ORGANIZATIONS`/`ALLOWABLE_GROUPS` includes your org
- Test SCM connectivity from the agent container
- Verify OAuth app has appropriate permissions

### LSTs not appearing

- Verify artifact repository configuration
- For Artifactory: Check AQL query filters
- For Maven: Ensure repository indexing has completed
- Check `MODERNE_AGENT_ARTIFACTINDEXINTERVALSECONDS` frequency
- Verify LSTs are published to the configured repository

## Minimum Docker image

The `Dockerfile.minimal` demonstrates the absolute minimum requirements for running the agent. The main `Dockerfile` includes additional tooling (`libxml2-utils`, automatic JAR download) that simplifies production deployments but aren't strictly required. This minimal version is useful for understanding what's essential vs optional for production hardening.

**To use the minimal Dockerfile:**

1. **Manually download the agent JAR** from [Maven Central](https://central.sonatype.com/artifact/io.moderne/moderne-agent):
   ```bash
   # Replace VERSION with the latest version number
   curl -o moderne-agent-VERSION.jar \
     https://repo1.maven.org/maven2/io/moderne/moderne-agent/VERSION/moderne-agent-VERSION.jar
   ```

2. **Build**:
   ```bash
   docker build -f Dockerfile.minimal -t moderne-agent:minimal .
   ```

3. **Run**:
   ```bash
   docker run -d \
     -p 8080:8080 \
     -e MODERNE_AGENT_APIGATEWAYRSOCKETURI=https://api.<tenant>.moderne.io \
     -e MODERNE_AGENT_TOKEN=<your-agent-token> \
     -e MODERNE_AGENT_CRYPTO_SYMMETRICKEY=<your-256-bit-hex-key> \
     -e MODERNE_AGENT_NICKNAME=my-agent \
     moderne-agent:minimal
   ```

## Repository Structure

```
.
├── Dockerfile                              # Production-grade agent container (downloads JAR)
├── Dockerfile.minimal                      # Minimal agent container (expects local JAR)
├── .env.example                            # Comprehensive configuration template
├── README.md                               # This file
└── grafana/                                # Grafana dashboard for monitoring
    ├── README.md                           # Dashboard documentation
    └── moderne-agent-dashboard-v1.json     # Pre-built dashboard
```

## Resources

- [Moderne Documentation](https://docs.moderne.io)
- [Agent Configuration Guide](https://docs.moderne.io/administrator-documentation/moderne-platform/how-to-guides/agent-configuration/agent-configuration)
- [Maven Central - Moderne Agent](https://central.sonatype.com/artifact/io.moderne/moderne-agent)
- [Moderne Platform](https://www.moderne.io)

## Requirements

- **CPU**: 2 cores minimum, 4+ recommended
- **Memory**: 8GB minimum
- **Storage**: 10GB minimum for LST caching (ephemeral)
- **Network**: Outbound HTTPS access to Moderne API endpoint
- **Java**: 17+ (provided in Docker image)

## Support

For questions or issues:
- [Moderne Documentation](https://docs.moderne.io)
- Contact your Moderne representative
- [GitHub Issues](https://github.com/moderneinc/moderne-agent-example/issues)
