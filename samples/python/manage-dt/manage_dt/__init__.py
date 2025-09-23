#!/usr/bin/env python3

"""
Manage Digital Twins for the OCI IoT Platform.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import importlib.metadata

try:
    __version__ = importlib.metadata.version("manage_dt")
except Exception:
    __version__ = "unknown"
