#!/usr/bin/env python3
"""Render two editorial derivatives from immutable, authenticated inputs.

No fit, forecast, score or original display is changed. ``--check`` compares
the deterministic rendering with the committed derivatives without writing.
"""
import argparse
import csv
import hashlib
import math
import re
from pathlib import Path


BASELINE_COMMIT = "1b249255018715dd3bdc3c95389c80702d26c8c9"
SOURCE_SHA256 = {
    "tables/appendix_compact_20261106_ind_forecast_mae.tex": "a1c938839d88006e5ed860a1e4baa6a8fdbc1a7d657b2f4af9404a33a3f4340f",
    "tables/qdesn_multiquantile_crossing_display.tex": "90ad26ea2a15c6459fdd2282fd3c43641254d60fe1d0241051ccde5f6b640f75",
    "tables/joint_qdesn_pure_desn_v2_crossing_rates.csv": "50df3e3750d9b0e85d212d0cb6157048b130fc9aa25e23559b21fa622726c7a3",
    "tables/joint_qdesn_pure_desn_v2_forecast_score_summary.csv": "9dacd530801674de5baa32624b38225dbb35ef1f3424548b34519b8fa78c16f0",
    "tables/joint_qdesn_pure_desn_v2_fit_oracle_diagnostics.csv": "042f25708c638310115363ee9dccb09be445dd6df02fd1e4fbd2d7530d7c1bd0",
    "tables/joint_qdesn_pure_desn_v2_draw_cardinality.csv": "a14f94470c8497caa11a94d6396d44a43bbfc38e7e9af5f0b69a54a8ee52c1c8",
}
# These are literal baseline TeX blocks, not CSV-generated quantities.
LITERAL_TABLE_SHA256 = {
    "tab:simulation-dgp": "420d997290bd28aae1e3f49a137ce75d13f46975663b6734736552234303894d",
    "tab:supp-mq-generating-coefficients": "ad0dc0afa06a05955963b260f2eaa7e1ee4617d46a045a65aa9fbd71f2964ca7",
    "tab:supp-pricefm-fold-design": "e5dca388e9d6413d8a2eec45d5548f2af78f7a5447c936bc7cda8b1934e3870e",
}
PREFIX = "tables/joint_qdesn_pure_desn_v2_"
MODELS = (
    ("joint_qdesn_rhs_mcmc", "MQ--DESN (AL)"),
    ("qdesn_rhs_independent_mcmc", "Q--DESN (AL)"),
    ("joint_exqdesn_rhs_mcmc", "MQ--DESN (exAL)"),
    ("exqdesn_rhs_independent_mcmc", "Q--DESN (exAL)"),
)
SCENARIOS = frozenset((
    "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
    "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
    "regime_shift", "student_t_location_scale",
))


def require(ok, message):
    if not ok:
        raise ValueError(message)


def read_rows(root, name):
    with (root / (PREFIX + name)).open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def keyed_mcmc(rows):
    selected = [row for row in rows if row["inference_method"] == "mcmc"]
    result = {(r["scenario_id"], r["model_cell_id"]): r for r in selected}
    expected = {(s, s + "__" + m.removesuffix("_mcmc")) for s in SCENARIOS for m, _ in MODELS}
    require(len(selected) == len(result) == 32 and set(result) == expected,
            "Frozen source does not contain the exact 32 unique MCMC keys")
    return result


def close(a, b):
    return math.isclose(float(a), float(b), rel_tol=1e-11, abs_tol=1e-12)


def build_outputs(root):
    root = Path(root)
    for name, expected in SOURCE_SHA256.items():
        actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
        require(actual == expected, "Immutable source hash changed: " + name)
    tables = re.findall(r"\\begin\{table\}.*?\\end\{table\}",
                        (root / "qdesn-supplement.tex").read_text(), re.S)
    for label, expected in LITERAL_TABLE_SHA256.items():
        blocks = [block for block in tables if "\\label{" + label + "}" in block]
        require(len(blocks) == 1 and hashlib.sha256(blocks[0].encode()).hexdigest() == expected,
                "Literal generating/fold table differs from immutable baseline: " + label)
    old_mae = (root / "tables/appendix_compact_20261106_ind_forecast_mae.tex").read_text()
    old_crossing = (root / "tables/qdesn_multiquantile_crossing_display.tex").read_text()
    mae = old_mae.replace(
        "% Presentation-only derivative; scripts/build_appendix_compact_tables_20261106.py",
        "% Presentation-only derivative; scripts/build_appendix_essential_displays_20261106.py",
    ).replace(
        "Corresponding 500-target panels use the same horizontal limits; intervals depend on the model-specific draw construction.",
        "The 500-target sensitivity is summarized in the text; complete panels remain in the computational-materials archive. Intervals depend on the model-specific draw construction.",
    )
    require(mae != old_mae and "Corresponding 500-target panels" not in mae,
            "MAE caption source no longer matches the approved revision")
    require(re.findall(r"\\includegraphics[^\n]*", mae) == re.findall(r"\\includegraphics[^\n]*", old_mae),
            "MAE figure identity or dimensions changed")
    scores = keyed_mcmc(read_rows(root, "forecast_score_summary.csv"))
    fit = keyed_mcmc(read_rows(root, "fit_oracle_diagnostics.csv"))
    counts = keyed_mcmc(read_rows(root, "draw_cardinality.csv"))
    rates = {row["model_id"]: row for row in read_rows(root, "crossing_rates.csv")}
    require(set(rates) == {m for m, _ in MODELS}, "Crossing source model keys changed")
    numeric_rows = []
    for mid, label in MODELS:
        keys = sorted(key for key, row in scores.items() if row["model_id"] == mid)
        require(len(keys) == 8, "Incomplete scenario block: " + mid)
        for key in keys:
            expected_draws = 7500 if mid.startswith(("joint_ex", "exq")) and key[0] == "laplace_bridge" else 3750
            require(int(counts[key]["n_score_draws"]) == expected_draws,
                    "Scored draw count differs from caption: " + str(key))
        computed = {
            "fit_opportunities": 8 * 500 * 6,
            "forecast_opportunities": 8 * 990 * 6,
            "fit_raw_pairs": sum(float(fit[k]["fit_raw_crossing_pairs"]) for k in keys),
            "forecast_raw_pairs": sum(float(scores[k]["canonical_raw_crossing_pairs"]) for k in keys),
            "posterior_forecast_raw_percent_equal_scenario": sum(
                100 * float(scores[k]["raw_crossing_pairs"]) /
                (int(counts[k]["n_score_draws"]) * 990 * 6) for k in keys) / 8,
            "mean_abs_adjustment": sum(float(scores[k]["canonical_mean_abs_monotone_adjustment"]) for k in keys) / 8,
            "max_abs_adjustment": max(float(scores[k]["canonical_max_abs_monotone_adjustment"]) for k in keys),
        }
        for name, value in computed.items():
            require(close(value, rates[mid][name]), "Crossing aggregation differs: " + mid + " " + name)
        values = [100 * computed["fit_raw_pairs"] / computed["fit_opportunities"],
                  100 * computed["forecast_raw_pairs"] / computed["forecast_opportunities"],
                  computed["posterior_forecast_raw_percent_equal_scenario"]]
        row = label + " & " + " & ".join(format(v, ".2f") for v in values)
        row += " & " + format(computed["mean_abs_adjustment"], ".4f") + " / " + format(computed["max_abs_adjustment"], ".4f") + r" \\"
        require(row in old_crossing, "Existing numerical display disagrees with frozen keys: " + mid)
        numeric_rows.append(row)
    crossing = old_crossing.replace(
        r"\shortstack{Mean and maximum\\adjustment}",
        r"\shortstack{Mean forecast-grid\\adjustment (mean, max.)}",
    ).replace(
        "Adjustment magnitudes are on the response scale.",
        "Adjustments are the equal-scenario mean and overall maximum for the posterior-mean forecast grids, on the response scale; they are not posterior-draw averages.",
    )
    require(crossing != old_crossing, "Crossing caption source no longer matches")
    require(all(row in crossing for row in numeric_rows), "Crossing numerical rows changed")
    return {
        "tables/appendix_essential_20261106_ind_forecast_mae.tex": mae,
        "tables/appendix_essential_20261106_mq_crossings.tex": crossing,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = build_outputs(args.root)
    for name, content in outputs.items():
        target = args.root / name
        if args.check:
            require(target.is_file() and target.read_text() == content,
                    "Editorial derivative missing or stale: " + name)
        else:
            target.write_text(content, encoding="utf-8")
    print("APPENDIX_ESSENTIAL_DISPLAYS=PASS files=2 immutable_sources=" + str(len(SOURCE_SHA256)))


if __name__ == "__main__":
    main()
