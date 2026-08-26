cat > tvssur-table.dashboard.json <<'JSON'
{
  "title": "tvssur-table",
  "description": "Oracle table space dashboard. Source: VTB.TB_DB_SPACE_LOG. Uses ES|QL and dashboard time picker.",
  "time_range": {
    "from": "now-120d",
    "to": "now"
  },
  "panels": [
    {
      "grid": {
        "x": 0,
        "y": 0,
        "w": 12,
        "h": 6
      },
      "type": "vis",
      "config": {
        "type": "metric",
        "title": "TOTAL_DATAFILES current MB",
        "data_source": {
          "type": "esql",
          "query": "FROM tvssur-table-space-v1 | WHERE metric_group == \"TOTAL_SPACE_DAILY\" AND object_name == \"TOTAL_DATAFILES\" AND @timestamp >= ?_tstart AND @timestamp < ?_tend | STATS total_space_mb = LAST(total_space_mb, @timestamp)"
        },
        "metrics": [
          {
            "type": "primary",
            "column": "total_space_mb"
          }
        ]
      }
    },
    {
      "grid": {
        "x": 12,
        "y": 0,
        "w": 12,
        "h": 6
      },
      "type": "vis",
      "config": {
        "type": "metric",
        "title": "TOTAL_DATAFILES selected range diff MB",
        "data_source": {
          "type": "esql",
          "query": "FROM tvssur-table-space-v1 | WHERE metric_group == \"TOTAL_SPACE_DAILY\" AND object_name == \"TOTAL_DATAFILES\" AND @timestamp >= ?_tstart AND @timestamp < ?_tend | STATS first_size_mb = FIRST(total_space_mb, @timestamp), last_size_mb = LAST(total_space_mb, @timestamp) | EVAL diff_mb = last_size_mb - first_size_mb | KEEP diff_mb"
        },
        "metrics": [
          {
            "type": "primary",
            "column": "diff_mb"
          }
        ]
      }
    },
    {
      "grid": {
        "x": 0,
        "y": 6,
        "w": 24,
        "h": 10
      },
      "type": "vis",
      "config": {
        "type": "xy",
        "title": "Top 10 table total size MB",
        "layers": [
          {
            "type": "bar_stacked",
            "data_source": {
              "type": "esql",
              "query": "FROM tvssur-table-space-v1 | WHERE metric_group == \"TABLE_DAILY\" AND @timestamp >= ?_tstart AND @timestamp < ?_tend | STATS size_mb = LAST(current_size_mb, @timestamp) BY entity_name | SORT size_mb DESC | LIMIT 10"
            },
            "x": {
              "column": "entity_name"
            },
            "y": [
              {
                "column": "size_mb"
              }
            ]
          }
        ]
      }
    },
    {
      "grid": {
        "x": 24,
        "y": 6,
        "w": 24,
        "h": 10
      },
      "type": "vis",
      "config": {
        "type": "xy",
        "title": "Top 10 non-partition table size MB",
        "layers": [
          {
            "type": "bar_stacked",
            "data_source": {
              "type": "esql",
              "query": "FROM tvssur-table-space-v1 | WHERE metric_group == \"TABLE_ONLY_CURRENT\" AND @timestamp >= ?_tstart AND @timestamp < ?_tend | SORT current_size_mb DESC | LIMIT 10 | KEEP entity_name, current_size_mb"
            },
            "x": {
              "column": "entity_name"
            },
            "y": [
              {
                "column": "current_size_mb"
              }
            ]
          }
        ]
      }
    },
    {
      "grid": {
        "x": 0,
        "y": 16,
        "w": 24,
        "h": 10
      },
      "type": "vis",
      "config": {
        "type": "xy",
        "title": "Top 10 table growth MB in selected range",
        "layers": [
          {
            "type": "bar_stacked",
            "data_source": {
              "type": "esql",
              "query": "FROM tvssur-table-space-v1 | WHERE metric_group == \"TABLE_DAILY\" AND @timestamp >= ?_tstart AND @timestamp < ?_tend | STATS first_size_mb = FIRST(current_size_mb, @timestamp), last_size_mb = LAST(current_size_mb, @timestamp) BY entity_name | EVAL diff_mb = last_size_mb - first_size_mb | WHERE diff_mb > 0 | SORT diff_mb DESC | LIMIT 10 | KEEP entity_name, diff_mb"
            },
            "x": {
              "column": "entity_name"
            },
            "y": [
              {
                "column": "diff_mb"
              }
            ]
          }
        ]
      }
    },
    {
      "grid": {
        "x": 24,
        "y": 16,
        "w": 24,
        "h": 10
      },
      "type": "vis",
      "config": {
        "type": "xy",
        "title": "Top 10 table growth % in selected range",
        "layers": [
          {
            "type": "bar_stacked",
            "data_source": {
              "type": "esql",
              "query": "FROM tvssur-table-space-v1 | WHERE metric_group == \"TABLE_DAILY\" AND @timestamp >= ?_tstart AND @timestamp < ?_tend | STATS first_size_mb = FIRST(current_size_mb, @timestamp), last_size_mb = LAST(current_size_mb, @timestamp) BY entity_name | EVAL pct_change = CASE(first_size_mb == 0, null, (last_size_mb - first_size_mb) / first_size_mb * 100) | WHERE pct_change > 0 | SORT pct_change DESC | LIMIT 10 | KEEP entity_name, pct_change"
            },
            "x": {
              "column": "entity_name"
            },
            "y": [
              {
                "column": "pct_change"
              }
            ]
          }
        ]
      }
    },
    {
      "grid": {
        "x": 0,
        "y": 26,
        "w": 48,
        "h": 10
      },
      "type": "vis",
      "config": {
        "type": "xy",
        "title": "TOTAL_DATAFILES trend",
        "layers": [
          {
            "type": "line",
            "data_source": {
              "type": "esql",
              "query": "FROM tvssur-table-space-v1 | WHERE metric_group == \"TOTAL_SPACE_DAILY\" AND object_name == \"TOTAL_DATAFILES\" AND @timestamp >= ?_tstart AND @timestamp < ?_tend | STATS total_space_mb = MAX(total_space_mb) BY day = BUCKET(@timestamp, 75, ?_tstart, ?_tend) | SORT day ASC"
            },
            "x": {
              "column": "day"
            },
            "y": [
              {
                "column": "total_space_mb"
              }
            ]
          }
        ]
      }
    },
    {
      "grid": {
        "x": 0,
        "y": 36,
        "w": 48,
        "h": 10
      },
      "type": "vis",
      "config": {
        "type": "data_table",
        "title": "Table debug - metric groups",
        "data_source": {
          "type": "esql",
          "query": "FROM tvssur-table-space-v1 | WHERE @timestamp >= ?_tstart AND @timestamp < ?_tend | STATS docs = COUNT() BY metric_group | SORT docs DESC"
        },
        "columns": [
          {
            "column": "metric_group"
          },
          {
            "column": "docs"
          }
        ]
      }
    }
  ]
}
JSON
