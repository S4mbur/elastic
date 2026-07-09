curl -s -X DELETE "http://localhost:9200/oracle-space-daily-v4" || true

curl -X PUT "http://localhost:9200/oracle-space-daily-v4" \
  -H "Content-Type: application/json" \
  -d '{
    "settings": {
      "index.max_result_window": 200000
    },
    "mappings": {
      "properties": {
        "@timestamp": {"type": "date"},
        "source_db": {"type": "keyword"},
        "metric_type": {"type": "keyword"},
        "metric_group": {"type": "keyword"},
        "owner": {"type": "keyword"},
        "object_name": {"type": "keyword"},
        "entity_name": {"type": "keyword"},
        "segment_type": {"type": "keyword"},
        "log_day": {"type": "date"},
        "log_day_str": {"type": "keyword"},
        "day_num": {"type": "integer"},
        "log_date": {"type": "date"},
        "size_mb": {"type": "double"},
        "doc_id": {"type": "keyword"}
      }
    }
  }'
