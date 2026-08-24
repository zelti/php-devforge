#!/usr/bin/env python3
"""Run one CI step's `run:` block locally, verbatim.

Verbatim is the point. Every CI failure this project has had came from checking
a hand-typed variant of a step rather than the step itself: a flag passed
locally but not in CI, a value assumed to be set by an earlier step, a pipeline
that behaves differently under `pipefail`.

    .github/scripts/run-step.py                       # list the steps
    .github/scripts/run-step.py "the forge command works"
    .github/scripts/run-step.py -x "<name>"           # trace each command

Needs the stack running (`forge start`). Steps are not independent: some rely on
fixtures an earlier step creates, so run those first when a step fails on
missing files. See the Contributing section of the README.
"""
import subprocess
import sys

try:
    import yaml
except ImportError:
    raise SystemExit(
        "This needs PyYAML to read the workflow file.\n"
        "  Debian/Ubuntu:  sudo apt install python3-yaml\n"
        "  Arch:           sudo pacman -S python-yaml\n"
        "  Any:            pip install --user pyyaml"
    )

WORKFLOW = ".github/workflows/ci.yml"


def steps():
    with open(WORKFLOW, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    for job_name, job in doc["jobs"].items():
        for step in job.get("steps", []):
            if step.get("name") and step.get("run"):
                yield job_name, step["name"], step["run"]


def main():
    args = [a for a in sys.argv[1:]]
    trace = False
    if args and args[0] in ("-x", "--trace"):
        trace = True
        args = args[1:]

    found = list(steps())
    if not args:
        print("Steps that can be run:\n")
        current = None
        for job, name, _ in found:
            if job != current:
                print("  [%s]" % job)
                current = job
            print("    %s" % name)
        print("\nRun one with:  %s \"<name>\"" % sys.argv[0])
        return 0

    want = args[0]
    for _, name, body in found:
        if name == want:
            print("--- running %r verbatim ---\n" % name, flush=True)
            # GitHub runs each step as `bash -e {0}`.
            flags = "-ex" if trace else "-e"
            result = subprocess.run(["bash", flags, "-c", body])
            print("\n--- exit %d ---" % result.returncode)
            return result.returncode

    print("No step named %r. Run without arguments to list them." % want, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
