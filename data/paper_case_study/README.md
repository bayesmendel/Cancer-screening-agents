# Paper case-study data

This directory contains the frozen inputs and reference outputs for the
colorectal cancer case study in a female population. Together, these files allow
the reported microsimulations to be rerun without repeating the agentic calls or
requiring access to the complete `Fam3PRODatabase`.

The data flow is:

```text
agent-generated strategy and test parameters
                       +
         age-specific penetrance vector
                       |
                       v
             scripts/two_test_full.R
                       |
                       v
       natural-history and screening objects
```

## Directory contents

```text
paper_case_study/
├── agent_generated_inputs/   # Frozen structured tables from the agents
├── simulation_inputs/        # Non-agent input required by the simulation
└── reference_outputs/        # Saved objects from the reported simulation
```

### Agent-generated inputs

The files in `agent_generated_inputs/` are the complete structured tables
selected for the manuscript case study. They are retained because new agentic
runs may identify different evidence, values, tests, or screening schedules.

| File | Contents |
|---|---|
| [`parameters_20260819_154630.csv`](agent_generated_inputs/parameters_20260819_154630.csv) | Template 2 output selecting colonoscopy as Test 1 and fecal immunochemical testing (FIT) as Test 2, with their screening schedules |
| [`parameters_20260814_195949.csv`](agent_generated_inputs/parameters_20260814_195949.csv) | Template 1 output containing the colonoscopy MST, sensitivity, and specificity inputs |
| [`parameters_20260814_190648.csv`](agent_generated_inputs/parameters_20260814_190648.csv) | Template 1 output containing the FIT MST, sensitivity, and specificity inputs |

Each table also retains its supporting sources, notes, and number of
Proposer–Critic rounds. The corresponding conversation logs are not included in
this directory.

### Simulation input

[`colorectal_female_seer_net_penetrance.csv`](simulation_inputs/colorectal_female_seer_net_penetrance.csv)
contains the age-specific penetrance vector used by the case-study simulation.
It has one row for each age from 1 through 94 and two columns:

- `age`: age in years;
- `penetrance`: the age-specific probability of reaching the clinical cancer
  state at that age, not cumulative risk.

The vector corresponds, at the precision stored in the CSV, to the following
slice of `Fam3PRODatabase`:

```r
Fam3PRODatabase$Penetrance[
  "Colorectal", "SEER", "All_Races", "Female", , "Net"
]
```

Only this extracted vector is included; the complete private
`Fam3PRODatabase` is not distributed in this repository. The case-study script
reads the CSV directly, so running the simulation does not require the
`Fam3PRO` package. The cancer, database index, race, and sex labels are retained
in the simulated object for traceability.

### Reference outputs

The files in `reference_outputs/` contain the saved results of the reported
simulation:

| File | Contents |
|---|---|
| [`natural_history.rds`](reference_outputs/natural_history.rds) | One million simulated two-test natural histories, generated with seed `2782005` |
| [`lead_time.rds`](reference_outputs/lead_time.rds) | Screening results for those histories, generated with seed `2782006` |

These are binary R files. Load them from R rather than opening them in a text
editor:

```r
natural_history <- readRDS(
  file.path(
    "data", "paper_case_study", "reference_outputs",
    "natural_history.rds"
  )
)

lead_time_results <- readRDS(
  file.path(
    "data", "paper_case_study", "reference_outputs",
    "lead_time.rds"
  )
)
```

The reference files contain simulated histories only; they do not contain
individual-level patient data.

## Rerunning the case study

From the repository root, run:

```bash
Rscript scripts/two_test_full.R
```

[`scripts/two_test_full.R`](../../scripts/two_test_full.R) reads the three saved
agent-generated tables and the penetrance CSV, runs the natural-history and
screening simulations using the fixed seeds above, and writes new objects to
`results/paper_case_study/` by default. That directory is ignored by version
control, and rerunning the script does not overwrite the curated reference files
in this directory.