#!/usr/bin/env python3

"""
Class to simulate an environmental sensor.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from datetime import datetime, timezone
import time

import numpy as np


class EnvironmentalSensorSimulator:
    """
    Simulates a virtual environmental sensor producing sequential telemetry.

    Parameters:
        time_format (str): Specify time style for telemetry payload.
            - 'epoch': Current time as integer microseconds since Unix epoch.
            - 'iso': Current time as an ISO8601 string in UTC (with 'Z' suffix).
            - 'none': No time information is included in the payload.

    Behavior:
        - Each telemetry message includes:
            - sht_temperature (°C), qmp_temperature (°C): Range [13.0, 21.0]
            - humidity (%): Range [60.0, 90.0]
            - pressure (hPa): Range [1000.0, 1030.0]
            - count: Increments with every call
            - (optional) time: Only included if time_format != 'none'
        - Sensor values evolve stochastically, deviating stepwise from the previous
          value using Gaussian noise and always clamped within their respective ranges.
        - All floats are rounded to 2 decimal places in the output.
        - Initial sensor values are chosen near the middle of their allowed range for
          realistic startup.
    """

    def __init__(self, time_format="epoch"):
        """
        Initialize the environmental sensor simulator with startup values.

        Args:
            time_format (str): Format for time in telemetry output. Must be one of
                'epoch', 'iso', or 'none'. Default is 'epoch'.

        Raises:
            ValueError: If time_format is not a supported value.
        """
        if time_format not in ("epoch", "iso", "none"):
            raise ValueError("time_format must be 'epoch', 'iso', or 'none'")
        self.time_format = time_format
        self.count = 0

        # Bounds
        self.TEMP_MIN = 13.0
        self.TEMP_MAX = 21.0
        self.PRESSURE_MIN = 1000.0
        self.PRESSURE_MAX = 1030.0
        self.HUMIDITY_MIN = 60.0
        self.HUMIDITY_MAX = 90.0

        # Step std devs
        self.sht_temp_sigma = 0.1  # Step size per call
        self.qmp_temp_sigma = 0.1
        self.humidity_sigma = 0.5
        self.pressure_sigma = 0.2

        # Initialize values: Gaussian around midpoint, clamp to bounds
        rng = np.random.default_rng()
        temp_mid = (self.TEMP_MIN + self.TEMP_MAX) / 2
        temp_std = (self.TEMP_MAX - self.TEMP_MIN) / 8
        pressure_mid = (self.PRESSURE_MIN + self.PRESSURE_MAX) / 2
        pressure_std = (self.PRESSURE_MAX - self.PRESSURE_MIN) / 8
        humidity_mid = (self.HUMIDITY_MIN + self.HUMIDITY_MAX) / 2
        humidity_std = (self.HUMIDITY_MAX - self.HUMIDITY_MIN) / 8

        self.sht_temperature = self._clamp(
            float(rng.normal(temp_mid, temp_std)), self.TEMP_MIN, self.TEMP_MAX
        )
        self.qmp_temperature = self._clamp(
            float(rng.normal(temp_mid, temp_std)), self.TEMP_MIN, self.TEMP_MAX
        )
        self.humidity = self._clamp(
            float(rng.normal(humidity_mid, humidity_std)),
            self.HUMIDITY_MIN,
            self.HUMIDITY_MAX,
        )
        self.pressure = self._clamp(
            float(rng.normal(pressure_mid, pressure_std)),
            self.PRESSURE_MIN,
            self.PRESSURE_MAX,
        )

    def _clamp(self, value, minv, maxv):
        return max(min(value, maxv), minv)

    def _get_time(self):
        now = time.time()
        if self.time_format == "epoch":
            # Return integer microseconds since Unix epoch
            return int(now * 1_000_000)
        else:
            # ISO 8601 with microseconds and UTC; use Z for UTC indicator
            return (
                datetime.fromtimestamp(now, tz=timezone.utc)
                .isoformat(timespec="microseconds")
                .replace("+00:00", "Z")
            )

    def get_telemetry(self):
        """
        Generate the next telemetry reading.

        Simulates realistic sensor value fluctuations. Returns a dictionary containing
        current sensor readings:
            - sht_temperature (float): SHT sensor temperature in °C
            - qmp_temperature (float): QMP sensor temperature in °C
            - humidity (float): Relative humidity in %
            - pressure (float): Pressure in hPa
            - count (int): Call counter
            - time: Timestamp in specified format, if enabled

        Returns:
            dict: Telemetry payload with sensor readings and optional time.
        """
        # Simulate the next values
        self.count += 1
        self.sht_temperature = self._clamp(
            float(np.random.normal(self.sht_temperature, self.sht_temp_sigma)),
            self.TEMP_MIN,
            self.TEMP_MAX,
        )
        self.qmp_temperature = self._clamp(
            float(np.random.normal(self.qmp_temperature, self.qmp_temp_sigma)),
            self.TEMP_MIN,
            self.TEMP_MAX,
        )
        self.humidity = self._clamp(
            float(np.random.normal(self.humidity, self.humidity_sigma)),
            self.HUMIDITY_MIN,
            self.HUMIDITY_MAX,
        )
        self.pressure = self._clamp(
            float(np.random.normal(self.pressure, self.pressure_sigma)),
            self.PRESSURE_MIN,
            self.PRESSURE_MAX,
        )

        telemetry = {
            "sht_temperature": round(self.sht_temperature, 2),
            "qmp_temperature": round(self.qmp_temperature, 2),
            "humidity": round(self.humidity, 2),
            "pressure": round(self.pressure, 2),
            "count": self.count,
        }
        if self.time_format != "none":
            telemetry["time"] = self._get_time()
        return telemetry
