cat > scripts/reset_space_indices.sh <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"
LOGSTASH_SERVICE="${LOGSTASH_SERVICE:-logstash}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-360}"
POLL_SECONDS="${POLL_SECONDS:-15}"

TABLE_INDEX="oracle-space-dashboard-v5"
INDEX_INDEX="oracle-index-space-dashboard-v5"

log() {
    echo
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

wait_for_elasticsearch() {
    log "Elasticsearch bekleniyor: ${ES_URL}"

    for ((i=1; i<=60; i++)); do
        if curl -fsS "${ES_URL}/_cluster/health" >/dev/null 2>&1; then
            log "Elasticsearch erişilebilir."
            return 0
        fi

        sleep 2
    done

    echo "HATA: Elasticsearch'e erişilemedi: ${ES_URL}" >&2
    exit 1
}

delete_index() {
    local index_name="$1"

    log "${index_name} siliniyor..."

    curl -fsS -X DELETE \
        "${ES_URL}/${index_name}?ignore_unavailable=true" \
        >/dev/null

    echo "Silindi veya zaten mevcut değildi: ${index_name}"
}

create_index() {
    local index_name="$1"

    log "${index_name} mapping ile oluşturuluyor..."

    curl -fsS -X PUT "${ES_URL}/${index_name}" \
        -H "Content-Type: application/json" \
        -d '{
          "settings": {
            "index.max_result_window": 100000
          },
          "mappings": {
            "properties": {
              "@timestamp": {
                "type": "date"
              },
              "source_db": {
                "type": "keyword"
              },
              "metric_type": {
                "type": "keyword"
              },
              "space_kind": {
                "type": "keyword"
              },
              "metric_group": {
                "type": "keyword"
              },
              "owner": {
                "type": "keyword"
              },
              "object_name": {
                "type": "keyword"
              },
              "entity_name": {
                "type": "keyword"
              },
              "segment_type": {
                "type": "keyword"
              },
              "log_day": {
                "type": "date"
              },
              "log_day_str": {
                "type": "keyword"
              },
              "day_num": {
                "type": "integer"
              },
              "period_days": {
                "type": "integer"
              },
              "log_date": {
                "type": "date"
              },
              "current_size_mb": {
                "type": "double"
              },
              "previous_size_mb": {
                "type": "double"
              },
              "diff_mb": {
                "type": "double"
              },
              "pct_change": {
                "type": "double"
              },
              "total_space_mb": {
                "type": "double"
              },
              "doc_id": {
                "type": "keyword"
              }
            }
          }
        }' | python3 -m json.tool

    echo "Oluşturuldu: ${index_name}"
}

get_count() {
    local index_name="$1"

    curl -fsS "${ES_URL}/${index_name}/_count" |
        python3 -c '
import json
import sys

try:
    print(json.load(sys.stdin).get("count", 0))
except Exception:
    print(0)
'
}

show_metric_groups() {
    local index_name="$1"

    log "${index_name} metric_group dağılımı"

    curl -fsS -X POST "${ES_URL}/${index_name}/_search" \
        -H "Content-Type: application/json" \
        -d '{
          "size": 0,
          "aggs": {
            "metric_groups": {
              "terms": {
                "field": "metric_group",
                "size": 20
              }
            }
          }
        }' |
        python3 -c '
import json
import sys

data = json.load(sys.stdin)
buckets = (
    data.get("aggregations", {})
        .get("metric_groups", {})
        .get("buckets", [])
)

if not buckets:
    print("  Henüz veri yok.")
else:
    for bucket in buckets:
        print(f"  {bucket.get('\''key'\'')}: {bucket.get('\''doc_count'\'')}")
'
}

if ! docker compose config >/dev/null 2>&1; then
    echo "HATA: Script docker-compose.yml bulunan proje klasöründen çalıştırılmalı." >&2
    exit 1
fi

wait_for_elasticsearch

log "Logstash durduruluyor..."
docker compose stop "${LOGSTASH_SERVICE}" || true

delete_index "${TABLE_INDEX}"
delete_index "${INDEX_INDEX}"

create_index "${TABLE_INDEX}"
create_index "${INDEX_INDEX}"

log "Oluşturulan indexler"
curl -fsS "${ES_URL}/_cat/indices/${TABLE_INDEX},${INDEX_INDEX}?v"

log "Logstash yeniden oluşturulup başlatılıyor..."
docker compose up -d --force-recreate "${LOGSTASH_SERVICE}"

log "Logstash pipeline kontrolü"
docker compose ps "${LOGSTASH_SERVICE}"

echo
echo "JDBC schedule 5 dakikalık olduğu için ilk veri akışı birkaç dakika sürebilir."

elapsed=0

while (( elapsed < MAX_WAIT_SECONDS )); do
    table_count="$(get_count "${TABLE_INDEX}")"
    index_count="$(get_count "${INDEX_INDEX}")"

    printf '[%3ss] Table docs: %s | Index docs: %s\n' \
        "${elapsed}" "${table_count}" "${index_count}"

    if (( table_count > 0 && index_count > 0 )); then
        break
    fi

    sleep "${POLL_SECONDS}"
    elapsed=$((elapsed + POLL_SECONDS))
done

log "Sonuç"

table_count="$(get_count "${TABLE_INDEX}")"
index_count="$(get_count "${INDEX_INDEX}")"

echo "Table index document sayısı : ${table_count}"
echo "Index index document sayısı : ${index_count}"

show_metric_groups "${TABLE_INDEX}"
show_metric_groups "${INDEX_INDEX}"

log "Logstash son logları"
docker compose logs --tail=80 "${LOGSTASH_SERVICE}"

echo
echo "İşlem tamamlandı."
echo "Table index: ${TABLE_INDEX}"
echo "Index index: ${INDEX_INDEX}"
echo
echo "Not: Dashboardlar korunur; bu script .kibana indexlerini silmez."
EOF
