"""Test helpers for archive-domain."""

import sys
from pathlib import Path

SAMPLE_ROOT = Path(__file__).resolve().parents[1]

if str(SAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(SAMPLE_ROOT))
