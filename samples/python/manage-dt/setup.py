#!/usr/bin/env python3

"""
Manage Digital Twins for the OCI IoT Platform.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import os

from setuptools import find_packages, setup

here = os.path.abspath(os.path.dirname(__file__))
with open(os.path.join(here, "README.md"), encoding="utf-8") as f:
    long_description = f.read()

setup(
    name="manage_dt",
    version="0.0.3",
    description="Manage Digital Twins sample script",
    long_description=long_description,
    long_description_content_type="text/markdown",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries",
        "Programming Language :: Python :: 3",
        "Operating System :: POSIX :: Linux",
    ],
    packages=find_packages(),
    python_requires=">=3.12",
    install_requires=[
        "click~=8.2.0",
        "oci~=2.0,>=2.161",
        "PyYAML~=6.0.0",
        "requests~=2.32.0",
        "rich~=13.0.0",
    ],
    extras_require={
        "test": [
            "flake8",
            "flake8-comprehensions",
            "flake8-docstrings",
            "flake8-import-order",
            "pep8-naming",
            "pydocstyle",
        ],
    },
    entry_points={
        "console_scripts": [
            "manage-dt=manage_dt.cli:cli",
        ],
    },
)
