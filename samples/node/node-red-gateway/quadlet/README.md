# Quadlet runtime

These units run the Node-RED gateway sample with Podman Quadlet.

Install the sample files:

```sh
mkdir -p ~/.config/containers/systemd ~/.config/oci-iot-node-red-gateway
mkdir -p ~/.config/oci-iot-node-red-gateway/flows
mkdir -p ~/.config/oci-iot-node-red-gateway/mosquitto
mkdir -p ~/.config/oci-iot-node-red-gateway/nodered
cp ../flows/flows.json ../flows/flows_cred.template.json ~/.config/oci-iot-node-red-gateway/flows/
cp ../mosquitto/mosquitto.conf ~/.config/oci-iot-node-red-gateway/mosquitto/
cp ../nodered/package.json ../nodered/seed-sample.sh ../nodered/settings.js ~/.config/oci-iot-node-red-gateway/nodered/
cp oci-iot-node-red-gateway.env.example ~/.config/oci-iot-node-red-gateway/oci-iot-node-red-gateway.env
cp *.container *.network *.volume ~/.config/containers/systemd/
```

Edit the installed
`~/.config/oci-iot-node-red-gateway/oci-iot-node-red-gateway.env` file with
your OCI IoT gateway values.

Reload and start:

```sh
systemctl --user daemon-reload
systemctl --user reset-failed oci-iot-node-red.service
systemctl --user start oci-iot-mosquitto.service oci-iot-node-red.service
```

Node-RED stores runtime state in the `oci-iot-node-red-data` Podman volume.
The seed script copies the sample flows and credential template into that
volume only on first startup.

Check status and logs:

```sh
systemctl --user status oci-iot-mosquitto.service oci-iot-node-red.service
podman logs oci-iot-node-red
podman logs -f oci-iot-node-red
podman logs -f oci-iot-mosquitto
journalctl --user -u oci-iot-node-red.service -n 100 --no-pager
journalctl --user -u oci-iot-node-red.service -f
journalctl CONTAINER_NAME=oci-iot-node-red -n 100 --no-pager
journalctl CONTAINER_NAME=oci-iot-mosquitto -n 100 --no-pager
podman exec oci-iot-node-red getent hosts mosquitto
```

If systemd reports `start-limit-hit`, run `systemctl --user reset-failed
oci-iot-node-red.service` before starting the service again. Use `podman logs`
for the container output. A bare `journalctl --user` can be empty on some
rootless Podman hosts; unit-filtered `journalctl --user -u ...` shows user
service entries when the host records them, and `journalctl CONTAINER_NAME=...`
shows container entries when the journald log driver is available.

The Mosquitto container has the network alias `mosquitto` so the same
`LOCAL_MQTT_HOST=mosquitto` setting works with Docker Compose and Quadlet.
If Node-RED reports MQTT connection failures, verify that the alias resolves
from inside the Node-RED container with the `podman exec` command shown above.

Stop the sample:

```sh
systemctl --user stop oci-iot-node-red.service oci-iot-mosquitto.service
```
