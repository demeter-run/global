#!/usr/bin/env python3
"""Generate a Demeter incident/degradation report from Grafana alert history.

Grafana Cloud is the only source that retains alert history beyond the 45-day
in-cluster Prometheus window, so incidents are reconstructed from alert
state-change history rather than a PromQL query. Demeter's alerts are
Grafana-managed (unified) rules, whose transitions live in the state-history
API (`/api/v1/rules/history`); the legacy annotations table
(`/api/annotations?type=alert`) is kept as a fallback source. Each firing
period is paired to its resolution to produce one row per incident.

The script writes a durable CSV and a Markdown snapshot to a working directory,
then optionally delivers both to a Discord channel (summary embed + file
attachments) so nothing sensitive is committed to this public repository. Run
ad-hoc for a one-off report or on a schedule to keep the channel current.

Each incident is classified as customer-visible or AZ-redundant: workloads run
across az1/az2, so a single AZ down while its peer stays up is invisible to
users. Buckets are split per network (mainnet/preprod/preview) so a testnet
outage doesn't read as a whole-service outage, and a network-agnostic proxy
counts against every network. Degraded time is reported as wall-clock (union of
overlapping pod/AZ intervals) rather than a sum of per-pod alerts, which would
overstate a network-wide event severalfold. Cluster-plumbing services
(kube-state-metrics) are excluded entirely.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import io
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

# Em dash used for empty cells; kept as a constant so it never appears as a
# backslash escape inside an f-string expression (a SyntaxError before 3.12).
DASH = "\u2014"

# Annotations API caps `limit` at 100 per request; we page backwards in time.
PAGE_LIMIT = 100
# Page size for the alert state-history API.
HISTORY_LIMIT = 2500
# Guard against pathological pagination loops.
MAX_PAGES = 500

# alertname keyword -> severity, used only when the rule carries no `severity`
# label. Ordered most-severe first; first match wins.
SEVERITY_KEYWORDS = (
    ("critical", ("down", "oom", "out of memory", "crashloop", "evicted", "failed", "unschedulable")),
    ("warning", ("stale", "lag", "mismatch", "disconnected", "pending", "imagepull", "error", "surge", "stopped")),
)

# Services excluded from the report: cluster-plumbing alerts that never reach
# customers (kube-state-metrics restarts churn a lot but users see nothing).
EXCLUDE_SERVICES = frozenset({"kube-state-metrics"})

# Demeter product families, matched against the alertname (which names the
# product, e.g. "Cardano Node Instance is down") because the pod/app labels are
# inconsistent or absent: some alerts carry no app label, and Kupo/UTxO RPC run
# on Dolos pods, so the instance name alone would mislabel them as `dolos`.
# Ordered most-specific first; the first substring match wins, so `kupo` and
# `utxo-rpc` are checked before `dolos` (their backing engine).
KNOWN_SERVICES = (
    ("cardano-node", ("cardano node", "cardano-node")),
    ("utxo-rpc", ("utxo rpc", "utxorpc", "utxo-rpc")),
    ("kupo", ("kupo",)),
    ("ogmios", ("ogmios",)),
    ("dolos", ("dolos",)),
)


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def resolve_grafana(config_path: str) -> tuple[str, str]:
    """Return (base_url, token), preferring env over the decrypted config file."""
    url = os.environ.get("GRAFANA_URL")
    token = os.environ.get("GRAFANA_TOKEN")
    if url and token:
        return url.rstrip("/"), token

    try:
        import yaml  # noqa: PLC0415 - optional dep, only needed for the config path
    except ImportError:
        eprint("PyYAML is required to read config.yaml; run `pip install -r scripts/requirements.txt` "
               "or pass GRAFANA_URL and GRAFANA_TOKEN.")
        sys.exit(2)

    with open(config_path, encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    cloud = (cfg or {}).get("grafana", {}).get("cloud", {})
    url = url or cloud.get("url", "")
    token = token or cloud.get("auth", "")

    if not url or not token:
        eprint(f"Could not find grafana.cloud.url/auth in {config_path}.")
        sys.exit(2)
    if token.startswith("ENC["):
        eprint(f"{config_path} is still sops-encrypted; run `sops -d -i {config_path}` first "
               "(or export GRAFANA_TOKEN).")
        sys.exit(2)
    return url.rstrip("/"), token


def webhook_from_config(config_path: str) -> str:
    """Read grafana.cloud.discord_webhook_url from the decrypted config, if present."""
    try:
        import yaml  # noqa: PLC0415 - optional dep, only needed for the config path
    except ImportError:
        return ""
    with open(config_path, encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    url = (cfg or {}).get("grafana", {}).get("cloud", {}).get("discord_webhook_url", "") or ""
    if url.startswith("ENC["):
        eprint(f"{config_path} is still sops-encrypted; cannot read discord_webhook_url.")
        return ""
    return url


def fetch_alert_annotations(base_url: str, token: str, frm_ms: int, to_ms: int) -> list[dict]:
    """Fetch every alert annotation in [frm_ms, to_ms], paging backwards in time."""
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    seen: dict[int, dict] = {}
    cursor = to_ms
    for _ in range(MAX_PAGES):
        params = urllib.parse.urlencode(
            {"type": "alert", "from": frm_ms, "to": cursor, "limit": PAGE_LIMIT}
        )
        req = urllib.request.Request(f"{base_url}/api/annotations?{params}", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                batch = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as err:
            eprint(f"Grafana API error {err.code}: {err.read().decode('utf-8', 'replace')[:300]}")
            sys.exit(1)

        if not batch:
            break
        new = 0
        oldest = cursor
        for ann in batch:
            ann_id = ann.get("id")
            if ann_id is None:
                ann_id = hash(json.dumps(ann, sort_keys=True))
            if ann_id not in seen:
                seen[ann_id] = ann
                new += 1
            oldest = min(oldest, int(ann.get("time", cursor)))
        # Step the cursor below the oldest row so the next page continues
        # backwards; a page that added nothing new is still bounded by this.
        cursor = oldest - 1
        if len(batch) < PAGE_LIMIT or cursor < frm_ms:
            break
    return list(seen.values())


def _history_request(base_url: str, token: str, frm: int, to: int, limit: int) -> dict:
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    params = urllib.parse.urlencode({"from": frm, "to": to, "limit": limit})
    req = urllib.request.Request(f"{base_url}/api/v1/rules/history?{params}", headers=headers)
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _parse_history_frame(data: dict) -> list[tuple[int, dict]]:
    """Turn a Grafana state-history dataframe into (time_ms, transition) tuples."""
    values = (data or {}).get("data", {}).get("values", [])
    if len(values) < 2:
        return []
    times, lines = values[0], values[1]
    out: list[tuple[int, dict]] = []
    for raw_t, line in zip(times, lines):
        t = int(raw_t)
        if t > 1_000_000_000_000_000:   # nanoseconds -> ms
            t //= 1_000_000
        elif t < 1_000_000_000_000:     # seconds -> ms
            t *= 1000
        if isinstance(line, str):
            try:
                line = json.loads(line)
            except json.JSONDecodeError:
                line = {"labels": {}, "current": ""}
        out.append((t, line if isinstance(line, dict) else {"labels": {}, "current": ""}))
    return out


def fetch_state_history(base_url: str, token: str, frm_ms: int, to_ms: int) -> list[tuple[int, dict]]:
    """Fetch alert state transitions from `/api/v1/rules/history` over [frm_ms, to_ms].

    Grafana-managed (unified) alert rules record their history here rather than
    in the legacy annotations table. The endpoint expects unix seconds; if that
    yields nothing we retry the window in milliseconds to tolerate either
    convention. Results are paged backwards in time and deduplicated.
    """
    entries: dict[tuple, tuple[int, dict]] = {}
    for unit in (1000, 1):  # divisor: seconds first, then milliseconds
        cursor = to_ms
        got_any = False
        for _ in range(MAX_PAGES):
            try:
                data = _history_request(base_url, token, frm_ms // unit, cursor // unit, HISTORY_LIMIT)
            except urllib.error.HTTPError as err:
                eprint(f"Grafana API error {err.code}: {err.read().decode('utf-8', 'replace')[:300]}")
                sys.exit(1)
            page = _parse_history_frame(data)
            if not page:
                break
            got_any = True
            oldest = cursor
            for t, line in page:
                key = (t, json.dumps(line.get("labels", {}), sort_keys=True), str(line.get("current", "")))
                entries[key] = (t, line)
                oldest = min(oldest, t)
            cursor = oldest - 1
            if len(page) < HISTORY_LIMIT or cursor < frm_ms:
                break
        if got_any:
            break
    return list(entries.values())


def parse_labels(ann: dict) -> dict[str, str]:
    """Extract label key/values from an annotation's tags (`key=value` form)."""
    labels: dict[str, str] = {}
    for tag in ann.get("tags", []) or []:
        if isinstance(tag, str) and "=" in tag:
            key, _, value = tag.partition("=")
            labels[key.strip()] = value.strip()
    return labels


def state_of(ann: dict) -> str:
    """Normalize an annotation to a coarse state: 'firing', 'resolved', or ''."""
    raw = str(ann.get("newState") or ann.get("data", {}).get("newState") or "").lower()
    if raw in ("alerting", "firing"):
        return "firing"
    if raw in ("normal", "ok", "resolved"):
        return "resolved"
    return ""


def severity_of(alertname: str, labels: dict[str, str]) -> str:
    if labels.get("severity"):
        return labels["severity"]
    name = alertname.lower()
    for level, keywords in SEVERITY_KEYWORDS:
        if any(kw in name for kw in keywords):
            return level
    return "unknown"


def service_of(alertname: str, labels: dict[str, str]) -> str:
    # The alertname names the product, so it's the most reliable signal: pod/app
    # labels are absent on some rules and point at the backing engine (Dolos)
    # for Kupo/UTxO RPC. Fall back to labels, then the first alertname word.
    name = (alertname or "").lower()
    for canonical, needles in KNOWN_SERVICES:
        if any(n in name for n in needles):
            return canonical
    for key in ("app", "service", "job"):
        if labels.get(key):
            return labels[key]
    ns = labels.get("namespace", "")
    if ns:
        return ns.removeprefix("ext-").removesuffix("-m1")
    return alertname.split()[0] if alertname else "unknown"


def instance_of(labels: dict[str, str]) -> str:
    for key in ("pod", "instance", "alias", "endpoint"):
        if labels.get(key):
            return labels[key]
    return ""


def series_key(alertname: str, labels: dict[str, str]) -> str:
    inst = labels.get("pod") or labels.get("instance") or labels.get("alias") or ""
    return f"{alertname}|{inst}"


# Instances are named `<app>-<network>-az<N>-<hash>`, e.g.
# `ogmios-v7-preprod-az1-857b...`. The AZ suffix marks the redundant peer.
_AZ_RE = re.compile(r"-az(\d+)\b")

# The three Cardano networks Demeter serves, used to bucket incidents so a
# testnet outage doesn't read as a whole-service outage.
NETWORKS = ("mainnet", "preprod", "preview")
_NET_RE = re.compile(r"-(" + "|".join(NETWORKS) + r")-")

# Network-agnostic services (proxies/gateways) front every network at once, so
# an outage there is attributed to all of them rather than a single bucket.
ALL_NETWORKS = "all"


def az_of(instance: str) -> str:
    m = _AZ_RE.search(instance)
    return m.group(1) if m else ""


def network_of(instance: str) -> str:
    """The Cardano network an instance serves, or `all` for a proxy.

    Network-specific workloads embed the network in their name
    (`ogmios-v7-preprod-az1-...`). A proxy that fronts every network carries no
    such token, so its incidents count against all networks at once.
    """
    m = _NET_RE.search(instance)
    return m.group(1) if m else ALL_NETWORKS


def normalize_service(name: str) -> str:
    """Fold service-name casing so one workload isn't split across rows.

    The same service is labelled inconsistently by different alerts (the app
    label `ogmios` vs the alertname-derived `Ogmios`); lowercasing merges them.
    """
    return name.strip().lower()


def workload_of(instance: str) -> str:
    """The AZ-independent workload identity, e.g. `ogmios-v7-preprod`.

    Everything from the `-azN` token onward (AZ + pod hash) is dropped so that
    az1 and az2 of the same deployment share a key.
    """
    m = re.match(r"^(.*?)-az\d+\b", instance)
    return m.group(1) if m else instance


def classify_impact(incidents: list[dict]) -> None:
    """Tag each incident 'Customer-visible' or 'AZ-redundant' in place.

    The platform runs each workload across az1/az2, so a single AZ being down is
    absorbed by its peer and is invisible to users. An incident is therefore
    customer-visible only when a different AZ of the same workload+alert was
    down at an overlapping time (all AZs down at once), or when the instance
    carries no AZ suffix (no known redundancy to rely on).
    """
    groups: dict[tuple[str, str], list[dict]] = {}
    for inc in incidents:
        inst = inc.get("instance", "")
        inc["_az"] = az_of(inst)
        # End of the firing window; ongoing incidents were measured to now, so
        # start + duration reconstructs the effective end without extra state.
        inc["_end_ms"] = int(inc["start_ms"]) + max(int(inc.get("duration_s") or 0), 1) * 1000
        groups.setdefault((workload_of(inst), inc["alert"]), []).append(inc)

    for members in groups.values():
        for inc in members:
            if not inc["_az"]:
                inc["impact"] = "Customer-visible"
                continue
            s_a, e_a = int(inc["start_ms"]), inc["_end_ms"]
            peer_down = any(
                other is not inc
                and other["_az"] and other["_az"] != inc["_az"]
                and s_a < other["_end_ms"] and int(other["start_ms"]) < e_a
                for other in members
            )
            inc["impact"] = "Customer-visible" if peer_down else "AZ-redundant"

    for inc in incidents:
        inc.pop("_az", None)
        inc.pop("_end_ms", None)


def annotations_to_events(annotations: list[dict]) -> list[dict]:
    """Normalize legacy alert annotations into common events.

    Region annotations (those carrying a `timeEnd`) become complete incidents
    via the `end` field; point annotations carry a firing/resolved state.
    """
    events: list[dict] = []
    for ann in annotations:
        labels = parse_labels(ann)
        alertname = labels.get("alertname") or ann.get("text") or ann.get("alertName") or "unknown"
        start = int(ann.get("time", 0))
        end = ann.get("timeEnd")
        events.append({
            "time": start,
            "state": state_of(ann),
            "alertname": alertname,
            "labels": labels,
            "id": ann.get("id"),
            "end": int(end) if end and int(end) > start else None,
        })
    return events


def history_to_events(entries: list[tuple[int, dict]]) -> list[dict]:
    """Normalize state-history transitions into common events.

    Only `Alerting` (firing) and `Normal` (resolved) transitions drive incident
    pairing; Pending/NoData/Error transitions are ignored.
    """
    events: list[dict] = []
    for ts_ms, line in entries:
        labels = line.get("labels", {}) or {}
        alertname = labels.get("alertname") or line.get("ruleTitle") or line.get("ruleUID") or "unknown"
        current = str(line.get("current", "")).lower()
        if current.startswith("alerting"):
            state = "firing"
        elif current.startswith(("normal", "ok")):
            state = "resolved"
        else:
            state = ""
        events.append({
            "time": int(ts_ms),
            "state": state,
            "alertname": alertname,
            "labels": labels,
            "id": None,
            "end": None,
        })
    return events


def build_incidents(events: list[dict], to_ms: int) -> list[dict]:
    """Collapse state-change events into one row per firing period.

    Events with an `end` are complete incidents on their own. The rest are
    paired per series: a `firing` opens an incident and the next `resolved`
    closes it; anything still open at report time is reported as ongoing.
    """
    incidents: list[dict] = []
    points: dict[str, list[dict]] = {}

    for ev in events:
        alertname = ev["alertname"]
        labels = ev["labels"]
        start = int(ev["time"])
        end = ev.get("end")
        if end and int(end) > start:
            incidents.append(_incident(ev.get("id"), alertname, labels, start, int(end)))
        else:
            points.setdefault(series_key(alertname, labels), []).append(ev)

    for series in points.values():
        series.sort(key=lambda e: e["time"])
        open_ev: dict | None = None
        for ev in series:
            if ev["state"] == "firing" and open_ev is None:
                open_ev = ev
            elif ev["state"] == "resolved" and open_ev is not None:
                incidents.append(_incident(open_ev.get("id"), open_ev["alertname"], open_ev["labels"],
                                           int(open_ev["time"]), int(ev["time"])))
                open_ev = None
        if open_ev is not None:  # still firing at report time
            incidents.append(_incident(open_ev.get("id"), open_ev["alertname"], open_ev["labels"],
                                        int(open_ev["time"]), None, ongoing_to=to_ms))

    incidents.sort(key=lambda i: i["start_ms"], reverse=True)
    return incidents


def _incident(ann_id, alertname, labels, start_ms, end_ms, ongoing_to=None) -> dict:
    effective_end = end_ms if end_ms is not None else ongoing_to
    duration_s = max(0, (effective_end - start_ms) // 1000) if effective_end else 0
    stable = ann_id if ann_id is not None else hashlib.sha1(
        f"{alertname}|{sorted(labels.items())}|{start_ms}".encode()
    ).hexdigest()[:12]
    instance = instance_of(labels)
    return {
        "incident_id": str(stable),
        "service": normalize_service(service_of(alertname, labels)),
        "alert": alertname,
        "instance": instance,
        "network": network_of(instance),
        "severity": severity_of(alertname, labels),
        "start_ms": start_ms,
        "start_utc": iso(start_ms),
        "end_utc": iso(end_ms) if end_ms is not None else "",
        "duration": humanize(duration_s),
        "duration_s": duration_s,
        "status": "Resolved" if end_ms is not None else "Ongoing",
        "impact": "",
    }


def iso(ms: int | None) -> str:
    if not ms:
        return ""
    return dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def humanize(seconds: int) -> str:
    if seconds <= 0:
        return "0s"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, secs = divmod(rem, 60)
    parts = [f"{days}d" if days else "", f"{hours}h" if hours else "",
             f"{minutes}m" if minutes else "", f"{secs}s" if secs and not days else ""]
    return " ".join(p for p in parts if p) or "0s"


CSV_FIELDS = ["incident_id", "service", "alert", "instance", "network", "severity",
              "start_utc", "end_utc", "duration", "duration_s", "status", "impact", "start_ms"]


def merge_csv(path: str, incidents: list[dict]) -> list[dict]:
    """Merge incidents into the durable CSV, deduped by incident_id."""
    by_id: dict[str, dict] = {}
    if os.path.exists(path):
        with open(path, newline="", encoding="utf-8") as fh:
            for row in csv.DictReader(fh):
                by_id[row["incident_id"]] = row
    for inc in incidents:
        # A later run may see a now-resolved incident that was ongoing before.
        by_id[inc["incident_id"]] = {k: str(inc.get(k, "")) for k in CSV_FIELDS}

    merged = sorted(by_id.values(), key=lambda r: int(r.get("start_ms") or 0), reverse=True)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(merged)
    return merged


def union_seconds(intervals: list[tuple[int, int]]) -> int:
    """Total wall-clock seconds covered by [start_ms, end_ms) intervals.

    Overlapping intervals are merged, so two AZs (or several pods) degraded at
    the same time count once. This is why the report can't just sum per-row
    durations: a single network-wide event fires on every pod in every AZ, and
    summing them inflates the figure several-fold.
    """
    spans = sorted(iv for iv in intervals if iv[1] > iv[0])
    if not spans:
        return 0
    total = 0
    cur_s, cur_e = spans[0]
    for s, e in spans[1:]:
        if s <= cur_e:
            cur_e = max(cur_e, e)
        else:
            total += cur_e - cur_s
            cur_s, cur_e = s, e
    total += cur_e - cur_s
    return total // 1000


def summarize_window(rows: list[dict], frm_ms: int) -> tuple[list[dict], dict[tuple[str, str], dict]]:
    """Filter rows to the window and tally each (service, network) bucket.

    Downtime is the union wall-clock time of the bucket's incidents, not a sum
    of overlapping per-pod rows. Proxy incidents (network `all`) are counted
    against every network, since a proxy outage hits them all at once.
    """
    window = [r for r in rows if int(r.get("start_ms") or 0) >= frm_ms]
    acc: dict[tuple[str, str], dict] = {}
    for r in window:
        net = r.get("network") or network_of(r.get("instance", ""))
        start = int(r.get("start_ms") or 0)
        span = (start, start + int(r.get("duration_s") or 0) * 1000)
        visible = r.get("impact") == "Customer-visible"
        for n in (NETWORKS if net == ALL_NETWORKS else (net,)):
            g = acc.setdefault((r["service"], n),
                               {"count": 0, "visible": 0, "all_iv": [], "vis_iv": []})
            g["count"] += 1
            g["all_iv"].append(span)
            if visible:
                g["visible"] += 1
                g["vis_iv"].append(span)
    by_group = {
        key: {
            "count": g["count"],
            "visible": g["visible"],
            "downtime_s": union_seconds(g["all_iv"]),
            "visible_s": union_seconds(g["vis_iv"]),
        }
        for key, g in acc.items()
    }
    return window, by_group


def build_discord_summary(window: list[dict], by_group: dict[tuple[str, str], dict],
                          frm_ms: int, to_ms: int, source_label: str) -> str:
    visible = sum(1 for r in window if r.get("impact") == "Customer-visible")
    # Rank by customer-visible downtime so the channel sees the worst-hit
    # service/network buckets first.
    top = sorted(by_group, key=lambda k: (by_group[k]["visible_s"], by_group[k]["visible"]),
                 reverse=True)[:10]
    lines = [
        f"**Window:** {iso(frm_ms)} \u2192 {iso(to_ms)}",
        f"**Source:** Grafana {source_label}",
        f"**Total incidents:** {len(window)}",
        f"**Customer-visible:** {visible}  \u00b7  **AZ-redundant:** {len(window) - visible}",
        "",
        "**Top service/network** (customer-visible / total)",
    ]
    for svc, net in top:
        g = by_group[(svc, net)]
        lines.append(f"- {svc} ({net}): {g['visible']}/{g['count']} incidents, "
                     f"{humanize(g['visible_s'])} visible downtime")
    lines.append("")
    lines.append("Customer-visible = all AZs of a workload down at once; downtime is wall-clock "
                 "(overlapping pods/AZs merged). Full report and CSV attached as a zip.")
    # Discord caps embed descriptions at 4096 characters.
    return "\n".join(lines)[:4096]


def zip_report(report_path: str, csv_path: str) -> bytes:
    """Bundle the Markdown report and CSV into a single in-memory zip."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in (report_path, csv_path):
            zf.write(path, arcname=os.path.basename(path))
    return buf.getvalue()


def post_discord(webhook_url: str, title: str, description: str,
                 files: list[tuple[str, bytes, str]]) -> None:
    """POST a summary embed plus file attachments to a Discord webhook."""
    boundary = "----incident" + os.urandom(12).hex()
    payload = {
        "username": "Demeter incident report",
        "embeds": [{"title": title, "description": description, "color": 0x5865F2}],
    }
    parts: list[bytes] = [
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="payload_json"\r\n\r\n',
        json.dumps(payload).encode(),
        b"\r\n",
    ]
    for i, (filename, data, ctype) in enumerate(files):
        parts += [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="files[{i}]"; filename="{filename}"\r\n'.encode(),
            f"Content-Type: {ctype}\r\n\r\n".encode(),
            data,
            b"\r\n",
        ]
    parts.append(f"--{boundary}--\r\n".encode())
    req = urllib.request.Request(
        webhook_url, data=b"".join(parts), method="POST",
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            # Discord's Cloudflare edge returns 403 (error 1010) for the default
            # Python-urllib agent, so send an explicit one.
            "User-Agent": "demeter-incident-report/1.0 (+https://github.com/demeter-run/global)",
        },
    )
    with urllib.request.urlopen(req, timeout=60):
        pass


def render_markdown(rows: list[dict], frm_ms: int, to_ms: int, source_label: str) -> str:
    window, by_group = summarize_window(rows, frm_ms)
    total = len(window)
    visible = sum(1 for r in window if r.get("impact") == "Customer-visible")

    lines = [
        "# Demeter incident & degradation report",
        "",
        f"- Window: **{iso(frm_ms)}** \u2192 **{iso(to_ms)}**",
        f"- Generated: **{iso(int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000))}**",
        f"- Source: Grafana {source_label} (dmtrglobal)",
        f"- Total incidents: **{total}** \u2014 customer-visible: **{visible}**, AZ-redundant: **{total - visible}**",
        "",
        "> Reconstructed from Grafana alert history. In-cluster Prometheus retains",
        "> only 45 days, so this is the authoritative long-term record.",
        ">",
        "> Each workload runs across az1/az2. An incident is **customer-visible**",
        "> only when all AZs of a workload were down at once; a single AZ failing",
        "> while its peer stayed up is **AZ-redundant** and invisible to users.",
        ">",
        "> Buckets are split per network so a testnet (preprod/preview) outage",
        "> doesn't read as a whole-service outage; a network-agnostic proxy counts",
        "> against every network. Degraded time is wall-clock (overlapping pods and",
        "> AZs merged), not a sum of per-pod alerts.",
        "",
        "## Summary by service and network",
        "",
        "| Service | Network | Customer-visible | AZ-redundant | Visible degraded time |",
        "| --- | --- | ---: | ---: | ---: |",
    ]
    for svc, net in sorted(by_group,
                           key=lambda k: (by_group[k]["visible_s"], by_group[k]["visible"]),
                           reverse=True):
        g = by_group[(svc, net)]
        lines.append(f"| {svc} | {net} | {g['visible']} | {g['count'] - g['visible']} "
                     f"| {humanize(g['visible_s'])} |")

    lines += [
        "",
        "## Incidents",
        "",
        "| Start (UTC) | End (UTC) | Duration | Service | Network | Alert | Instance | Severity | Impact | Status |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for r in window:
        end = r.get("end_utc") or DASH
        duration = r.get("duration") or DASH
        inst = r.get("instance") or DASH
        impact = r.get("impact") or DASH
        network = r.get("network") or network_of(r.get("instance", ""))
        lines.append(
            f"| {r['start_utc']} | {end} | {duration} "
            f"| {r['service']} | {network} | {r['alert']} | {inst} "
            f"| {r['severity']} | {impact} | {r['status']} |"
        )
    if not window:
        lines.append("| _no incidents in window_ | | | | | | | | | |")
    lines.append("")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--config", default="config.yaml",
                   help="Decrypted config.yaml with grafana.cloud.url/auth (default: config.yaml).")
    p.add_argument("--months", type=int, default=6,
                   help="Report window in months back from now (default: 6).")
    p.add_argument("--days", type=int, default=None,
                   help="Report window in days back from now; overrides --months when set "
                        "(use for the recurring weekly run).")
    p.add_argument("--source", choices=("state-history", "annotations"), default="state-history",
                   help="Grafana history source (default: state-history, correct for managed rules).")
    p.add_argument("--discord-webhook", default=os.environ.get("DISCORD_WEBHOOK_URL", ""),
                   help="Discord webhook to post the report to (env: DISCORD_WEBHOOK_URL). Skipped if unset.")
    p.add_argument("--discord-from-config", action="store_true",
                   help="If no webhook is given, read grafana.cloud.discord_webhook_url from --config.")
    p.add_argument("--from", dest="frm", help="Override window start (ISO 8601, UTC).")
    p.add_argument("--to", dest="to", help="Override window end (ISO 8601, UTC).")
    p.add_argument("--out-dir", default="report-out", help="Output directory (default: report-out).")
    p.add_argument("--csv-name", default="incidents.csv", help="Durable CSV filename.")
    p.add_argument("--report-name", default="report-latest.md", help="Markdown snapshot filename.")
    return p.parse_args()


def to_ms_from_iso(value: str) -> int:
    d = dt.datetime.fromisoformat(value)
    if d.tzinfo is None:
        d = d.replace(tzinfo=dt.timezone.utc)
    return int(d.timestamp() * 1000)


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(dt.timezone.utc)
    to_ms = to_ms_from_iso(args.to) if args.to else int(now.timestamp() * 1000)
    if args.frm:
        frm_ms = to_ms_from_iso(args.frm)
    elif args.days is not None:
        frm = now - dt.timedelta(days=args.days)
        frm_ms = int(frm.timestamp() * 1000)
    else:
        frm = now - dt.timedelta(days=int(args.months * 30.44))
        frm_ms = int(frm.timestamp() * 1000)

    base_url, token = resolve_grafana(args.config)
    if args.source == "annotations":
        eprint(f"Fetching alert annotations from {base_url} for {iso(frm_ms)} -> {iso(to_ms)} ...")
        events = annotations_to_events(fetch_alert_annotations(base_url, token, frm_ms, to_ms))
        source_label = "alert state-change annotations"
    else:
        eprint(f"Fetching alert state history from {base_url} for {iso(frm_ms)} -> {iso(to_ms)} ...")
        events = history_to_events(fetch_state_history(base_url, token, frm_ms, to_ms))
        source_label = "alert state history (/api/v1/rules/history)"
    eprint(f"Fetched {len(events)} state events.")

    incidents = build_incidents(events, to_ms)
    incidents = [i for i in incidents if i["service"] not in EXCLUDE_SERVICES]
    classify_impact(incidents)
    csv_path = os.path.join(args.out_dir, args.csv_name)
    merged = merge_csv(csv_path, incidents)

    report = render_markdown(merged, frm_ms, to_ms, source_label)
    report_path = os.path.join(args.out_dir, args.report_name)
    with open(report_path, "w", encoding="utf-8") as fh:
        fh.write(report)

    eprint(f"Wrote {len(incidents)} incidents this run; {len(merged)} total in {csv_path}.")
    eprint(f"Report snapshot: {report_path}")

    if args.discord_webhook or args.discord_from_config:
        webhook = args.discord_webhook or webhook_from_config(args.config)
        if not webhook:
            eprint("No Discord webhook resolved; skipping delivery.")
            return 0
        window, by_group = summarize_window(merged, frm_ms)
        description = build_discord_summary(window, by_group, frm_ms, to_ms, source_label)
        zip_name = f"demeter-incident-report-{now.strftime('%Y%m%d')}.zip"
        zip_bytes = zip_report(report_path, csv_path)
        files = [(zip_name, zip_bytes, "application/zip")]
        eprint("Posting report to Discord ...")
        try:
            post_discord(webhook, "Demeter incident & degradation report",
                         description, files)
        except urllib.error.HTTPError as err:
            eprint(f"Discord API error {err.code}: {err.read().decode('utf-8', 'replace')[:300]}")
            return 1
        eprint("Posted to Discord.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
