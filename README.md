# Neuroforger

Neuroforger is a tool for generating certified violation witnesses for Solidity smart contract properties. Given a contract and a property written in GATE (a Foundry-based specification language with abstract types), it uses an LLM to produce a concretization of the abstract variables that makes the test pass — i.e., a counterexample that proves that the property is violated. The counterexample is then validated via type checking (manual, in the current version) and concrete execution with Forge.

For a full description of the approach, see the paper *"[Neuroforger: certified violation witnesses for smart contracts verification via LLMs](https://arxiv.org/abs/2605.31389)"*.

## Requirements

- Python 3.10+
- [Foundry](https://github.com/foundry-rs/foundry) (the `forge` binary must be available; update `FORGE_PATH` in `Neuroforger.py` if needed)
- Python dependencies: `openai`, `pandas`
- An OpenAI API key stored in `openai_api_key.txt` (one line, no extra whitespace)

## Running the tool

```bash
python Neuroforger.py --model gpt-5 --contract bank --property withdraw-revert --version 17
```

**Arguments:**

| Argument | Description |
|---|---|
| `--model` | LLM model identifier (e.g. `gpt-5`) |
| `--contract` | Contract name, must match a subfolder under `contracts/` |
| `--property` | Property name, must be a key in `contracts/<contract>/skeleton.json` |
| `--version` | Version number, must match a file `contracts/<contract>/versions/<Contract>_v<N>.sol` |
| `--use_csv_verification_tasks <file>` | Run the tool on the set of tasks listed in the given CSV |
| `--niter <N>` | Maximum number of CEGIS iterations (default: 3) |
| `--prompt <file>` | Prompt template file (default: `prompt_templates/dsl_zeroshot.txt`) |
| `--tokens <N>` | Token limit for the LLM (default: 30000) |

## Folder structure

```
contracts/
  bank/
    skeleton.json          # property names and descriptions
    ground-truth.csv       # ground truth for all (property, version) pairs
    versions/              # Bank_v1.sol ... Bank_v17.sol
    specs/                 # GATE specification files (.spec)

experiments/
  Bank_verification_tasks.csv   # the list of tasks used in the experiments
  forge_results/
    bank/
      v1/ ... v17/
        test/              # generated and failed test files, per version
  logs/                    # raw LLM logs
  results/
    results.csv            # main results file
    analyze_results.py     # post-processing script
    backup/                # automatic backups of the results file

lib/                       # Solidity libraries (ERC20, ReentrancyGuard, etc.)
prompt_templates/          # LLM prompt templates
Neuroforger.py             # main entry point
```

## Reproducing the experiments

To run the tool on all the verification tasks used in the paper:

```bash
python Neuroforger.py --model gpt-5 --contract bank \
  --use_csv_verification_tasks experiments/Bank_verification_tasks.csv
```

It is possible to only reproduce a subset of the verification tasks by specifying either a --property or a --version filter. For example, to run all tasks related to the `withdraw-revert` property across all versions:

```bash
python Neuroforger.py --model gpt-5 --contract bank \
  --use_csv_verification_tasks experiments/Bank_verification_tasks.csv \
  --property withdraw-revert
```

To run a single task instead:

```bash
python Neuroforger.py --model gpt-5 --contract bank \
  --property withdraw-revert --version 11
```

Results are written to `experiments/results/results_{model}_{prompt}_{contract}_{tokens}.csv`. Each run automatically saves a timestamped backup of the existing results file under `experiments/results/backup/` before writing.


### Analyzing results

Once the results CSV is populated, run:

```bash
python experiments/results/analyze_results.py experiments/results/{results_filename}.csv
```

This produces `{results_filename}_analyzed.csv` in the same directory, with an added `iterations` column counting the number of failed Forge attempts per task.
