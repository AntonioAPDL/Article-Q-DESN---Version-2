"""PriceFM graph-neighbor helpers used by article-local DESN adapters.

The adjacency mirrors the released PriceFM helper so article runs do not depend
on the ignored external checkout being importable at runtime.
"""

from __future__ import annotations

from collections import deque
import hashlib
import json


GRAPH_NEIGHBOR_POLICIES = {
    "graph_khop",
    "graph_summary_mean",
    "graph_summary_mean_std",
    "graph_neighbor_direct",
    "graph_neighbor_spread_summary",
}


def graph_adj_matrix():
    """Return the released PriceFM region adjacency dictionary."""
    return {
        "AT": ["AT", "CZ", "DE_LU", "HU", "IT_NORD", "SI"],
        "BE": ["BE", "DE_LU", "FR", "NL"],
        "BG": ["BG", "GR", "RO"],
        "CZ": ["AT", "CZ", "DE_LU", "PL", "SK"],
        "DE_LU": ["AT", "BE", "CZ", "DK_1", "DK_2", "DE_LU", "FR", "NL", "NO_2", "PL", "SE_4"],
        "DK_1": ["DE_LU", "DK_1", "DK_2", "NL", "NO_2", "SE_3"],
        "DK_2": ["DE_LU", "DK_1", "DK_2", "SE_4"],
        "EE": ["EE", "FI", "LV"],
        "ES": ["ES", "FR", "PT"],
        "FI": ["EE", "FI", "NO_4", "SE_1", "SE_3"],
        "FR": ["BE", "DE_LU", "ES", "FR", "IT_NORD"],
        "GR": ["BG", "GR", "IT_SUD"],
        "HR": ["HR", "HU", "SI"],
        "HU": ["AT", "HR", "HU", "RO", "SI", "SK"],
        "IT_CALA": ["IT_CALA", "IT_SICI", "IT_SUD"],
        "IT_CNOR": ["IT_CNOR", "IT_CSUD", "IT_NORD"],
        "IT_CSUD": ["IT_CNOR", "IT_CSUD", "IT_SARD", "IT_SUD"],
        "IT_NORD": ["AT", "FR", "IT_CNOR", "IT_NORD", "SI"],
        "IT_SARD": ["IT_CSUD", "IT_SARD"],
        "IT_SICI": ["IT_CALA", "IT_SICI"],
        "IT_SUD": ["GR", "IT_CALA", "IT_CSUD", "IT_SUD"],
        "LT": ["LT", "LV", "PL", "SE_4"],
        "LV": ["EE", "LT", "LV"],
        "NL": ["BE", "DK_1", "DE_LU", "NL", "NO_2"],
        "NO_1": ["NO_1", "NO_2", "NO_3", "NO_5", "SE_3"],
        "NO_2": ["DE_LU", "DK_1", "NL", "NO_1", "NO_2", "NO_5"],
        "NO_3": ["NO_1", "NO_3", "NO_4", "NO_5", "SE_2"],
        "NO_4": ["FI", "NO_3", "NO_4", "SE_1", "SE_2"],
        "NO_5": ["NO_1", "NO_2", "NO_3", "NO_5"],
        "PL": ["CZ", "DE_LU", "LT", "PL", "SE_4", "SK"],
        "PT": ["ES", "PT"],
        "RO": ["BG", "HU", "RO"],
        "SE_1": ["FI", "NO_4", "SE_1", "SE_2"],
        "SE_2": ["NO_3", "NO_4", "SE_1", "SE_2", "SE_3"],
        "SE_3": ["DK_1", "FI", "NO_1", "SE_2", "SE_3", "SE_4"],
        "SE_4": ["DE_LU", "DK_2", "LT", "PL", "SE_3", "SE_4"],
        "SI": ["AT", "HR", "HU", "IT_NORD", "SI"],
        "SK": ["CZ", "HU", "PL", "SK"],
    }


def graph_hash(adjacency=None):
    adjacency = graph_adj_matrix() if adjacency is None else adjacency
    payload = {str(k): [str(x) for x in v] for k, v in sorted(adjacency.items())}
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def get_k_hop_regions(target_region, input_regions, degree, adjacency=None):
    """Return target plus k-hop neighbors, restricted to input_regions.

    The output order follows PriceFM: target first, then input_regions order.
    """
    adjacency = graph_adj_matrix() if adjacency is None else adjacency
    degree = int(degree)
    if degree < 0:
        raise ValueError("graph_degree must be >= 0")
    input_regions = [str(x) for x in input_regions]
    target_region = str(target_region)
    allowed = set(input_regions)
    if target_region not in allowed:
        raise ValueError("target_region '{}' must be in input_regions".format(target_region))
    if target_region not in adjacency:
        raise ValueError("target_region '{}' is absent from the PriceFM graph".format(target_region))

    visited = {target_region}
    q = deque([(target_region, 0)])
    while q:
        node, dist = q.popleft()
        if dist == degree:
            continue
        for nb in adjacency.get(node, []):
            if nb in allowed and nb not in visited:
                visited.add(nb)
                q.append((nb, dist + 1))
    return [target_region] + [region for region in input_regions if region in visited and region != target_region]


def graph_scope_manifest(target_region, input_regions, degree, adjacency=None):
    adjacency = graph_adj_matrix() if adjacency is None else adjacency
    active_regions = get_k_hop_regions(target_region, input_regions, degree, adjacency=adjacency)
    return {
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": graph_hash(adjacency),
        "graph_degree": int(degree),
        "target_region": str(target_region),
        "input_regions": [str(x) for x in input_regions],
        "active_regions": active_regions,
        "n_input_regions": int(len(input_regions)),
        "n_active_regions": int(len(active_regions)),
    }


def graph_policy_requires_neighbor_windows(feature_policy):
    """Return whether a PriceFM feature policy needs graph-neighbor windows."""
    return str(feature_policy) in GRAPH_NEIGHBOR_POLICIES


def graph_active_regions_for_policy(
    target_region,
    input_regions,
    feature_policy,
    spatial=None,
    adjacency=None,
):
    """Return active window regions for a PriceFM feature policy.

    For legacy graph policies this is the ordinary k-hop scope.  For
    ``graph_neighbor_direct`` the scope may be narrowed by explicit
    ``neighbor_regions`` or by ``max_neighbor_regions`` while preserving the
    target region as the first element.
    """
    feature_policy = str(feature_policy)
    if not graph_policy_requires_neighbor_windows(feature_policy):
        return [str(target_region)]

    spatial = dict(spatial or {})
    degree = int(spatial.get("graph_degree", spatial.get("degree", 1)))
    graph = graph_scope_manifest(target_region, input_regions, degree, adjacency=adjacency)
    active_regions = list(graph["active_regions"])
    if feature_policy not in ("graph_neighbor_direct", "graph_neighbor_spread_summary"):
        return active_regions

    target_region = str(target_region)
    available_neighbors = active_regions[1:]
    explicit = spatial.get("neighbor_regions")
    if explicit is None:
        neighbors = available_neighbors
    else:
        neighbors = [str(x) for x in explicit]
        unknown = [x for x in neighbors if x not in available_neighbors]
        if unknown:
            raise ValueError(
                "{} neighbor_regions must be within the "
                "{}-hop scope for {}: {}".format(feature_policy, degree, target_region, unknown)
            )

    if "max_neighbor_regions" in spatial and spatial["max_neighbor_regions"] not in (None, ""):
        max_neighbors = int(spatial["max_neighbor_regions"])
        if max_neighbors < 0:
            raise ValueError("max_neighbor_regions must be non-negative")
        neighbors = neighbors[:max_neighbors]

    return [target_region] + [x for x in neighbors if x != target_region]


def graph_scope_manifest_for_policy(
    target_region,
    input_regions,
    feature_policy,
    spatial=None,
    adjacency=None,
):
    """Return a graph manifest after feature-policy narrowing."""
    spatial = dict(spatial or {})
    degree = int(spatial.get("graph_degree", spatial.get("degree", 1)))
    graph = graph_scope_manifest(target_region, input_regions, degree, adjacency=adjacency)
    active_regions = graph_active_regions_for_policy(
        target_region,
        input_regions,
        feature_policy,
        spatial=spatial,
        adjacency=adjacency,
    )
    graph = dict(graph)
    graph["feature_policy"] = str(feature_policy)
    graph["active_regions"] = active_regions
    graph["neighbor_regions"] = active_regions[1:]
    graph["n_active_regions"] = int(len(active_regions))
    graph["n_neighbor_regions"] = int(max(0, len(active_regions) - 1))
    if str(feature_policy) in ("graph_neighbor_direct", "graph_neighbor_spread_summary"):
        graph["scope_narrowing"] = {
            "neighbor_regions": [str(x) for x in spatial.get("neighbor_regions", [])],
            "max_neighbor_regions": spatial.get("max_neighbor_regions", None),
        }
    return graph
