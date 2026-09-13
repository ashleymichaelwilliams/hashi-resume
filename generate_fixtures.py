#!/usr/bin/env python3
"""
generate_fixtures.py

Extracts text from a PDF resume and generates a Consul KV fixtures shell
script (fixtures.sh) that populates Consul with the resume data.

Usage:
    python3 generate_fixtures.py
    python3 generate_fixtures.py --pdf /path/to/resume.pdf --output fixtures.sh

The script performs three logical steps:
  1. PDF text extraction (via pypdf)
  2. Structured parsing / data-point mapping
  3. Shell-safe fixtures.sh generation

Mapping from resume sections -> Consul KV keys:
  Contact line  -> $1/address, $1/email
  Profile block -> $1/profile_summary
  Each company  -> $1/org/<N>/name          (includes location + dates)
  Each position -> $1/org/<N>/position/<P>/name
  Each bullet   -> $1/org/<N>/position/<P>/tasks/<T>
"""

import re
import shutil
import sys
from pathlib import Path

try:
    from pypdf import PdfReader
except ImportError:
    print("Error: pypdf is not installed. Run: pip3 install pypdf", file=sys.stderr)
    sys.exit(1)


DEFAULT_PDF_PATH = "/Users/ashley.williams/Downloads/Ashley Williams - Staff Platform Engineer (Revised).pdf"
DEFAULT_OUTPUT_PATH = Path(__file__).resolve().parent / "fixtures.sh"
BACKUP_PATH = DEFAULT_OUTPUT_PATH.parent / "fixtures-original.sh"


# ---------------------------------------------------------------------------
# Step 1 – PDF text extraction
# ---------------------------------------------------------------------------

def extract_pdf_text(pdf_path: str) -> str:
    """Extract raw text from every page of the PDF and return it as a single
    string.  Newlines in the extracted text correspond to layout line breaks,
    so multi-line paragraphs may be split across several Python string lines.
    """
    reader = PdfReader(pdf_path)
    text = "\n".join(page.extract_text() or "" for page in reader.pages)
    return text


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

EMAIL_RE = re.compile(r"[\w.+-]+@[\w.-]+\.\w+")
PHONE_RE = re.compile(r"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b")
ALL_CAPS_RE = re.compile(r"^[A-Z][A-Z0-9 ,.&/+-]+$")
BULLET_RE = re.compile(r"^\s*[\u2022\u2023\u25E6\u2022]\s+")


def shell_escape(value: str) -> str:
    """Escape a string so it is safe inside a double-quoted shell value.

    Characters that trigger command substitution or variable expansion
    (``$``, backtick, ``\\``, ``"``) are backslash-escaped.
    """
    value = value.replace("\\", "\\\\")
    value = value.replace("$", "\\$")
    value = value.replace("`", "\\`")
    value = value.replace('"', '\\"')
    return value


# ---------------------------------------------------------------------------
# Step 2 – Structured parsing / mapping
# ---------------------------------------------------------------------------

class ResumeData:
    """Container for parsed resume fields."""

    def __init__(self):
        self.name = ""
        self.address = ""
        self.email = ""
        self.phone = ""
        self.profile_summary = ""
        self.orgs: list[dict] = []


def _clean_spaces(text: str) -> str:
    """Collapse runs of whitespace (including stray newlines) into single spaces."""
    return re.sub(r"\s+", " ", text).strip()


def parse_resume(text: str) -> ResumeData:
    """Parse the raw PDF text into a :class:`ResumeData` instance.

    Parsing strategy (state-machine over the list of text lines):

    * **Name** – first non-empty line in ALL CAPS.
    * **Contact info** – the line containing ``@``; split on ``|`` to obtain
      *address*, *email*, and *phone*.
    * **Profile summary** – the paragraph between the contact line and the
      next section header (``IMPACT``, ``TECHNICAL EXPERTISE``, etc.).
    * **Professional experience** – everything after the
      ``PROFESSIONAL EXPERIENCE`` header is parsed for companies and roles.

    Each *company header* is a line containing ``|`` whose left-most segment
    is ALL-CAPS (e.g. ``LYTX, INC.  |  Remote | March 2021 - Present``).  Lines
    immediately following a company header that do **not** start with a bullet
    and do **not** contain ``|`` are treated as *position titles*.  Lines
    starting with ``•`` are *task bullets*; non-bullet continuation lines are
    appended to the current task.

    Blank lines are preserved (not filtered) so that paragraph boundaries
    can be used to distinguish new position titles from continuation lines
    of a previous bullet.
    """
    # Keep empty lines — they are paragraph separators.
    lines = [ln.strip() for ln in text.split("\n")]

    data = ResumeData()
    idx = 0
    n = len(lines)

    # --- Name (first non-empty ALL-CAPS line) ---
    while idx < n and (not lines[idx] or not ALL_CAPS_RE.match(lines[idx])):
        idx += 1
    if idx < n:
        data.name = lines[idx]
        idx += 1

    # --- Contact info line (contains @) ---
    while idx < n and "@" not in lines[idx]:
        idx += 1
    if idx < n:
        contact_line = lines[idx]
        idx += 1
        parts = [p.strip() for p in contact_line.split("|")]
        for part in parts:
            m = EMAIL_RE.search(part)
            if m:
                data.email = m.group()
            else:
                m = PHONE_RE.search(part)
                if m:
                    data.phone = m.group()
                elif part:
                    data.address = part

    # --- Profile summary (until first ALL-CAPS section header) ---
    summary_parts: list[str] = []
    while idx < n:
        line = lines[idx]
        if not line:
            idx += 1
            continue
        if ALL_CAPS_RE.match(line):
            break
        summary_parts.append(_clean_spaces(line))
        idx += 1
    summary_parts = [s for s in summary_parts if s]
    data.profile_summary = " ".join(summary_parts)

    # --- Skip to PROFESSIONAL EXPERIENCE ---
    while idx < n and "PROFESSIONAL EXPERIENCE" not in lines[idx].upper():
        idx += 1
    idx += 1  # move past the header

    # --- Parse orgs / positions / tasks ---
    current_org: dict | None = None
    current_pos: dict | None = None
    prev_was_blank = False

    for i in range(idx, n):
        line = lines[i]

        if not line:
            prev_was_blank = True
            continue

        # Company header: contains '|' and the left-most segment is ALL-CAPS.
        if "|" in line:
            left_segment = line.split("|")[0].strip()
            if left_segment and ALL_CAPS_RE.match(left_segment):
                if current_org:
                    data.orgs.append(current_org)
                clean = re.sub(r"\s*\|\s*", " | ", line)
                current_org = {"name": clean, "positions": []}
                current_pos = None
                prev_was_blank = False
                continue

        # Bullet / task line — always starts a new task.
        bullet_match = BULLET_RE.match(line)
        if bullet_match:
            task_text = line[bullet_match.end():].strip()
            if current_pos is not None:
                current_pos["tasks"].append(task_text)
            prev_was_blank = False
            continue

        # Non-bullet, non-company line.
        if current_org is not None:
            if current_pos is None or prev_was_blank:
                # New position title (blank line or first line after header).
                current_pos = {"title": line, "tasks": []}
                current_org["positions"].append(current_pos)
            elif current_pos["tasks"]:
                # Continuation of the previous bullet's text.
                current_pos["tasks"][-1] += " " + line

        prev_was_blank = False

    if current_org:
        data.orgs.append(current_org)

    return data


# ---------------------------------------------------------------------------
# Step 3 – Generate fixtures.sh
# ---------------------------------------------------------------------------

def generate_fixtures(data: ResumeData) -> str:
    """Render the :class:`ResumeData` into a fixtures.sh shell script."""
    lines: list[str] = ["# Populate Consul with Data"]
    lines.append(f'consul kv put "$1/address" "{shell_escape(data.address)}"')
    lines.append(f'consul kv put "$1/email" "{shell_escape(data.email)}"')
    lines.append(f'consul kv put "$1/profile_summary" "{shell_escape(data.profile_summary)}"')
    lines.append("")

    for org_idx, org in enumerate(data.orgs):
        lines.append(
            f'consul kv put "$1/org/{org_idx}/name" "{shell_escape(org["name"])}"'
        )
        for pos_idx, pos in enumerate(org["positions"]):
            lines.append(
                f'consul kv put "$1/org/{org_idx}/position/{pos_idx}/name" "{shell_escape(pos["title"])}"'
            )
            for task_idx, task in enumerate(pos["tasks"]):
                lines.append(
                    f'consul kv put "$1/org/{org_idx}/position/{pos_idx}/tasks/{task_idx}" "{shell_escape(task)}"'
                )
        lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate fixtures.sh from a PDF resume."
    )
    parser.add_argument(
        "--pdf", default=DEFAULT_PDF_PATH,
        help="Path to the resume PDF (default: %(default)s)",
    )
    parser.add_argument(
        "--output", default=str(DEFAULT_OUTPUT_PATH),
        help="Output fixtures.sh path (default: %(default)s)",
    )
    parser.add_argument(
        "--no-backup", action="store_true",
        help="Do not create fixtures-original.sh backup.",
    )
    args = parser.parse_args()

    pdf_path = args.pdf
    output_path = Path(args.output)

    # Step 1 – extract
    print(f"[1/3] Extracting text from {pdf_path} ...")
    text = extract_pdf_text(pdf_path)
    print(f"      Extracted {len(text)} characters across {text.count(chr(10))} lines.")

    # Step 2 – parse
    print("[2/3] Parsing resume data ...")
    data = parse_resume(text)
    print(f"      Name:              {data.name}")
    print(f"      Address:           {data.address}")
    print(f"      Email:             {data.email}")
    print(f"      Profile summary:   {len(data.profile_summary)} chars")
    print(f"      Organizations:     {len(data.orgs)}")
    for i, org in enumerate(data.orgs):
        print(f"        Org {i}: {org['name']}  ({len(org['positions'])} positions)")

    # Step 3 – generate
    print("[3/3] Generating fixtures.sh ...")
    if not args.no_backup and output_path.exists():
        backup = output_path.parent / "fixtures-original.sh"
        shutil.copy2(output_path, backup)
        print(f"      Backed up current fixtures.sh -> {backup}")

    content = generate_fixtures(data)
    output_path.write_text(content + "\n", encoding="utf-8")
    output_path.chmod(0o755)
    print(f"      Wrote {len(content.splitlines())} lines to {output_path}")


if __name__ == "__main__":
    main()
