# Sending observed time in device payload

## The `timeObserved` property

Digital twins with telemetry in structured format will by default set the Time Observed
property to the time the payload was received.

You can override this with data from the payload by assigning the `timeObserved` property
in the envelope mapping section of the digital twin adapter envelope.

If a default adapter is used, the generated envelope will already contain a mapping:

```json
"envelopeMapping": {
    "timeObserved": "$.time"
}
```

This means that if a `time` field is present in the payload, it will be used as the
observed time; if not, it will default to the received time.

## Data format

The `timeObserved` property is a POSIX time expressed in microseconds; that is: the
number of microseconds that have elapsed since January 1, 1970 (midnight UTC/GMT), also
known as Unix time or Epoch time.

The following sample payload (from the [publish-mqtt](../../python/publish-mqtt/)
example) will set the observed time to: Wednesday, September 10, 2025 13:47:05.226854 UTC:

```json
{
    "time": 1757512025226854,
    "sht_temperature": 23.8,
    "qmp_temperature": 24.4,
    "humidity": 56.1,
    "pressure": 1012.2,
    "count": 1,
}
```

## Conversion

If the device sends a date string (e.g. in ISO-8601 format), it must be converted to the
above format in the envelope mapping.

The IoT Platform mappings can be done with JsonPath or JQ expression. To facilitate the
conversion of a date string to POSIX time format, the Platform provides an additional
JQ function: `fromdateformat`

To accept a payload in the following format:

```json
{
    "iso_time": "2025-09-10T13:47:05.226854Z",
    "sht_temperature": 23.8,
    ...
}
```

we can use the following envelope mapping:

```json
"envelopeMapping": {
    "timeObserved": "${.iso_time | fromdateformat(\"yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'\")}"
}
```

The patterns used for parsing are compatible with the [Java DateTimeFormatter](https://docs.oracle.com/en/java/javase/23/docs/api/java.base/java/time/format/DateTimeFormatter.html#patterns).

Note that such conversion might fail if the payload field (`iso_time` in this case) is missing
from the payload, as the function might not accept a null value.
If the field is optional, null values should be handled in the expression. For example:

```json
"envelopeMapping": {
    "timeObserved": "${if .iso_time == null then null else .iso_time | fromdateformat(\"yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'\") end}"
}
```
