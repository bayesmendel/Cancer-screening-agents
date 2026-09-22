#!/usr/bin/env python3
"""
two_agent_system_parameters.py

A two-agent "agentic" conversation system using the OpenAI Responses API,
specialized for estimating cancer natural-history and screening parameters.

- The user provides a problem description in the terminal.
- A ProposerAgent proposes/refines a solution using ChatGPT.
- A CriticAgent critiques the solution using ChatGPT and optional HTTP checks
  on references (URLs).
- The conversation continues for up to MAX_ROUNDS, or until the Critic explicitly
  agrees with the solution.
- A summarizer agent always extracts a final parameter table from the last
  Proposer solution, even if no agreement is reached.
- The final parameter table is saved to file.

Dependencies:
    pip install openai striprtf
"""

from __future__ import annotations

import os
import re
import sys
import pandas as pd
from typing import Any, Dict, List, Optional
from dataclasses import dataclass

import urllib.request
import urllib.error
from datetime import datetime
import json
import argparse

from openai import OpenAI
from openai.types.chat import ChatCompletionMessageParam

# Optional RTF support
try:
    from striprtf.striprtf import rtf_to_text
except ImportError:
    rtf_to_text = None

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MODEL_NAME: str = "gpt-5.5"
MAX_ROUNDS: int = 5

OPENAI_API_KEY: Optional[str] = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    raise RuntimeError(
        "OPENAI_API_KEY environment variable is not set. "
        "Please export it, e.g.: export OPENAI_API_KEY='sk-...'"
    )

# Pin the standard OpenAI endpoint so unrelated gateway environment variables
# cannot redirect personal-account requests.
client = OpenAI(
    api_key=OPENAI_API_KEY,
    base_url="https://api.openai.com/v1",
)

# Timeout for URL checks
URL_CHECK_TIMEOUT: float = 3.0  # seconds

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))

if os.getcwd() != REPO_ROOT:
    os.chdir(REPO_ROOT)


# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

def extract_urls(text: str) -> List[str]:
    """
    Extract http/https URLs from a text string.

    Parameters
    ----------
    text : str
        The input text.

    Returns
    -------
    list of str
        List of URLs found in the text.
    """
    url_pattern = re.compile(r"https?://\S+")
    return url_pattern.findall(text)


def check_url(url: str) -> tuple[bool, str]:
    """
    Perform a lightweight HTTP HEAD request to check if a URL seems valid.
    Uses only the Python standard library (no requests dependency).

    Parameters
    ----------

    url: str
        URL

    Returns
    --------
    tuple of
        boolean TRUE if the URL appears reachable
        str message about the status

    """
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=URL_CHECK_TIMEOUT) as response:
            status = response.status
            if 200 <= status < 400:
                return True, f"HTTP status {status}"
            else:
                return False, f"HTTP status {status}"
    except urllib.error.HTTPError as e:
        return False, f"HTTP error: {e.code}"
    except urllib.error.URLError as e:
        return False, f"Network error: {e.reason}"
    except Exception as e:
        return False, f"Error: {e}"

   
def read_text_file(path: str) -> str:
    """
    Read a UTF-8 encoded text file and return its contents as a string.

    This utility is used to load prompt templates from external 
    text files, allowing prompt logic to be defined outside the Python
    code.

    Parameters
    ----------
    path : str
        Path to the text file to read.

    Returns
    -------
    str
        Full contents of the file as a single string.
    """
    with open(path, "r", encoding="utf-8") as f:
        return f.read()            


def truncate_history(
    history: List[ChatCompletionMessageParam],
    max_messages: int = 20,
) -> List[ChatCompletionMessageParam]:
    """
    Optionally truncate conversation history to keep prompts small.

    Parameters
    ----------
    history : list of message dicts
        The full conversation history.
    max_messages : int, optional
        Maximum number of messages to keep (from the end).

    Returns
    -------
    list of message dicts
        Possibly truncated history.
    """
    if len(history) <= max_messages:
        return history
    return history[-max_messages:]


def _content_to_text(content: Any) -> str:
    """
    Convert message content into plain text for the Responses API input format.
    """
    if isinstance(content, str):
        return content

    if isinstance(content, list):
        parts: List[str] = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(str(item.get("text", "")))
            else:
                parts.append(str(item))
        return "".join(parts)

    return str(content)


def _to_responses_input(
    messages: List[ChatCompletionMessageParam],
) -> List[Dict[str, str]]:
    """
    Convert Chat Completions-style messages into Responses API input messages.
    """
    output: List[Dict[str, str]] = []
    for msg in messages:
        role = str(msg.get("role", "user"))
        content = _content_to_text(msg.get("content", ""))
        name = msg.get("name")

        # Keep speaker identity (proposer/critic) when present.
        if name:
            content = f"[{name}] {content}"

        output.append({"role": role, "content": content})
    return output


def _run_model(
    model_name: str,
    messages: List[ChatCompletionMessageParam],
    enable_web_search: bool = False,
) -> str:
    """
    Run a model via the OpenAI Responses API and return text output.
    """
    request_kwargs: Dict[str, Any] = {
        "model": model_name,
        "input": _to_responses_input(messages),
    }

    if enable_web_search:
        request_kwargs["tools"] = [{"type": "web_search"}]
        request_kwargs["tool_choice"] = "auto"

    response = client.responses.create(**request_kwargs)
    return (response.output_text or "").strip()


def load_problem_from_file_or_input() -> str:
    """
    Ask the user for an optional RTF or TXT file path and load the problem description.

    - If an RTF or TXT path is provided and exists:
        * If .rtf and striprtf is installed, convert to plain text.
        * If .txt, read directly.
    - Otherwise, fall back to manual input.

    Returns
    -------
    str
        The problem description provided by the user, either loaded from file 
        or entered manually.

    """
    print("You can either:")
    print("  1) Provide a path to a .rtf or .txt file containing your problem description, or")
    print("  2) Leave it blank and type the problem manually.\n")

    file_path = input("File path (RTF or TXT) [press Enter to skip]: ").strip()
    problem: str = ""

    if file_path:
        if not os.path.exists(file_path):
            print(f"⚠️  File not found: {file_path}. Falling back to manual input.\n")
        else:
            try:
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                if file_path.lower().endswith(".rtf"):
                    if rtf_to_text is not None:
                        print("✓ Loaded and converted RTF file to plain text.\n")
                        problem = rtf_to_text(content).strip()
                    else:
                        print(
                            "⚠️  striprtf not installed. Using raw RTF markup as text.\n"
                            "    Install with: pip install striprtf\n"
                        )
                        problem = content.strip()
                elif file_path.lower().endswith(".txt"):
                    print("✓ Loaded plain text file.\n")
                    problem = content.strip()
                else:
                    print("⚠️  Unsupported file type. Please use .rtf or .txt.\n")
            except Exception as e:
                print(f"⚠️  Error reading file ({e}). Falling back to manual input.\n")

    while not problem.strip():
        problem = input("Please describe your problem (or type 'quit' to exit): ").strip()
        if problem.lower() in {"quit", "exit"}:
            print("Exiting without running the agentic conversation.")
            sys.exit(0)
        if not problem:
            print("Problem description cannot be empty. Please try again.\n")

    return problem


def load_problem(problem_text: str | None, problem_file: str | None) -> str:
    if problem_text and problem_file:
        raise ValueError("Provide only one of --problem or --problem_file (not both).")

    if problem_text:
        return problem_text.strip()

    if problem_file:
        if not os.path.exists(problem_file):
            raise FileNotFoundError(f"Problem file not found: {problem_file}")
        with open(problem_file, "r", encoding="utf-8") as f:
            return f.read().strip()

    # fallback to interactive behavior (your current function)
    return load_problem_from_file_or_input()



def markdown_table_to_dataframe(md_table: str) -> pd.DataFrame:
    """
    Convert a Markdown table into a pandas DataFrame.

    Assumes a standard table like:

    | Quantity | Value | Units | Evidence status | Source(s) | Notes |
    |---------|-------|-------|---------------|-----------|-------|
    | ...     | ...   | ...   | ...                     | ...       | ...   |

    No unnamed boundary columns will be created.

    Parameters
    ----------
    table_md : str
        Markdown-formatted table text.

    Returns
    -------
    pd.DataFrame
        DataFrame containing the parsed table contents.

    """
    # Split into non-empty lines
    lines = [line.strip() for line in md_table.strip().splitlines() if line.strip()]
    if not lines:
        raise ValueError("Empty markdown table.")

    # Remove Markdown separator lines (e.g., |---|---|---| or |:---|:---:|---:|)
    def is_sep_line(line: str) -> bool:
        candidate = line.replace(" ", "").strip()
        if not candidate:
            return False
        parts = candidate.strip("|").split("|")
        if not parts:
            return False
        # each column separator must be made only of '-' and optional boundary ':'
        return all(bool(re.fullmatch(r":?-{3,}:?", p)) for p in parts if p != "")

    lines = [ln for ln in lines if not is_sep_line(ln)]

    # Parse rows manually: strip leading/trailing '|' and split on '|'
    rows = []
    for line in lines:
        row = line.strip().strip("|").split("|")
        row = [cell.strip() for cell in row]
        rows.append(row)

    header = rows[0]
    data_rows = rows[1:]

    df = pd.DataFrame(data_rows, columns=header)

    # Safety: drop any residual separator-like rows that might still appear.
    sep_cell_re = re.compile(r"^\s*:?-{3,}:?\s*$")
    if not df.empty:
        sep_row_mask = df.apply(
            lambda row: all(
                bool(sep_cell_re.fullmatch(str(v))) for v in row.values
            ),
            axis=1,
        )
        df = df.loc[~sep_row_mask].reset_index(drop=True)

    return df

import re

AGE_BAND_RE = re.compile(r"^\s*\d{1,3}\s*[–-]\s*\d{1,3}\s*$")  # e.g., "45-54" or "45–54"

def collapse_mst_band_rows(df: pd.DataFrame) -> pd.DataFrame:
    """
    Collapse age-band MST rows into a single 'MST by age band (years)' row.

    If the table contains rows whose Quantity is an age range (e.g. '45–54',
    '55-64'), their values are combined into a semicolon-delimited string
    ('age:value; age:value; ...') and stored in the
    'MST by age band (years)' row. If that row is missing, it is inserted.

    Parameters
    ----------
    df : pd.DataFrame
        Parameter table containing at least 'Quantity' and 'Value' columns.

    Returns
    -------
    pd.DataFrame
        DataFrame with age-band rows collapsed and index reset.
    """

    if "Quantity" not in df.columns or "Value" not in df.columns:
        return df

    if not (df["Quantity"].astype(str).str.strip().eq("MST by age band (years)").any()):
        return df    

    # Find rows that look like age ranges (45–54) and have numeric-ish values
    band_rows = df[df["Quantity"].astype(str).str.match(AGE_BAND_RE)]

    if band_rows.empty:
        return df

    pairs = []
    for _, r in band_rows.iterrows():
        q = str(r["Quantity"]).strip().replace("-", "–")
        v = str(r["Value"]).strip()
        pairs.append(f"{q}:{v}")

    band_string = "; ".join(pairs)

    # Remove the band rows
    df = df[~df["Quantity"].astype(str).str.match(AGE_BAND_RE)].copy()

    # Put band_string into the intended row
    target = df["Quantity"].astype(str).str.strip().eq("MST by age band (years)")
    if target.any():
        df.loc[target, "Value"] = band_string
    else:
        # If the row is missing, insert it at the top
        new_row = {col: "" for col in df.columns}
        new_row["Quantity"] = "MST by age band (years)"
        new_row["Value"] = band_string
        df = pd.concat([pd.DataFrame([new_row]), df], ignore_index=True)

    return df.reset_index(drop=True)


def save_conversation_txt(out_dir: str, timestamp: str, problem: str, history) -> str:
    """
    Save the full proposer–critic conversation to a plain text file.

    The output file includes:
    - The original problem description.
    - Each message in the conversation history, labeled by agent role
      (e.g., PROPOSER, CRITIC, SUMMARIZER).
    - Messages are written in chronological order.

    The file is saved under the specified output directory using the
    provided timestamp to ensure uniqueness.

    Parameters
    ----------
    out_dir : str
        Directory where the conversation log will be saved.
    timestamp : str
        Timestamp string used to uniquely name the output file.
    problem : str
        The original problem description provided by the user.
    history : list of dict
        Conversation history containing message dictionaries with
        'role', optional 'name', and 'content' fields.

    Returns
    -------
    str
        Path to the saved conversation text file.
    """
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"conversation_{timestamp}.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write("PROBLEM:\n")
        f.write(problem + "\n\n")
        for msg in history:
            role = msg.get("name", msg.get("role", ""))
            f.write(f"--- {role.upper()} ---\n")
            f.write((msg.get("content") or "") + "\n\n")
    return path



# ---------------------------------------------------------------------------
# Configuration and template handling
# ---------------------------------------------------------------------------

@dataclass
class Template:
    """
    Template specification for a proposer–critic workflow.

    Attributes
    ----------
    name : str
        Template key (e.g., "one_test_model").
    description : str
        Human-readable summary of the template’s intended use.
    parameters : list of str
        Parameter names to be extracted by the summarizer. These are injected into
        the summarizer prompt at runtime to enforce the table row set/order.
    table_columns : list of str
        Output columns to be generated for this template.
    evidence_status_rows : list of str
        Parameter rows to which the evidence-status rules apply. An empty list means
        that the template does not use evidence statuses.
    proposer_prompt : str
        Proposer system prompt content (loaded from a text file).
    critic_prompt : str
        Critic system prompt content (loaded from a text file).
    """
    name: str
    description: str
    parameters: List[str]
    table_columns: List[str]
    evidence_status_rows: List[str]
    proposer_prompt: str
    critic_prompt: str

def list_available_templates(registry_file: str = "templates/templates.json") -> List[str]:
    """
    List available template names from the template registry.

    This function reads the JSON template registry and returns the names
    of all registered templates. It is typically used to inform users
    which template options are available for selection at runtime.

    Parameters
    ----------
    registry_file : str, optional
        Path to the JSON file that defines available templates and their
        associated prompt files. Defaults to
        ``"templates/templates.json"``.

    Returns
    -------
    list of str
        Sorted list of template names available in the registry.
    """
    with open(registry_file, "r", encoding="utf-8") as f:
        registry = json.load(f)
    return sorted(registry.keys())



def load_template(
    template_name: str,
    registry_file: str = "templates/templates.json",
) -> Template:
    """
    Load a parameter-estimation template definition.

    Parameters
    ----------
    template_name : str
        Name of the template to load (e.g., ``"one_test_model"``), as defined
        in the template registry.

    registry_file : str, optional
        Path to the JSON registry defining available templates.

    Returns
    -------
    Template
        Loaded template specification.

    Raises
    ------
    FileNotFoundError
        If the registry or required prompt files are missing.
    KeyError
        If the template name is not defined in the registry.
    """
    if not os.path.exists(registry_file):
        raise FileNotFoundError(f"Template registry not found: {registry_file}")

    with open(registry_file, "r", encoding="utf-8") as f:
        registry = json.load(f)

    if template_name not in registry:
        raise KeyError(
            f"Template '{template_name}' not found. "
            f"Available templates: {list(registry.keys())}"
        )

    entry = registry[template_name]

    # Required fields
    description = entry["description"]
    parameters = entry["parameters"]
    output = entry.get("output", {})
    table_columns = output.get(
        "columns",
        ["Quantity", "Value", "Units", "Source(s)", "Notes"],
    )
    evidence_status_rows = output.get("evidence_status_rows", [])
    prompts = entry["prompts"]

    if evidence_status_rows and "Evidence status" not in table_columns:
        raise ValueError(
            f"Template '{template_name}' defines evidence_status_rows but its "
            "output columns do not include 'Evidence status'."
        )

    proposer_path = prompts.get("proposer")
    critic_path = prompts.get("critic")

    if proposer_path is None or critic_path is None:
        raise KeyError(
            f"Template '{template_name}' must define proposer and critic prompts."
        )

    if not os.path.exists(proposer_path):
        raise FileNotFoundError(f"Missing proposer prompt: {proposer_path}")
    if not os.path.exists(critic_path):
        raise FileNotFoundError(f"Missing critic prompt: {critic_path}")

    proposer_prompt = read_text_file(proposer_path)
    critic_prompt = read_text_file(critic_path)

    return Template(
        name=template_name,
        description=description,
        parameters=parameters,
        table_columns=table_columns,
        evidence_status_rows=evidence_status_rows,
        proposer_prompt=proposer_prompt,
        critic_prompt=critic_prompt,
    )


# ---------------------------------------------------------------------------
# Agent classes
# ---------------------------------------------------------------------------

class ProposerAgent:
    """
    Proposer agent that uses the ChatGPT API to propose and refine solutions.

    Behavior:
    - On the first turn, proposes an initial solution to the user's problem.
    - On subsequent turns, refines the solution based on the Critic's feedback.
    """

    def __init__(self, system_prompt: str, model_name: str = MODEL_NAME) -> None:
        self.model_name = model_name
        self.system_prompt = system_prompt


    def respond(
        self,
        problem: str,
        history: List[ChatCompletionMessageParam],
    ) -> str:

        """
        Generate a solution or refined solution using the ChatGPT API.
        """
        trimmed_history = truncate_history(history)

        messages: List[ChatCompletionMessageParam] = [
            {"role": "system", "content": self.system_prompt},
            {
                "role": "user",
                "content": (
                    "Here is the problem you must solve:\n"
                    f"{problem}\n\n"
                    "Below is the conversation so far between you (Proposer) and "
                    "the Critic. Continue as the Proposer, proposing or refining "
                    "a solution."
                ),
            },
        ]
        messages.extend(trimmed_history)
        messages.append(
            {
                "role": "user",
                "content": (
                    "Now, respond as the Proposer agent. Provide a clear solution "
                    "or an improved version of your previous solution."
                ),
            }
        )

        try:
            reply = _run_model(
                model_name=self.model_name,
                messages=messages,
                enable_web_search=True,
            )
        except Exception as exc:
            print(f"[ERROR] ProposerAgent API call failed: {exc}", file=sys.stderr)
            raise

        return reply.strip()


class CriticAgent:
    """
    Critic agent that uses the ChatGPT API to critique the Proposer's solution.

    Behavior:
    - Analyzes the Proposer's message for clarity, completeness, correctness.
    - Extracts and optionally checks URLs (via HEAD/GET).
    - Incorporates URL check results into the prompt.
    - If the Critic fully agrees with the solution, it must say exactly:
      "I agree with this solution."
    """

    def __init__(self, system_prompt: str, model_name: str = MODEL_NAME) -> None:
        self.model_name = model_name
        self.system_prompt = system_prompt

    def respond(
        self,
        problem: str,
        history: List[ChatCompletionMessageParam],
        proposer_message: str,
    ) -> Dict[str, Any]:
        """
        Critique the Proposer's latest solution using the ChatGPT API.
        """
        urls = extract_urls(proposer_message)
        url_checks: List[Dict[str, str]] = []

        for url in urls:
            is_valid, reason = check_url(url)
            url_checks.append(
                {
                    "url": url,
                    "valid": "True" if is_valid else "False",
                    "reason": reason,
                }
            )

        if url_checks:
            url_summary_lines = ["URL checks (performed by an external tool):"]
            for info in url_checks:
                url_summary_lines.append(
                    f"- {info['url']} -> valid={info['valid']} ({info['reason']})"
                )
            url_summary = "\n".join(url_summary_lines)
        else:
            url_summary = "URL checks: No URLs were found in the Proposer's message."

        trimmed_history = truncate_history(history)

        messages: List[ChatCompletionMessageParam] = [
            {"role": "system", "content": self.system_prompt},
            {
                "role": "user",
                "content": (
                    "Here is the problem the Proposer is trying to solve:\n"
                    f"{problem}\n\n"
                    "Here is the Proposer's latest solution:\n"
                    f"{proposer_message}\n\n"
                    f"{url_summary}\n\n"
                    "Now, as the Critic agent, please provide your critique. "
                    'If you fully agree with the solution, include a line that says '
                    '"I agree with this solution." exactly, and only do so if you '
                    "truly think no further refinement is needed."
                ),
            },
        ]
        messages.extend(trimmed_history)

        try:
            reply = _run_model(
                model_name=self.model_name,
                messages=messages,
                enable_web_search=True,
            )
        except Exception as exc:
            print(f"[ERROR] CriticAgent API call failed: {exc}", file=sys.stderr)
            raise

        reply = reply.strip()

        agrees = "I agree with this solution." in reply

        return {
            "message": reply,
            "agrees": agrees,
            "url_checks": url_checks,
        }


def summarize_solution(
    problem: str,
    solution: str,
    parameters: List[str],
    table_columns: Optional[List[str]] = None,
    evidence_status_rows: Optional[List[str]] = None,
) -> str:
    """
    Extract a final parameter table from a solution text using a summarizer LLM.

    This function instructs a summarizer agent to read the Proposer's solution
    and generate a Markdown table containing only the requested parameters.
    The rows of the table are defined explicitly by the `parameters` argument,
    ensuring consistency with the selected template.

    Parameters
    ----------
    problem : str
        Original problem description. Included for API compatibility and
        traceability, but not directly used in the summarization prompt.
    solution : str
        The solution text to summarize, typically the final or last Proposer
        message produced by the agentic conversation.
    parameters : list of str
        Names of the parameters to extract and include as rows in the final
        table (e.g., "Mean sojourn time (MST)", "Sensitivity", "Specificity").

    Returns
    -------
    str
        A Markdown-formatted table using the columns configured for the selected
        template. The output contains no additional text outside the table.
    """
    rows_text = "\n".join(f"- {p}" for p in parameters)
    table_columns = table_columns or [
        "Quantity", "Value", "Units", "Source(s)", "Notes"
    ]
    evidence_status_rows = evidence_status_rows or []
    table_header = "| " + " | ".join(table_columns) + " |\n"
    table_separator = "|" + "|".join("---" for _ in table_columns) + "|\n\n"

    if evidence_status_rows:
        status_rows_text = ", ".join(f"`{row}`" for row in evidence_status_rows)
        evidence_status_rules = (
            "Evidence status rules:\n"
            f"- Populate Evidence status for these rows: {status_rows_text}. For every "
            "other row, write NA in Evidence status.\n"
            "- For Sensitivity and Specificity, copy exactly one explicitly stated final "
            "classification: `Tier 1 single-study`, `Tier 2 PROXY`, "
            "`Tier 3 POOLED`, `Tier 3 META-ANALYTIC`, or `Tier 4 NA`.\n"
            "- For each MST or mean sojourn time row, copy exactly one explicitly stated "
            "final status: `Direct test-specific MST`, "
            "`PROXY MST`, `OPERATIONAL MST ASSUMPTION`, or `NA`.\n"
            "- Use `OPERATIONAL MST ASSUMPTION` only for a numeric recommended "
            "single MST when the solution explicitly invokes the last-resort "
            "operational fallback. Do not use it for MST by age band.\n"
            "- Use `NA` for an MST row only when its Value is NA. A numeric MST must "
            "retain one of the three non-NA MST statuses.\n"
            "- Do not infer, weaken, paraphrase, or combine statuses. Keep derivation, "
            "anchor role, transferability, population, setting, configuration, endpoint, "
            "pooling, and heterogeneity limitations in Notes; do not replace the exact "
            "status with those details.\n\n"
        )
    else:
        evidence_status_rules = ""

    messages: List[ChatCompletionMessageParam] = [
        {
            "role": "system",
            "content": (
                "You are a summarizer agent.\n\n"
                "Your ONLY task is to produce a final parameter table based strictly "
                "on the solution text provided to you regardless of whether the agents reached agreement.\n"
                "The table must have EXACTLY one row per item in the rows list below.\n"
                "Do NOT split an item into multiple rows\n\n"

                "Output exactly this table (and nothing else):\n\n"
                f"{table_header}"
                f"{table_separator}"
                "The table must have rows for:\n"
                f"{rows_text}\n\n"
                "Use ONLY information explicitly stated in the solution text. \n"
                "Fill the Notes column with brief clarifications explicitly stated in the solution text "
                "that affect interpretation/derivation of the Value for that row. If none, write NA. \n"
                "Do not invent notes.\n\n"

                f"{evidence_status_rules}"

                "Units column rules:\n"
					"- If the row name explicitly includes units in parentheses, use those units in the "
					"Units column and do not repeat the units in the Value cell when avoidable.\n"
					"- For sensitivity, specificity, PPV, NPV, FPR, false-positive rate, detection rate, "
					"or other probability/accuracy rows, set Units = proportion when the Value is "
					"reported on a 0–1 scale.\n"
					"- For MST or mean sojourn time rows, set Units = years unless the row name or "
					"solution text states another unit.\n"
					"- For Cancer and Test-name rows, set Units = NA.\n"
					"- If units cannot be inferred from the row name or solution text, write NA.\n\n"

                "Row count requirement:\n"
                    "- The final table must contain exactly N data rows (excluding header), "
                    "where N = number of items in the rows list.\n"
                    "- If you cannot find values, still include the row and put NA.\n\n"

                "Special rule for MST by age band (if there exists a row called 'MST by age band (years)'):\n"
                    "- For the row 'MST by age band (years)', the Value MUST be a single "
                    "semicolon-delimited string of the form  "
                    "age_range:value; age_range:value; ...' (example: '45–54:2; 55–64:3; 65–74:6') \n"
                    "If the solution provides age-band MST values in bullets or sentences, "
                    "you MUST convert them into the semicolon-delimited format in the Value cell. \n"
                    "- Do NOT create separate table rows for each age band.\n"
                    "- If no age-specific MST estimates exist, write NA.\n\n"    

                "If a value is missing, write 'NA' in the Value column.\n"
                "Do NOT use bullets or line breaks inside any table cell. Every Value cell "
                "must be one line. Do not invent any numbers or sources.\n"
                "If no explicit source citation is stated, write NA in Source(s)\n"
                "Do not include any text before or after the table."
            ),
        },
        {
            "role": "user",
            "content": (
                "Here is the solution text from which you must extract the parameters:\n\n"
                f"{solution}\n\n"
                "Produce ONLY the table as specified in the system message."
            ),
        },
    ]


    reply = _run_model(
        model_name=MODEL_NAME,
        messages=messages,
        enable_web_search=False,
    )
    return reply.strip()


# ---------------------------------------------------------------------------
# Main conversation loop
# ---------------------------------------------------------------------------

def main() -> None:
    print("=== Two-Agent Conversation System (Parameter Estimation) ===")
    print("You will be asked to input a problem description.")
    print("The Proposer and Critic agents will then discuss it.\n")
    print("DEBUG sys.argv:", sys.argv)

    parser = argparse.ArgumentParser()
    parser.add_argument("--problem", type=str, default=None, help="Problem text (non-interactive).")
    parser.add_argument("--problem_file", type=str, default=None, help="Path to a text file containing the problem.")
    parser.add_argument("--template", type=str, default=None,
                    help="Template name to run (bypasses interactive selection).")
    parser.add_argument("--non_interactive", action="store_true",
                    help="Run without interactive prompts.")

    args = parser.parse_args()
    problem = load_problem(args.problem, args.problem_file)

    # parser = argparse.ArgumentParser()
    # parser.add_argument(
    # 	"--template",
    # 	type=str,
    # 	default=None,
    # 	help= "Name of the template to use. \n"
    # 	"If provided, the template is selected automatically instead of prompting the user."
    # )
    # parser.add_argument(
    # 	"--non_interactive",
    # 	action="store_true",
    # 	help="Disable all interactive prompts. \n"
    #     "Intended for batch or pipeline execution. \n"
    #     "Required inputs (e.g., --template) must be provided explicitly."
    # )
    # args = parser.parse_args()
    available = list_available_templates()

    print("Available templates:")
    for t in available:
    	print(f"  - {t}")

    if args.template is not None:
    	template_name = args.template
    else:
    	if args.non_interactive:
        	raise ValueError("--non_interactive requires --template (or set a default).")
    	template_name = input("Template name: ").strip()    

    #template_name = input("Template name: ").strip()

    print("\nThank you. Starting the agent conversation...\n")
    template = load_template(template_name)

    out_dir = "logs"
    os.makedirs(out_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    proposer = ProposerAgent(system_prompt=template.proposer_prompt, model_name=MODEL_NAME)
    critic = CriticAgent(system_prompt=template.critic_prompt, model_name=MODEL_NAME)

    history: List[ChatCompletionMessageParam] = []

    agreed: bool = False
    final_solution: Optional[str] = None
    last_critic_message: Optional[str] = None

    for round_idx in range(1, MAX_ROUNDS + 1):
        print(f"\n==== ROUND {round_idx}: Proposer ====")

        try:
            proposer_reply = proposer.respond(problem=problem, history=history)
        except Exception:
            print(
                "An error occurred while generating the Proposer's response. "
                "Stopping conversation.",
                file=sys.stderr,
            )
            break

        print(f"\n[Proposer]\n{proposer_reply}\n")

        history.append(
            {
                "role": "assistant",
                "name": "proposer",
                "content": proposer_reply,
            }
        )

        print(f"==== ROUND {round_idx}: Critic ====")

        try:
            critic_result = critic.respond(
                problem=problem,
                history=history,
                proposer_message=proposer_reply,
            )
        except Exception:
            print(
                "An error occurred while generating the Critic's response. "
                "Stopping conversation.",
                file=sys.stderr,
            )
            break

        critic_reply: str = critic_result["message"]
        critic_agrees: bool = critic_result["agrees"]

        print(f"\n[Critic]\n{critic_reply}\n")

        history.append(
            {
                "role": "assistant",
                "name": "critic",
                "content": critic_reply,
            }
        )

        last_critic_message = critic_reply

        if critic_agrees:
            agreed = True
            final_solution = proposer_reply
            print(
                "The Critic explicitly agreed with the solution. "
                "Ending the conversation early."
            )
            break

    num_rounds_executed = round_idx

    print("\n=== Conversation Finished ===\n")

    if agreed and final_solution is not None:
        print("Final agreed-upon solution:\n")
        print(final_solution)
    else:
        print(
            f"No full agreement was reached within the maximum number of rounds ({MAX_ROUNDS})."
        )
        last_proposer_message: Optional[str] = None
        for msg in reversed(history):
            if msg.get("name") == "proposer":
                last_proposer_message = msg.get("content")
                break

        print("\nLast proposed solution (best attempt):\n")
        print(last_proposer_message or "(No proposal was generated.)")

        print("\nLast Critic message:\n")
        print(last_critic_message or "(No critic message was generated.)")

    # -------------------------------------------------------------------
    # Generate the parameter table from the last solution (always)
    # -------------------------------------------------------------------
    # Choose solution to summarize
    best_solution_for_summary = final_solution
    if best_solution_for_summary is None:
        for msg in reversed(history):
            if msg.get("name") == "proposer":
                best_solution_for_summary = msg.get("content")
                break

    # Run summarizer
    summary_text = None
    if best_solution_for_summary:
        summary_text = summarize_solution(
            problem,
            best_solution_for_summary,
            template.parameters,
            template.table_columns,
            template.evidence_status_rows,
        )

    # Save summarizer output in history
    if summary_text:
        history.append({
            "role": "assistant",
            "name": "summarizer",
            "content": summary_text
        })

    # -----------------------------------------------------------------------
    # Save parameter table (CSV) from the summary; also print it nicely
    # -----------------------------------------------------------------------
    if summary_text:
        try:
            # Convert Markdown table to DataFrame
            df_params = markdown_table_to_dataframe(summary_text)
            df_params = collapse_mst_band_rows(df_params)

            # Add number of rounds
            df_params["NumRounds"] = num_rounds_executed

            # Pretty print in console
            print("\nFinal parameter table:\n")
            print(df_params.to_string(index=False))

            # Save to CSV in logs/
            csv_path = os.path.join(out_dir, f"parameters_{timestamp}.csv")
            df_params.to_csv(csv_path, index=False)

            print(f"\nParameter table saved to CSV: {csv_path}")
        except Exception as e:
            print(f"\n[WARNING] Could not save parameter CSV: {e}", file=sys.stderr)

    else:
        print("\n[WARNING] No summary was generated, no parameter CSV saved.")

    # Save history in logs/
    txt_path = save_conversation_txt(out_dir, timestamp, problem, history)
    print(f"Conversation saved to TXT: {txt_path}")

    with open(os.path.join(out_dir, f"problem_{timestamp}.txt"), "w", encoding="utf-8") as f:
    	f.write(problem)
    


if __name__ == "__main__":
    main()
