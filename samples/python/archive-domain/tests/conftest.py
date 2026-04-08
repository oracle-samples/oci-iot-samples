"""Test helpers for archive-domain."""

from pathlib import Path
import sys


SAMPLE_ROOT = Path(__file__).resolve().parents[1]

if str(SAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(SAMPLE_ROOT))

