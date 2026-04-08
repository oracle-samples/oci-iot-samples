from archive_domain.iot_domain import resolve_retention_days


class _FailingLookup:
    def get_retention_days(self):
        raise RuntimeError("lookup failed")


class _PartialLookup:
    def get_retention_days(self):
        return {"raw": 16, "historized": 30}


def test_resolve_retention_days_falls_back_to_config_values():
    retention = resolve_retention_days(
        lookup_client=_FailingLookup(),
        configured_overrides={"raw": 10, "historized": 20, "rejected": 30},
    )

    assert retention == {"raw": 10, "historized": 20, "rejected": 30}


def test_resolve_retention_days_merges_live_lookup_and_overrides():
    retention = resolve_retention_days(
        lookup_client=_PartialLookup(),
        configured_overrides={"raw": None, "historized": None, "rejected": 12},
    )

    assert retention == {"raw": 16, "historized": 30, "rejected": 12}
