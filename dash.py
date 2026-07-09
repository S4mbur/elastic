import json
import urllib.request
import urllib.error

KIBANA_URL = "http://localhost:5601"
INDEX = "oracle-space-daily-v3"
SEARCH_SIZE = 100000

DASHBOARD_ID = "oracle-table-growth-dashboard"

def es_query(metric_group):
    return {
        "index": INDEX,
        "body": {
            "size": SEARCH_SIZE,
            "_source": [
                "metric_group",
                "entity_name",
                "owner",
                "object_name",
                "segment_type",
                "log_day",
                "log_date",
                "size_mb"
            ],
            "query": {
                "bool": {
                    "filter": [
                        {"term": {"metric_group.keyword": metric_group}},
                        {"range": {"@timestamp": {"gte": "now-60d/d", "lte": "now"}}}
                    ]
                }
            },
            "sort": [
                {"log_day": {"order": "desc"}},
                {"entity_name.keyword": {"order": "asc"}}
            ]
        }
    }

def current_size_bar_spec():
    return {
        "description": "Top 10 current table total size",
        "width": 780,
        "height": 330,
        "autosize": "none",
        "padding": {"left": 330, "right": 110, "top": 20, "bottom": 45},
        "data": [
            {
                "name": "raw",
                "url": es_query("SEGMENT_TABLE"),
                "format": {"property": "hits.hits"},
                "transform": [
                    {"type": "formula", "as": "entity", "expr": "datum._source.entity_name"},
                    {"type": "formula", "as": "size", "expr": "+datum._source.size_mb"},
                    {"type": "formula", "as": "logDay", "expr": "toDate(datum._source.log_day)"},
                    {"type": "filter", "expr": "datum.entity != null && isValid(datum.size)"}
                ]
            },
            {
                "name": "latest",
                "source": "raw",
                "transform": [
                    {
                        "type": "window",
                        "sort": {"field": "logDay", "order": "descending"},
                        "ops": ["row_number"],
                        "as": ["rn"],
                        "groupby": ["entity"]
                    },
                    {"type": "filter", "expr": "datum.rn == 1"},
                    {"type": "collect", "sort": {"field": "size", "order": "descending"}},
                    {"type": "window", "ops": ["row_number"], "as": ["rank"]},
                    {"type": "filter", "expr": "datum.rank <= 10"}
                ]
            }
        ],
        "scales": [
            {
                "name": "yscale",
                "type": "band",
                "domain": {"data": "latest", "field": "entity"},
                "range": "height",
                "padding": 0.18
            },
            {
                "name": "xscale",
                "type": "linear",
                "domain": {"data": "latest", "field": "size"},
                "range": "width",
                "nice": True,
                "zero": True
            }
        ],
        "axes": [
            {
                "orient": "left",
                "scale": "yscale",
                "labelLimit": 310,
                "labelFontSize": 11,
                "title": "Table"
            },
            {
                "orient": "bottom",
                "scale": "xscale",
                "title": "Size MB",
                "grid": True
            }
        ],
        "marks": [
            {
                "type": "rect",
                "from": {"data": "latest"},
                "encode": {
                    "enter": {
                        "y": {"scale": "yscale", "field": "entity"},
                        "height": {"scale": "yscale", "band": 1},
                        "x": {"scale": "xscale", "value": 0},
                        "x2": {"scale": "xscale", "field": "size"},
                        "tooltip": {
                            "signal": "datum.entity + ': ' + format(datum.size, ',.2f') + ' MB'"
                        }
                    }
                }
            },
            {
                "type": "text",
                "from": {"data": "latest"},
                "encode": {
                    "enter": {
                        "y": {"scale": "yscale", "field": "entity", "band": 0.5},
                        "x": {"scale": "xscale", "field": "size", "offset": 6},
                        "align": {"value": "left"},
                        "baseline": {"value": "middle"},
                        "fontSize": {"value": 11},
                        "text": {"signal": "format(datum.size, ',.2f') + ' MB'"}
                    }
                }
            }
        ]
    }

def adjustable_growth_bar_spec():
    return {
        "description": "Adjustable table growth percentage",
        "width": 780,
        "height": 330,
        "autosize": "none",
        "padding": {"left": 330, "right": 150, "top": 45, "bottom": 45},
        "signals": [
            {
                "name": "daysBack",
                "value": 3,
                "bind": {
                    "input": "select",
                    "options": [1, 2, 3, 5, 7, 14, 30],
                    "name": "Kaç gün önceyle karşılaştır: "
                }
            }
        ],
        "data": [
            {
                "name": "raw",
                "url": es_query("SEGMENT_TABLE"),
                "format": {"property": "hits.hits"},
                "transform": [
                    {"type": "formula", "as": "entity", "expr": "datum._source.entity_name"},
                    {"type": "formula", "as": "size", "expr": "+datum._source.size_mb"},
                    {"type": "formula", "as": "logDayDate", "expr": "toDate(datum._source.log_day)"},
                    {"type": "formula", "as": "day", "expr": "timeFormat(datum.logDayDate, '%Y-%m-%d')"},
                    {"type": "filter", "expr": "datum.entity != null && isValid(datum.size)"},
                    {
                        "type": "joinaggregate",
                        "ops": ["max"],
                        "fields": ["logDayDate"],
                        "as": ["latestDate"]
                    },
                    {"type": "formula", "as": "latestDay", "expr": "timeFormat(datum.latestDate, '%Y-%m-%d')"},
                    {
                        "type": "formula",
                        "as": "targetDay",
                        "expr": "timeFormat(datetime(year(datum.latestDate), month(datum.latestDate), date(datum.latestDate) - daysBack), '%Y-%m-%d')"
                    }
                ]
            },
            {
                "name": "current",
                "source": "raw",
                "transform": [
                    {"type": "filter", "expr": "datum.day == datum.latestDay"}
                ]
            },
            {
                "name": "previous",
                "source": "raw",
                "transform": [
                    {"type": "filter", "expr": "datum.day == datum.targetDay"}
                ]
            },
            {
                "name": "diffs",
                "source": "current",
                "transform": [
                    {
                        "type": "lookup",
                        "from": "previous",
                        "key": "entity",
                        "fields": ["entity"],
                        "values": ["size"],
                        "as": ["prevSize"]
                    },
                    {
                        "type": "formula",
                        "as": "diffMb",
                        "expr": "datum.prevSize == null ? null : datum.size - datum.prevSize"
                    },
                    {
                        "type": "formula",
                        "as": "pct",
                        "expr": "datum.prevSize == null || datum.prevSize == 0 ? null : ((datum.size - datum.prevSize) / datum.prevSize) * 100"
                    },
                    {"type": "filter", "expr": "datum.pct != null && isValid(datum.pct)"},
                    {"type": "collect", "sort": {"field": "pct", "order": "descending"}},
                    {"type": "window", "ops": ["row_number"], "as": ["rank"]},
                    {"type": "filter", "expr": "datum.rank <= 10"}
                ]
            }
        ],
        "scales": [
            {
                "name": "yscale",
                "type": "band",
                "domain": {"data": "diffs", "field": "entity"},
                "range": "height",
                "padding": 0.18
            },
            {
                "name": "xscale",
                "type": "linear",
                "domain": {"data": "diffs", "field": "pct"},
                "range": "width",
                "nice": True,
                "zero": True
            }
        ],
        "axes": [
            {
                "orient": "left",
                "scale": "yscale",
                "labelLimit": 310,
                "labelFontSize": 11,
                "title": "Table"
            },
            {
                "orient": "bottom",
                "scale": "xscale",
                "title": "Growth %",
                "grid": True
            }
        ],
        "marks": [
            {
                "type": "rect",
                "from": {"data": "diffs"},
                "encode": {
                    "enter": {
                        "y": {"scale": "yscale", "field": "entity"},
                        "height": {"scale": "yscale", "band": 1},
                        "x": {"scale": "xscale", "value": 0},
                        "x2": {"scale": "xscale", "field": "pct"},
                        "tooltip": {
                            "signal": "datum.entity + '\\nCurrent: ' + format(datum.size, ',.2f') + ' MB\\nPrevious: ' + format(datum.prevSize, ',.2f') + ' MB\\nDiff: ' + format(datum.diffMb, ',.2f') + ' MB\\nGrowth: ' + format(datum.pct, ',.2f') + '%'"
                        }
                    }
                }
            },
            {
                "type": "text",
                "from": {"data": "diffs"},
                "encode": {
                    "enter": {
                        "y": {"scale": "yscale", "field": "entity", "band": 0.5},
                        "x": {"scale": "xscale", "field": "pct", "offset": 6},
                        "align": {"value": "left"},
                        "baseline": {"value": "middle"},
                        "fontSize": {"value": 11},
                        "text": {
                            "signal": "format(datum.pct, ',.2f') + '% / ' + format(datum.diffMb, ',.2f') + ' MB'"
                        }
                    }
                }
            }
        ]
    }

def total_space_trend_spec():
    return {
        "description": "Total space trend",
        "width": 1620,
        "height": 300,
        "autosize": "none",
        "padding": {"left": 90, "right": 60, "top": 20, "bottom": 45},
        "data": [
            {
                "name": "raw",
                "url": es_query("TOTAL_SPACE"),
                "format": {"property": "hits.hits"},
                "transform": [
                    {"type": "formula", "as": "entity", "expr": "datum._source.entity_name"},
                    {"type": "formula", "as": "size", "expr": "+datum._source.size_mb"},
                    {"type": "formula", "as": "logDayDate", "expr": "toDate(datum._source.log_day)"},
                    {"type": "formula", "as": "day", "expr": "timeFormat(datum.logDayDate, '%Y-%m-%d')"},
                    {"type": "filter", "expr": "isValid(datum.size)"}
                ]
            },
            {
                "name": "daily",
                "source": "raw",
                "transform": [
                    {
                        "type": "aggregate",
                        "groupby": ["day", "logDayDate"],
                        "ops": ["sum"],
                        "fields": ["size"],
                        "as": ["totalSize"]
                    },
                    {"type": "collect", "sort": {"field": "logDayDate", "order": "ascending"}}
                ]
            }
        ],
        "scales": [
            {
                "name": "xscale",
                "type": "time",
                "domain": {"data": "daily", "field": "logDayDate"},
                "range": "width"
            },
            {
                "name": "yscale",
                "type": "linear",
                "domain": {"data": "daily", "field": "totalSize"},
                "range": "height",
                "nice": True,
                "zero": False
            }
        ],
        "axes": [
            {
                "orient": "bottom",
                "scale": "xscale",
                "title": "Day"
            },
            {
                "orient": "left",
                "scale": "yscale",
                "title": "Total space MB",
                "grid": True
            }
        ],
        "marks": [
            {
                "type": "line",
                "from": {"data": "daily"},
                "encode": {
                    "enter": {
                        "x": {"scale": "xscale", "field": "logDayDate"},
                        "y": {"scale": "yscale", "field": "totalSize"},
                        "strokeWidth": {"value": 2}
                    }
                }
            },
            {
                "type": "symbol",
                "from": {"data": "daily"},
                "encode": {
                    "enter": {
                        "x": {"scale": "xscale", "field": "logDayDate"},
                        "y": {"scale": "yscale", "field": "totalSize"},
                        "size": {"value": 45},
                        "tooltip": {
                            "signal": "datum.day + ': ' + format(datum.totalSize, ',.2f') + ' MB'"
                        }
                    }
                }
            }
        ]
    }

def visualization_obj(obj_id, title, spec):
    vis_state = {
        "title": title,
        "type": "vega",
        "params": {
            "spec": json.dumps(spec, indent=2)
        },
        "aggs": []
    }

    return {
        "type": "visualization",
        "id": obj_id,
        "attributes": {
            "title": title,
            "description": "",
            "version": 1,
            "visState": json.dumps(vis_state),
            "uiStateJSON": "{}",
            "kibanaSavedObjectMeta": {
                "searchSourceJSON": json.dumps({
                    "query": {"query": "", "language": "kuery"},
                    "filter": []
                })
            }
        },
        "references": []
    }

viz_size_id = "oracle-current-table-size-bar-v3"
viz_growth_id = "oracle-adjustable-table-growth-bar-v3"
viz_total_id = "oracle-total-space-trend-v3"

objects = [
    visualization_obj(viz_size_id, "Top 10 Current Table Size MB", current_size_bar_spec()),
    visualization_obj(viz_growth_id, "Top 10 Adjustable Table Growth %", adjustable_growth_bar_spec()),
    visualization_obj(viz_total_id, "Total Space Trend", total_space_trend_spec())
]

panels = [
    {
        "version": "9.4.2",
        "type": "visualization",
        "gridData": {"x": 0, "y": 0, "w": 24, "h": 16, "i": "1"},
        "panelIndex": "1",
        "embeddableConfig": {},
        "panelRefName": "panel_1"
    },
    {
        "version": "9.4.2",
        "type": "visualization",
        "gridData": {"x": 24, "y": 0, "w": 24, "h": 16, "i": "2"},
        "panelIndex": "2",
        "embeddableConfig": {},
        "panelRefName": "panel_2"
    },
    {
        "version": "9.4.2",
        "type": "visualization",
        "gridData": {"x": 0, "y": 16, "w": 48, "h": 15, "i": "3"},
        "panelIndex": "3",
        "embeddableConfig": {},
        "panelRefName": "panel_3"
    }
]

objects.append({
    "type": "dashboard",
    "id": DASHBOARD_ID,
    "attributes": {
        "title": "Oracle Table Space Growth",
        "description": "Daily Oracle table and total-space tracking. Growth panel is adjustable by selected days.",
        "panelsJSON": json.dumps(panels),
        "optionsJSON": json.dumps({
            "useMargins": True,
            "syncColors": False,
            "syncCursor": True,
            "syncTooltips": False
        }),
        "version": 1,
        "timeRestore": False,
        "kibanaSavedObjectMeta": {
            "searchSourceJSON": json.dumps({
                "query": {"query": "", "language": "kuery"},
                "filter": []
            })
        }
    },
    "references": [
        {"name": "panel_1", "type": "visualization", "id": viz_size_id},
        {"name": "panel_2", "type": "visualization", "id": viz_growth_id},
        {"name": "panel_3", "type": "visualization", "id": viz_total_id}
    ]
})

payload = json.dumps(objects).encode("utf-8")

req = urllib.request.Request(
    KIBANA_URL + "/api/saved_objects/_bulk_create?overwrite=true",
    data=payload,
    method="POST",
    headers={
        "Content-Type": "application/json",
        "kbn-xsrf": "true"
    }
)

try:
    with urllib.request.urlopen(req) as resp:
        print(resp.read().decode("utf-8"))
        print()
        print("Dashboard hazır:")
        print(KIBANA_URL + "/app/dashboards#/view/" + DASHBOARD_ID)
except urllib.error.HTTPError as e:
    print("HTTP ERROR:", e.code)
    print(e.read().decode("utf-8"))
    raise
