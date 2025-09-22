#!/usr/bin/env python3
"""
Manage-dt: OCI IoT interactions (data API).

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""
from datetime import datetime, timedelta, timezone
import json
import logging
import pathlib
import time
from typing import Optional

from oci import exceptions as oci_exceptions, iot as oci_iot
import requests
import requests.auth

from . import mdt_constants


logger = logging.getLogger(__name__)


def get_data_access_parameters(
    client: oci_iot.IotClient, iot_config: dict, data_dir: pathlib.Path
) -> Optional[dict]:
    """Get and cache data API access parameters.

    This function creates/updates a file to cache data. The file contains:
        {
            "iot_domain_id":
            "oauth_endpoint":
            "iot_data_endpoint":
            "token":
            "expires":
        }
    The cache is invalidated if the iot_domain_id changes.
    On the first call, the IoT Domain and Domain Group are queried to retrieve the
    OAuth endpoint and the IoT data endpoint.
    On subsequent calls, the token is refreshed if it is about to expire.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        iot_config (dict): IoT configuration.
        data_dir (pathlib.Path): Data directory.

    Returns:
        Optional[dict]: Data access parameters or None.
    """
    iot_domain_id = iot_config["iot"]["domain_id"]
    now = time.time()
    data_access = None
    data_access_cache_path = data_dir / mdt_constants.DATA_ACCESS_CACHE
    if data_access_cache_path.exists():
        with open(data_access_cache_path, "r") as fp:
            data_access = json.load(fp)
        if (
            data_access["expires"] > now + mdt_constants.TOKEN_GRACE_SECONDS
            and data_access["iot_domain_id"] == iot_domain_id
        ):
            logger.debug("Using cached data access configuration and token")
            return data_access

    # Either there is no data_access file or the token is about to expire
    if not data_access or data_access["iot_domain_id"] != iot_domain_id:
        logger.debug("Retrieving data access configuration")
        data_access = {"iot_domain_id": iot_domain_id}
        try:
            response = client.get_iot_domain(iot_domain_id=iot_domain_id)
        except oci_exceptions.ServiceError as exc:
            logger.error("Cannot get IoT Domain")
            logger.error("  Status : %d - %s", exc.status, exc.code)
            logger.error("  Message: %s", exc.message)
            return None
        if not response or response.status != 200:
            logger.error(
                "Cannot retrieve IoT Domain - %s",
                response.status if response else None,
            )
            return None
        identity_domain = response.data.db_allowed_identity_domain_host
        if not identity_domain:
            logger.error("ORDS Data access has not been configured for this IoT Domain")
            return None
        iot_domain_short_id = response.data.device_host.split(".")[0]
        iot_domain_group_id = response.data.iot_domain_group_id
        try:
            response = client.get_iot_domain_group(
                iot_domain_group_id=iot_domain_group_id
            )
        except oci_exceptions.ServiceError as exc:
            logger.error("Cannot get IoT Domain Group")
            logger.error("  Status : %d - %s", exc.status, exc.code)
            logger.error("  Message: %s", exc.message)
            return None
        if not response or response.status != 200:
            logger.error(
                "Cannot retrieve IoT Domain Group - %s",
                response.status if response else None,
            )
            return None
        iot_domain_group_data_host = response.data.data_host
        iot_domain_group_short_id = iot_domain_group_data_host.split(".")[0]
        data_access["iot_data_endpoint"] = (
            f"https://{iot_domain_group_data_host}/ords/{iot_domain_short_id}/20250531"
        )
        data_access["oauth_endpoint"] = f"https://{identity_domain}/oauth2/v1/token"
        data_access["scope"] = f"/{iot_domain_group_short_id}/iot/{iot_domain_short_id}"

    logger.debug("Getting OAuth access token")
    r = requests.post(
        url=data_access["oauth_endpoint"],
        auth=requests.auth.HTTPBasicAuth(
            iot_config["identity"]["app_client_id"],
            iot_config["identity"]["app_client_secret"],
        ),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data={
            "scope": data_access["scope"],
            "grant_type": "password",
            "username": iot_config["identity"]["user"],
            "password": iot_config["identity"]["password"],
        },
    )
    if r.status_code != requests.codes.ok:
        logger.error("Unable to get OAuth access token")
        logger.error("  Status : %s", r.status_code)
        logger.error("  Message: %s", r.text)
        return None

    # returns: {'access_token': '...',  'token_type': 'Bearer', 'expires_in': 3600}
    oauth_token = r.json()
    data_access["token"] = oauth_token["access_token"]
    data_access["expires"] = int(now + oauth_token["expires_in"])
    with open(data_access_cache_path, "w") as fp:
        json.dump(data_access, fp, indent=2)
    logger.debug("Data access configuration retrieved and saved")
    return data_access


def get_recent_data(
    data_access: dict,
    last_minutes: int,
    digital_twin_instance_id: str,
    endpoint: str,
    time_field: str,
) -> Optional[list]:
    """Query recent data for a digital twin from the data API.

    Args:
        data_access (dict): Data access parameters.
        last_minutes (int): Minutes back to query.
        digital_twin_instance_id (str): Digital Twin instance ID.
        endpoint (str): Data endpoint.
        time_field (str): Time field to filter (time_received or time_observed).

    Returns:
        Optional[list]: List of queried items or None.
    """
    recent_time = datetime.now(timezone.utc) - timedelta(minutes=last_minutes)
    recent_time_iso = recent_time.isoformat().replace("+00:00", "Z")
    query = {
        "$and": [
            {"digital_twin_instance_id": digital_twin_instance_id},
            {time_field: {"$gte": {"$date": recent_time_iso}}},
        ]
    }
    r = requests.get(
        url=f"{data_access['iot_data_endpoint']}/{endpoint}",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {data_access['token']}",
        },
        params={
            "q": json.dumps(query),
            "limit": 100,
            "offset": 0,
        },
    )
    if r.status_code != requests.codes.ok:
        logger.error("Unable to query data API")
        logger.error("  Status : %s", r.status_code)
        logger.error("  Message: %s", r.text)
        return None
    return r.json()["items"]


def get_recent_raw_data(
    data_access: dict, digital_twin_instance_id: str, last_minutes: int
) -> Optional[list]:
    """Query recent raw data for a digital twin.

    Args:
        data_access (dict): Data access parameters.
        digital_twin_instance_id (str): Digital Twin instance ID.
        last_minutes (int): Minutes back to query.

    Returns:
        Optional[list]: List of raw data or None.
    """
    return get_recent_data(
        data_access=data_access,
        last_minutes=last_minutes,
        digital_twin_instance_id=digital_twin_instance_id,
        endpoint="rawData",
        time_field="time_received",
    )


def get_recent_historized_data(
    data_access: dict, digital_twin_instance_id: str, last_minutes: int
) -> Optional[list]:
    """Query recent historized data for a digital twin.

    Args:
        data_access (dict): Data access parameters.
        digital_twin_instance_id (str): Digital Twin instance ID.
        last_minutes (int): Minutes back to query.

    Returns:
        Optional[list]: List of historized data or None.
    """
    return get_recent_data(
        data_access=data_access,
        last_minutes=last_minutes,
        digital_twin_instance_id=digital_twin_instance_id,
        endpoint="historizedData",
        time_field="time_observed",
    )


def get_recent_rejected_data(
    data_access: dict, digital_twin_instance_id: str, last_minutes: int
) -> Optional[list]:
    """Query recent rejected data for a digital twin.

    Args:
        data_access (dict): Data access parameters.
        digital_twin_instance_id (str): Digital Twin instance ID.
        last_minutes (int): Minutes back to query.

    Returns:
        Optional[list]: List of rejected data or None.
    """
    return get_recent_data(
        data_access=data_access,
        last_minutes=last_minutes,
        digital_twin_instance_id=digital_twin_instance_id,
        endpoint="rejectedData",
        time_field="time_received",
    )
