# Moderne Agent Grafana Dashboard

Pre-built Grafana dashboard for monitoring Moderne agent health and performance.

## Dashboard Features

Monitors:
- **Gateway connectivity** - Connection status and disconnections
- **System resources** - CPU, memory, disk, network
- **JVM metrics** - Heap usage, garbage collection, threads, file descriptors
- **LST operations** - Download counts, durations, and throughput
- **Maven operations** - Index update activity
- **Optional metrics** - POM cache, package management, repos.csv fetching

## Requirements

- Grafana instance
- Prometheus datasource configured
- Prometheus scraping the agent's `/actuator/prometheus` endpoint
- Agent should set `MODERNE_AGENT_NICKNAME` (exposes `instance_display_name` label)

## Deployment

### Via Grafana UI

1. Open your Grafana instance
2. Navigate to **Dashboards** → **New** → **Import**
3. Upload `moderne-agent-dashboard-v1.json`
4. When prompted, select your Prometheus datasource for the `DS_PROMETHEUS` variable

The dashboard will show data for all agents being scraped by Prometheus. Use the **Agent** dropdown to filter by specific agent nickname.

## Prometheus Configuration

Ensure Prometheus is scraping the agent's metrics endpoint:

```yaml
scrape_configs:
  - job_name: 'moderne-agent'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['<agent-host>:8080']
```

The agent exposes the `instance_display_name` label by default (via `MODERNE_AGENT_NICKNAME`). If you need to override the agent's nickname in Prometheus, you can use relabel configs:

```yaml
scrape_configs:
  - job_name: 'moderne-agent'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['<agent-host>:8080']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance_display_name
        replacement: 'custom-nickname'
```

## Dashboard Structure

1. **Overview** - Dashboard introduction and usage instructions
2. **Status at a glance** - 6 key health indicators (uptime, disconnections, CPU, memory, heap, LST activity)
3. **Gateway connectivity** - Detailed connection health metrics
4. **System resources** - CPU, load, memory, network, disk
5. **JVM metrics** - Heap, GC overhead, threads, file descriptors
6. **LST operations** - Download activity and performance
7. **Maven operations** - Maven index updates
8. **Optional metrics** (collapsed) - POM cache, package management, repos.csv

## Troubleshooting

### No data in panels

- Verify Prometheus is scraping the agent endpoint
- Check the agent is exposing metrics at `/actuator/prometheus`
- Ensure the `application="agent"` label is present on metrics

### Agent not appearing in dropdown

- Verify `MODERNE_AGENT_NICKNAME` is set on the agent
- Check the `instance_display_name` label exists in Prometheus
- Refresh the dashboard or adjust the time range
