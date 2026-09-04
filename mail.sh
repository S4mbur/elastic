#!/bin/bash

set -u

source /data/logstash/weekly_space_alert.env

HOST_NAME=$(hostname -s)

TMP_TABLE="/tmp/tvssur_table_growth.$$"
TMP_INDEX="/tmp/tvssur_index_growth.$$"
TMP_TABLE_JSON="/tmp/tvssur_table_growth_json.$$"
TMP_INDEX_JSON="/tmp/tvssur_index_growth_json.$$"

trap 'rm -f "$TMP_TABLE" "$TMP_INDEX" "$TMP_TABLE_JSON" "$TMP_INDEX_JSON"' EXIT


# ------------------------------------------------------------
# 7 günlük zaman aralığı
# Epoch millis kullanıyoruz.
# Fark hesabı @timestamp değil LOG_DATE üzerinden yapılır.
# ------------------------------------------------------------

START_MS=$(( $(date -d '7 days ago' +%s) * 1000 ))
END_MS=$(( $(date +%s) * 1000 ))

START_TEXT=$(date -d '7 days ago' '+%Y-%m-%d %H:%M')
END_TEXT=$(date '+%Y-%m-%d %H:%M')


# ------------------------------------------------------------
# TABLE - Son 7 günlük artış
# TABLE_DAILY partitionlar dahil table toplamıdır.
# ------------------------------------------------------------

curl -kfsS \
  -u "${ES_USER}:${ES_PASS}" \
  -X POST "${ES_URL}/_query" \
  -H "Content-Type: application/json" \
  -d @- > "$TMP_TABLE_JSON" <<EOF
{
  "query": "FROM ${TABLE_INDEX} | WHERE metric_group == \"TABLE_DAILY\" AND log_date >= TO_DATETIME(${START_MS}) AND log_date <= TO_DATETIME(${END_MS}) | STATS first_size_mb = FIRST(current_size_mb, log_date), last_size_mb = LAST(current_size_mb, log_date), first_log_date = FIRST(log_date, log_date), last_log_date = LAST(log_date, log_date) BY entity_name | EVAL diff_mb = last_size_mb - first_size_mb | EVAL pct_change = CASE(first_size_mb == 0, null, diff_mb / first_size_mb) | WHERE first_log_date < last_log_date AND diff_mb >= ${TABLE_THRESHOLD_MB} | SORT diff_mb DESC | LIMIT 100 | KEEP entity_name, first_log_date, last_log_date, first_size_mb, last_size_mb, diff_mb, pct_change"
}
EOF


# ------------------------------------------------------------
# INDEX - Son 7 günlük artış
# INDEX_DAILY index partitionlar dahil toplamdır.
# ------------------------------------------------------------

curl -kfsS \
  -u "${ES_USER}:${ES_PASS}" \
  -X POST "${ES_URL}/_query" \
  -H "Content-Type: application/json" \
  -d @- > "$TMP_INDEX_JSON" <<EOF
{
  "query": "FROM ${INDEX_INDEX} | WHERE metric_group == \"INDEX_DAILY\" AND log_date >= TO_DATETIME(${START_MS}) AND log_date <= TO_DATETIME(${END_MS}) | STATS first_size_mb = FIRST(current_size_mb, log_date), last_size_mb = LAST(current_size_mb, log_date), first_log_date = FIRST(log_date, log_date), last_log_date = LAST(log_date, log_date) BY entity_name | EVAL diff_mb = last_size_mb - first_size_mb | EVAL pct_change = CASE(first_size_mb == 0, null, diff_mb / first_size_mb) | WHERE first_log_date < last_log_date AND diff_mb >= ${INDEX_THRESHOLD_MB} | SORT diff_mb DESC | LIMIT 100 | KEEP entity_name, first_log_date, last_log_date, first_size_mb, last_size_mb, diff_mb, pct_change"
}
EOF


# ------------------------------------------------------------
# ES|QL JSON -> okunabilir mail tablosu
# ------------------------------------------------------------

python3 - "$TMP_TABLE_JSON" "$TMP_TABLE" <<'PY'
import json
import sys
from datetime import datetime

src, dst = sys.argv[1], sys.argv[2]

with open(src) as f:
    d = json.load(f)

cols = [x["name"] for x in d.get("columns", [])]
rows = d.get("values", [])

def fmt_date(v):
    if v is None:
        return "-"
    try:
        return str(v).replace("T", " ")[:19]
    except:
        return str(v)

with open(dst, "w") as out:
    for r in rows:
        x = dict(zip(cols, r))

        name = x.get("entity_name", "-")
        first = float(x.get("first_size_mb") or 0)
        last = float(x.get("last_size_mb") or 0)
        diff = float(x.get("diff_mb") or 0)
        pct = float(x.get("pct_change") or 0) * 100

        out.write(
            f"{name}\n"
            f"  İlk Size : {first:,.2f} MB\n"
            f"  Son Size : {last:,.2f} MB\n"
            f"  Artış    : {diff:,.2f} MB (%{pct:,.2f})\n"
            f"  Tarih    : {fmt_date(x.get('first_log_date'))}"
            f" -> {fmt_date(x.get('last_log_date'))}\n\n"
        )
PY


python3 - "$TMP_INDEX_JSON" "$TMP_INDEX" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]

with open(src) as f:
    d = json.load(f)

cols = [x["name"] for x in d.get("columns", [])]
rows = d.get("values", [])

def fmt_date(v):
    if v is None:
        return "-"
    return str(v).replace("T", " ")[:19]

with open(dst, "w") as out:
    for r in rows:
        x = dict(zip(cols, r))

        name = x.get("entity_name", "-")
        first = float(x.get("first_size_mb") or 0)
        last = float(x.get("last_size_mb") or 0)
        diff = float(x.get("diff_mb") or 0)
        pct = float(x.get("pct_change") or 0) * 100

        out.write(
            f"{name}\n"
            f"  İlk Size : {first:,.2f} MB\n"
            f"  Son Size : {last:,.2f} MB\n"
            f"  Artış    : {diff:,.2f} MB (%{pct:,.2f})\n"
            f"  Tarih    : {fmt_date(x.get('first_log_date'))}"
            f" -> {fmt_date(x.get('last_log_date'))}\n\n"
        )
PY


TABLE_COUNT=$(grep -c '^  Artış' "$TMP_TABLE" 2>/dev/null || true)
INDEX_COUNT=$(grep -c '^  Artış' "$TMP_INDEX" 2>/dev/null || true)


# ------------------------------------------------------------
# Hiç threshold aşan yoksa mail atma
# ------------------------------------------------------------

if [ "$TABLE_COUNT" -eq 0 ] && [ "$INDEX_COUNT" -eq 0 ]; then
    echo "Threshold aşan table/index bulunamadı."
    exit 0
fi


# ------------------------------------------------------------
# Mail
# ------------------------------------------------------------

(
echo "To: ${MAIL_TO}"
echo "Subject: [${HOST_NAME}] Haftalık Table / Index Büyüme Uyarısı - $(date '+%Y-%m-%d')"
echo "MIME-Version: 1.0"
echo "Content-Type: text/plain; charset=UTF-8"
echo ""
echo "Host             : ${HOST_NAME}"
echo "Kontrol Aralığı  : ${START_TEXT} - ${END_TEXT}"
echo ""
echo "Table Eşiği      : ${TABLE_THRESHOLD_MB} MB"
echo "Index Eşiği      : ${INDEX_THRESHOLD_MB} MB"
echo ""
echo "Eşiği Aşan Table : ${TABLE_COUNT}"
echo "Eşiği Aşan Index : ${INDEX_COUNT}"
echo ""
echo "============================================================"
echo "TABLE - HAFTALIK BÜYÜME"
echo "============================================================"
echo ""

if [ "$TABLE_COUNT" -gt 0 ]; then
    cat "$TMP_TABLE"
else
    echo "Table eşiğini aşan obje bulunamadı."
    echo ""
fi

echo ""
echo "============================================================"
echo "INDEX - HAFTALIK BÜYÜME"
echo "============================================================"
echo ""

if [ "$INDEX_COUNT" -gt 0 ]; then
    cat "$TMP_INDEX"
else
    echo "Index eşiğini aşan obje bulunamadı."
    echo ""
fi

echo ""
echo "============================================================"
echo "Bu mail Elasticsearch tvssur space monitoring tarafından"
echo "otomatik oluşturulmuştur."
echo ""

) | /usr/sbin/sendmail.postfix -t
