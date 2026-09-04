#!/bin/bash

set -u

source /data/logstash/tvssur_alert.env

ES_API_KEY=$(cat "${ES_API_KEY_FILE}")

HOST_NAME=$(hostname -s)

TMP_TABLE_JSON="/tmp/tvssur_daily_table_growth_json.$$"
TMP_INDEX_JSON="/tmp/tvssur_daily_index_growth_json.$$"
TMP_TABLE="/tmp/tvssur_daily_table_growth.$$"
TMP_INDEX="/tmp/tvssur_daily_index_growth.$$"

trap 'rm -f "$TMP_TABLE_JSON" "$TMP_INDEX_JSON" "$TMP_TABLE" "$TMP_INDEX"' EXIT

# Dünden bugüne bakıyoruz.
# Günlük snapshot olduğu için dünkü gün başı ile yarın gün başı arası alınır.
START_MS=$(( $(date -d 'yesterday 00:00:00' +%s) * 1000 ))
END_MS=$(( $(date -d 'tomorrow 00:00:00' +%s) * 1000 ))

START_TEXT=$(date -d 'yesterday 00:00:00' '+%Y-%m-%d %H:%M')
END_TEXT=$(date -d 'tomorrow 00:00:00' '+%Y-%m-%d %H:%M')

# ------------------------------------------------------------
# TABLE alert
# Şart:
# - Güncel size >= 1024 MB
# - Son 1 günlük artış >= %3
# ------------------------------------------------------------

curl -kfsS \
  -H "Authorization: ApiKey ${ES_API_KEY}" \
  -X POST "${ES_URL}/_query" \
  -H "Content-Type: application/json" \
  -d @- > "$TMP_TABLE_JSON" <<EOF
{
  "query": "FROM ${TABLE_INDEX} | WHERE metric_group == \"TABLE_DAILY\" AND log_date >= TO_DATETIME(${START_MS}) AND log_date < TO_DATETIME(${END_MS}) | STATS first_size_mb = FIRST(current_size_mb, log_date), last_size_mb = LAST(current_size_mb, log_date), first_log_date = FIRST(log_date, log_date), last_log_date = LAST(log_date, log_date) BY entity_name | EVAL diff_mb = last_size_mb - first_size_mb | EVAL pct_change = CASE(first_size_mb == 0, null, ROUND(TO_DOUBLE(diff_mb) / TO_DOUBLE(first_size_mb) * 100, 2)) | WHERE first_log_date < last_log_date AND last_size_mb >= ${MIN_CURRENT_SIZE_MB} AND pct_change >= ${DAILY_PERCENT_THRESHOLD} | SORT pct_change DESC | LIMIT 1000 | KEEP entity_name, first_log_date, last_log_date, first_size_mb, last_size_mb, diff_mb, pct_change"
}
EOF

# ------------------------------------------------------------
# INDEX alert
# Şart:
# - Güncel size >= 1024 MB
# - Son 1 günlük artış >= %3
# ------------------------------------------------------------

curl -kfsS \
  -H "Authorization: ApiKey ${ES_API_KEY}" \
  -X POST "${ES_URL}/_query" \
  -H "Content-Type: application/json" \
  -d @- > "$TMP_INDEX_JSON" <<EOF
{
  "query": "FROM ${INDEX_INDEX} | WHERE metric_group == \"INDEX_DAILY\" AND log_date >= TO_DATETIME(${START_MS}) AND log_date < TO_DATETIME(${END_MS}) | STATS first_size_mb = FIRST(current_size_mb, log_date), last_size_mb = LAST(current_size_mb, log_date), first_log_date = FIRST(log_date, log_date), last_log_date = LAST(log_date, log_date) BY entity_name | EVAL diff_mb = last_size_mb - first_size_mb | EVAL pct_change = CASE(first_size_mb == 0, null, ROUND(TO_DOUBLE(diff_mb) / TO_DOUBLE(first_size_mb) * 100, 2)) | WHERE first_log_date < last_log_date AND last_size_mb >= ${MIN_CURRENT_SIZE_MB} AND pct_change >= ${DAILY_PERCENT_THRESHOLD} | SORT pct_change DESC | LIMIT 1000 | KEEP entity_name, first_log_date, last_log_date, first_size_mb, last_size_mb, diff_mb, pct_change"
}
EOF

# ------------------------------------------------------------
# JSON -> mail text
# ------------------------------------------------------------

python3 - "$TMP_TABLE_JSON" "$TMP_TABLE" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]

with open(src) as f:
    d = json.load(f)

cols = [c["name"] for c in d.get("columns", [])]
rows = d.get("values", [])

def fmt_date(v):
    if v is None:
        return "-"
    return str(v).replace("T", " ")[:19]

def gb(mb):
    return mb / 1024

with open(dst, "w") as out:
    for r in rows:
        x = dict(zip(cols, r))

        name = x.get("entity_name", "-")
        first = float(x.get("first_size_mb") or 0)
        last = float(x.get("last_size_mb") or 0)
        diff = float(x.get("diff_mb") or 0)
        pct = float(x.get("pct_change") or 0)

        out.write(
            f"{name}\n"
            f"  İlk Size : {first:,.2f} MB ({gb(first):,.2f} GB)\n"
            f"  Son Size : {last:,.2f} MB ({gb(last):,.2f} GB)\n"
            f"  Artış    : {diff:,.2f} MB ({gb(diff):,.2f} GB) - %{pct:,.2f}\n"
            f"  Tarih    : {fmt_date(x.get('first_log_date'))} -> {fmt_date(x.get('last_log_date'))}\n\n"
        )
PY

python3 - "$TMP_INDEX_JSON" "$TMP_INDEX" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]

with open(src) as f:
    d = json.load(f)

cols = [c["name"] for c in d.get("columns", [])]
rows = d.get("values", [])

def fmt_date(v):
    if v is None:
        return "-"
    return str(v).replace("T", " ")[:19]

def gb(mb):
    return mb / 1024

with open(dst, "w") as out:
    for r in rows:
        x = dict(zip(cols, r))

        name = x.get("entity_name", "-")
        first = float(x.get("first_size_mb") or 0)
        last = float(x.get("last_size_mb") or 0)
        diff = float(x.get("diff_mb") or 0)
        pct = float(x.get("pct_change") or 0)

        out.write(
            f"{name}\n"
            f"  İlk Size : {first:,.2f} MB ({gb(first):,.2f} GB)\n"
            f"  Son Size : {last:,.2f} MB ({gb(last):,.2f} GB)\n"
            f"  Artış    : {diff:,.2f} MB ({gb(diff):,.2f} GB) - %{pct:,.2f}\n"
            f"  Tarih    : {fmt_date(x.get('first_log_date'))} -> {fmt_date(x.get('last_log_date'))}\n\n"
        )
PY

TABLE_COUNT=$(grep -c '^  Artış' "$TMP_TABLE" 2>/dev/null || true)
INDEX_COUNT=$(grep -c '^  Artış' "$TMP_INDEX" 2>/dev/null || true)

if [ "$TABLE_COUNT" -eq 0 ] && [ "$INDEX_COUNT" -eq 0 ]; then
    echo "Günlük yüzde alarm eşiğini aşan TABLE/INDEX bulunamadı."
    exit 0
fi

(
echo "To: ${MAIL_TO}"
echo "Subject: [${HOST_NAME}] Günlük TABLE/INDEX Büyüme Uyarısı - %${DAILY_PERCENT_THRESHOLD}+ - $(date '+%Y-%m-%d')"
echo "MIME-Version: 1.0"
echo "Content-Type: text/plain; charset=UTF-8"
echo ""
echo "Host                 : ${HOST_NAME}"
echo "Kontrol Aralığı      : ${START_TEXT} - ${END_TEXT}"
echo "Minimum Güncel Size  : ${MIN_CURRENT_SIZE_MB} MB"
echo "Yüzde Artış Eşiği    : %${DAILY_PERCENT_THRESHOLD}"
echo ""
echo "Eşiği Aşan Table     : ${TABLE_COUNT}"
echo "Eşiği Aşan Index     : ${INDEX_COUNT}"
echo ""
echo "============================================================"
echo "TABLE - SON 1 GÜNLÜK %${DAILY_PERCENT_THRESHOLD}+ BÜYÜME"
echo "============================================================"
echo ""

if [ "$TABLE_COUNT" -gt 0 ]; then
    cat "$TMP_TABLE"
else
    echo "Table tarafında eşiği aşan obje bulunamadı."
    echo ""
fi

echo ""
echo "============================================================"
echo "INDEX - SON 1 GÜNLÜK %${DAILY_PERCENT_THRESHOLD}+ BÜYÜME"
echo "============================================================"
echo ""

if [ "$INDEX_COUNT" -gt 0 ]; then
    cat "$TMP_INDEX"
else
    echo "Index tarafında eşiği aşan obje bulunamadı."
    echo ""
fi

echo ""
echo "============================================================"
echo "Bu mail Elasticsearch tvssur space monitoring tarafından otomatik oluşturulmuştur."
echo ""

) | /usr/sbin/sendmail.postfix -t
