#!/usr/bin/env python3
"""Derive the guarded Overleaf status from exact committed manuscript bytes.

This is not scientific certification. It recognizes the specifically marked
historical GloFAS review draft and requires all of its reader-facing notices.
Supported notices are exact top-level document-body commands, outside comments,
macro arguments, and the common conditional/comment contexts rejected below.
This conservative source check is not a general TeX visibility interpreter.
It uses only Python's standard library and supports Python 3.6.
"""

import argparse
import re
import subprocess
import sys


DRAFT_MARKERS = (
    ("main.tex", "analysis notice", r"""\noindent\textit{[The issued-window analysis is being recomputed under the
unit-member likelihood specified below. Its numerical results and displays
in this draft remain from the earlier weighted analysis.]}"""),
    ("main.tex", "historical results notice", r"""\noindent\textit{[The following comparison is retained as the historical
weighted analysis until all six unit-member refits and their scoring checks
are complete; it is not a result of the revised likelihood.]}"""),
    ("main.tex", "historical table caption", r"""\caption{Historical weighted forecast correction at the 25 December 2022
origin, retained pending the unit-member refits."""),
    ("main.tex", "historical figure caption", r"""\caption{Streamflow data and two historical weighted quantile forecasts at
the 25 December 2022 origin, retained pending the unit-member refits."""),
    ("main.tex", "pending discussion notice", r"""\textit{[Streamflow findings will be updated after the unit-member refits.]}"""),
    ("qdesn-supplement.tex", "supplement historical results notice", r"""\textit{[The following issued-window numerical summaries and displays
describe the historical weighted analysis. They will be replaced together
after the unit-member refits and their checks are complete.]}"""),
)

# Recognize partial notice loss as pending too; the full set below must still
# be present. These signals are deliberately specific to this correction.
PENDING_SIGNALS = (
    "The issued-window analysis is being recomputed",
    "in this draft remain from the earlier weighted analysis.",
    "weighted analysis until all six unit-member refits",
    "retained pending the unit-member refits.",
    "Streamflow findings will be updated after the unit-member refits.",
    "after the unit-member refits and their checks are complete.",
    "the numerical summaries below are explicitly historical until the corresponding refits are complete.",
)


class DraftStatusError(Exception):
    pass


def normalize(text):
    return " ".join(text.split())


def without_tex_comments(text):
    """Ignore commented notices, respecting escaped percent signs."""
    visible = []
    for line in text.splitlines():
        for index, char in enumerate(line):
            if char != "%":
                continue
            backslashes = 0
            previous = index - 1
            while previous >= 0 and line[previous] == "\\":
                backslashes += 1
                previous -= 1
            if backslashes % 2 == 0:
                line = line[:index]
                break
        visible.append(line)
    return "\n".join(visible)


def committed_document(source_commit, path):
    try:
        raw = subprocess.check_output(
            ["git", "show", "{}:{}".format(source_commit, path)],
            stderr=subprocess.PIPE,
        )
        text = raw.decode("utf-8")
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError):
        raise DraftStatusError("cannot read committed {} at {}".format(path, source_commit))
    return without_tex_comments(text)


def document_body(text):
    """Do not accept notices hidden in a preamble or after the document."""
    begin = r"\begin{document}"
    end = r"\end{document}"
    if text.count(begin) != 1 or text.count(end) != 1:
        raise DraftStatusError("pending draft requires one visible document environment")
    if text.index(end) < text.index(begin):
        raise DraftStatusError("pending draft has an invalid document environment")
    body = text.split(begin, 1)[1].split(end, 1)[0]
    if re.search(r"\\(?:iffalse|iftrue|ifnum|ifdefined|ifx|ifcase)\b|\\begin\{comment\}", body):
        raise DraftStatusError("pending draft notices must not depend on hidden or conditional document text")
    return normalize(body)


def top_level_at(text, position):
    """Reject notices stored inside unused macros or other brace arguments."""
    depth = 0
    backslashes = 0
    for char in text[:position]:
        if char in "{}" and backslashes % 2 == 0:
            depth += 1 if char == "{" else -1
            if depth < 0:
                return False
        backslashes = backslashes + 1 if char == "\\" else 0
    return depth == 0


def source_status(source_commit):
    documents = {
        path: committed_document(source_commit, path)
        for path in ("main.tex", "qdesn-supplement.tex")
    }
    pending = any(
        signal in normalize(document)
        for document in documents.values()
        for signal in PENDING_SIGNALS
    )
    if not pending:
        return "release"
    bodies = {path: document_body(document) for path, document in documents.items()}
    for path, name, notice in DRAFT_MARKERS:
        normalized_notice = normalize(notice)
        if (bodies[path].count(normalized_notice) != 1 or
                not top_level_at(bodies[path], bodies[path].find(normalized_notice))):
            raise DraftStatusError(
                "REVIEW_DRAFT_NOTICE_INVALID: {} must contain exactly one visible top-level {}".format(path, name)
            )
    return "review-draft"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_commit")
    parser.add_argument("--require-authorization", action="store_true")
    parser.add_argument("--review-draft", action="store_true")
    args = parser.parse_args()
    try:
        if not re.fullmatch(r"[0-9a-f]{40}", args.source_commit):
            raise DraftStatusError("source commit must be a lowercase 40-character commit hash")
        status = source_status(args.source_commit)
        if status == "review-draft" and args.require_authorization and not args.review_draft:
            raise DraftStatusError(
                "GLOFAS_CORRECTION_PENDING: corrected results are not approved for release; "
                "use --review-draft only to publish the explicitly marked historical draft"
            )
    except DraftStatusError as error:
        print("OVERLEAF_REVIEW_DRAFT_ERROR: {}".format(error), file=sys.stderr)
        return 1
    print(status)
    return 0


if __name__ == "__main__":
    sys.exit(main())
