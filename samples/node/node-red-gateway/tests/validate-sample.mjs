#!/usr/bin/env node

import { readFile, stat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const sampleDir = dirname(testDir);

const requiredFiles = [
  'docker-compose.yaml',
  'podman-compose.yaml',
  'README.md',
  '.env.example',
  'data/gateway-model.json',
  'data/gateway-adapter-envelope.json',
  'data/gateway-adapter-routes.json',
  'data/m5-model.json',
  'data/m5-adapter-envelope.json',
  'data/m5-adapter-routes.json',
  'data/gateway-metrics-example.json',
  'data/m5-identify-command.json',
  'data/m5-set-interval-command.json',
  'flows/flows.json',
  'flows/flows_cred.template.json',
  'images/node-red-gateway.png',
  'images/node-red-simulators.png',
  'mosquitto/mosquitto.conf',
  'nodered/package.json',
  'nodered/seed-sample.sh',
  'nodered/settings.js',
  'quadlet/README.md',
  'quadlet/oci-iot-node-red-gateway.network',
  'quadlet/oci-iot-node-red-data.volume',
  'quadlet/oci-iot-node-red-gateway.env.example',
  'quadlet/oci-iot-mosquitto.container',
  'quadlet/oci-iot-node-red.container',
];

for (const file of requiredFiles) {
  const filePath = join(sampleDir, file);
  let fileStat;

  try {
    fileStat = await stat(filePath);
  } catch {
    throw new Error(`Missing file: ${file}`);
  }

  if (!fileStat.isFile()) {
    throw new Error(`Required path is not a file: ${file}`);
  }
}

const requiredEnvKeys = [
  'IOT_DEVICE_HOST',
  'IOT_GATEWAY_EXTERNAL_KEY',
  'IOT_GATEWAY_SECRET',
  'LOCAL_MQTT_HOST',
  'LOCAL_MQTT_PORT',
  'GATEWAY_METRICS_INTERVAL_SECONDS',
];

const envExample = await readFile(join(sampleDir, '.env.example'), 'utf8');

for (const key of requiredEnvKeys) {
  if (!new RegExp(`^${key}=`, 'm').test(envExample)) {
    throw new Error(`Missing .env.example key: ${key}`);
  }
}
assertNotContains(envExample, 'IOT_BASE_ENDPOINT', '.env.example');

async function readJson(file) {
  const text = await readFile(join(sampleDir, file), 'utf8');
  return JSON.parse(text);
}

async function readText(file) {
  return readFile(join(sampleDir, file), 'utf8');
}

function assertContains(text, expected, file) {
  if (typeof text !== 'string') {
    throw new Error(`${file} must be a string containing ${expected}`);
  }
  if (!text.includes(expected)) {
    throw new Error(`${file} must contain ${expected}`);
  }
}

function assertNotContains(text, unexpected, file) {
  if (text.includes(unexpected)) {
    throw new Error(`${file} must not contain ${unexpected}`);
  }
}

function assertMatches(text, pattern, file, message) {
  if (!pattern.test(text)) {
    throw new Error(`${file} ${message}`);
  }
}

function assertNoDependency(packageJson, dependencyName, file) {
  const dependencySections = ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies'];

  for (const section of dependencySections) {
    if (Object.hasOwn(packageJson[section] ?? {}, dependencyName)) {
      throw new Error(`${file} must not include ${dependencyName}`);
    }
  }
}

function assertModelId(model, expectedId, file) {
  if (model['@id'] !== expectedId) {
    throw new Error(`${file} must use @id ${expectedId}`);
  }
}

function assertModelContents(model, names, file) {
  const contents = Array.isArray(model.contents) ? model.contents : [];
  const contentNames = new Set(contents.map((content) => content.name));

  for (const name of names) {
    if (!contentNames.has(name)) {
      throw new Error(`${file} missing content ${name}`);
    }
  }
}

function assertModelSchemas(model, schemas, file) {
  const contents = Array.isArray(model.contents) ? model.contents : [];
  const contentsByName = new Map(contents.map((content) => [content.name, content]));

  for (const [name, expectedSchema] of Object.entries(schemas)) {
    const content = contentsByName.get(name);
    const actualSchema = content?.schema?.['@type'] ?? content?.schema;

    if (actualSchema !== expectedSchema) {
      throw new Error(`${file} content ${name} must use schema ${expectedSchema}`);
    }
  }
}

function assertEnvelope(envelope, expectedEndpoint, referencePayload, file) {
  if (envelope.referenceEndpoint !== expectedEndpoint) {
    throw new Error(`${file} must use referenceEndpoint ${expectedEndpoint}`);
  }

  if (envelope.envelopeMapping?.timeObserved !== '$.time') {
    throw new Error(`${file} must map envelopeMapping.timeObserved from $.time`);
  }

  if (envelope.referencePayload?.dataFormat !== 'JSON') {
    throw new Error(`${file} must use JSON referencePayload dataFormat`);
  }

  assertObjectKeys(
    envelope.referencePayload?.data,
    Object.keys(referencePayload),
    `${file} referencePayload.data`,
  );

  for (const [key, expectedValue] of Object.entries(referencePayload)) {
    assertSameValue(envelope.referencePayload.data[key], expectedValue, `${file} referencePayload.data.${key}`);
  }
}

function assertRoutes(routes, routeTerm, payloadMapping, file) {
  if (!Array.isArray(routes)) {
    throw new Error(`${file} must be a JSON array`);
  }

  const dataRoute = routes.find((route) => route.condition?.includes(routeTerm));
  if (!dataRoute) {
    throw new Error(`${file} must include a route condition containing ${routeTerm}`);
  }

  assertObjectKeys(dataRoute.payloadMapping, Object.keys(payloadMapping), `${file} ${routeTerm} payloadMapping`);
  for (const [target, source] of Object.entries(payloadMapping)) {
    if (dataRoute.payloadMapping?.[target] !== source) {
      throw new Error(`${file} must map ${target} from ${source}`);
    }
  }

  const fallbackRoute = routes.find((route) => route.condition === '*');
  assertObjectKeys(fallbackRoute?.payloadMapping, ['$.system'], `${file} fallback payloadMapping`);
  if (fallbackRoute?.payloadMapping?.['$.system'] !== '${.}') {
    throw new Error(`${file} must include fallback mapping from full payload to $.system`);
  }
}

function assertObjectKeys(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }

  const actualKeys = Object.keys(value).sort();
  const expectedKeys = [...keys].sort();

  if (JSON.stringify(actualKeys) !== JSON.stringify(expectedKeys)) {
    throw new Error(`${label} must have exactly keys: ${expectedKeys.join(', ')}`);
  }
}

function assertEmptyObject(value, label) {
  assertObject(value, label);

  if (Object.keys(value).length !== 0) {
    throw new Error(`${label} must be empty`);
  }
}

function assertSameValue(actual, expected, label) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label} must be ${JSON.stringify(expected)}`);
  }
}

function assertNumber(value, label) {
  if (typeof value !== 'number') {
    throw new Error(`${label} must be a number`);
  }
}

function assertObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
}

function assertFlowNode(flow, predicate, label) {
  const node = flow.find(predicate);

  if (!node) {
    throw new Error(`flows/flows.json missing ${label}`);
  }

  return node;
}

function assertGatewayNode(flows, gatewayTabId, predicate, label) {
  return assertFlowNode(flows, (node) => node.z === gatewayTabId && predicate(node), `Gateway ${label}`);
}

function assertTabNode(flows, tabId, tabLabel, predicate, label) {
  return assertFlowNode(flows, (node) => node.z === tabId && predicate(node), `${tabLabel} ${label}`);
}

function assertNodePosition(node, expectedX, expectedY, label) {
  if (node.x !== expectedX || node.y !== expectedY) {
    throw new Error(`${label} must be positioned at (${expectedX}, ${expectedY}), got (${node.x}, ${node.y})`);
  }
}

function createFunctionRuntime(initialFlow = {}) {
  const flowStore = new Map(Object.entries(initialFlow));
  const contextStore = new Map();
  const statuses = [];
  return {
    flow: {
      get: (key) => flowStore.get(key),
      set: (key, value) => flowStore.set(key, value),
    },
    context: {
      get: (key) => contextStore.get(key),
      set: (key, value) => contextStore.set(key, value),
    },
    env: {
      get: (key) => (key === 'GATEWAY_METRICS_INTERVAL_SECONDS' ? '60' : undefined),
    },
    node: {
      status: (value) => statuses.push(value),
    },
    statuses,
    flowStore,
  };
}

function runFunctionNode(functionNode, msg, runtime) {
  const run = new Function('msg', 'flow', 'context', 'env', 'node', 'Buffer', functionNode.func);
  return run(msg, runtime.flow, runtime.context, runtime.env, runtime.node, Buffer);
}

function assertYamlBlock(text, key, indent, file) {
  const lines = text.split('\n');
  const keyLine = new RegExp(`^ {${indent}}${key}:\\s*$`);
  const start = lines.findIndex((line) => keyLine.test(line));

  if (start === -1) {
    throw new Error(`${file} missing YAML block: ${key}`);
  }

  const blockLines = [lines[start]];
  for (const line of lines.slice(start + 1)) {
    const match = line.match(/^( *)\S/);
    if (match && match[1].length <= indent) {
      break;
    }
    blockLines.push(line);
  }

  return blockLines.join('\n');
}

function envKeys(text) {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .map((line) => line.split('=', 1)[0])
    .sort();
}

const gatewayFields = [
  'messagesReceived',
  'messagesForwarded',
  'commandsReceived',
  'commandsForwarded',
  'responsesForwarded',
  'localDevices',
  'uptimeSeconds',
  'system',
];

const gatewayMetricFields = [
  'commandsForwarded',
  'commandsReceived',
  'localDevices',
  'messagesForwarded',
  'messagesReceived',
  'responsesForwarded',
  'system',
  'time',
  'uptimeSeconds',
];

const gatewayMetricPayloadMapping = {
  '$.commandsForwarded': '$.commandsForwarded',
  '$.commandsReceived': '$.commandsReceived',
  '$.localDevices': '$.localDevices',
  '$.messagesForwarded': '$.messagesForwarded',
  '$.messagesReceived': '$.messagesReceived',
  '$.responsesForwarded': '$.responsesForwarded',
  '$.system': '$.system',
  '$.uptimeSeconds': '$.uptimeSeconds',
};

const gatewayReferencePayload = {
  commandsForwarded: 0,
  commandsReceived: 0,
  localDevices: 0,
  messagesForwarded: 0,
  messagesReceived: 0,
  responsesForwarded: 0,
  system: {},
  time: 0,
  uptimeSeconds: 0,
};

const m5Fields = ['sht_temperature', 'qmp_temperature', 'humidity', 'pressure', 'count', 'system'];

const m5TelemetryPayloadMapping = {
  '$.count': '$.count',
  '$.humidity': '$.humidity',
  '$.pressure': '$.pressure',
  '$.qmp_temperature': '$.qmp_temperature',
  '$.sht_temperature': '$.sht_temperature',
};

const m5ReferencePayload = {
  count: 0,
  humidity: 0,
  pressure: 0,
  qmp_temperature: 0,
  sht_temperature: 0,
  system: {},
  time: 0,
};

const gatewayModel = await readJson('data/gateway-model.json');
assertModelId(gatewayModel, 'dtmi:com:oracle:iot:samples:nodered:gateway;1', 'gateway-model.json');
assertModelContents(gatewayModel, gatewayFields, 'gateway-model.json');
assertModelSchemas(
  gatewayModel,
  {
    commandsForwarded: 'integer',
    commandsReceived: 'integer',
    localDevices: 'integer',
    messagesForwarded: 'integer',
    messagesReceived: 'integer',
    responsesForwarded: 'integer',
    system: 'Object',
    uptimeSeconds: 'integer',
  },
  'gateway-model.json',
);

const gatewayEnvelope = await readJson('data/gateway-adapter-envelope.json');
assertEnvelope(gatewayEnvelope, 'gateway/metrics', gatewayReferencePayload, 'gateway-adapter-envelope.json');
assertSameValue(
  gatewayEnvelope.envelopeMapping.target,
  '${if endpoint(1) == "m5" then endpoint(2) else null end}',
  'gateway-adapter-envelope.json target mapping',
);
assertContains(
  gatewayEnvelope.envelopeMapping.target,
  'else null',
  'gateway-adapter-envelope.json target mapping',
);
assertNotContains(gatewayEnvelope.envelopeMapping.target, 'endpoint(3)', 'gateway-adapter-envelope.json target mapping');
assertNotContains(gatewayEnvelope.envelopeMapping.target, 'endpoint(4)', 'gateway-adapter-envelope.json target mapping');
assertSameValue(gatewayEnvelope.envelopeMapping.contentRoot, '$', 'gateway-adapter-envelope.json contentRoot');

const gatewayRoutes = await readJson('data/gateway-adapter-routes.json');
assertRoutes(gatewayRoutes, 'metrics', gatewayMetricPayloadMapping, 'gateway-adapter-routes.json');
assertSameValue(
  gatewayRoutes[0].condition,
  '${endpoint(1) == "gateway" and endpoint(2) == "metrics"}',
  'gateway-adapter-routes.json metrics route condition',
);
assertNotContains(gatewayRoutes[0].condition, 'endpoint(3)', 'gateway-adapter-routes.json metrics route condition');
assertNotContains(gatewayRoutes[0].condition, 'endpoint(4)', 'gateway-adapter-routes.json metrics route condition');

const gatewayMetrics = await readJson('data/gateway-metrics-example.json');
assertObjectKeys(gatewayMetrics, gatewayMetricFields, 'gateway-metrics-example.json');
for (const field of gatewayMetricFields.filter((field) => field !== 'system')) {
  assertNumber(gatewayMetrics[field], `gateway-metrics-example.json ${field}`);
}
assertObject(gatewayMetrics.system, 'gateway-metrics-example.json system');

const m5Model = await readJson('data/m5-model.json');
assertModelId(m5Model, 'dtmi:com:oracle:iot:samples:nodered:m5:env;1', 'm5-model.json');
assertModelContents(m5Model, m5Fields, 'm5-model.json');

const m5Envelope = await readJson('data/m5-adapter-envelope.json');
assertEnvelope(m5Envelope, 'm5/m5-01/telemetry', m5ReferencePayload, 'm5-adapter-envelope.json');

const m5Routes = await readJson('data/m5-adapter-routes.json');
assertRoutes(m5Routes, 'telemetry', m5TelemetryPayloadMapping, 'm5-adapter-routes.json');
assertSameValue(
  m5Routes[0].condition,
  '${endpoint(1) == "m5" and endpoint(3) == "telemetry"}',
  'm5-adapter-routes.json telemetry route condition',
);
assertNotContains(m5Routes[0].condition, 'endpoint(4)', 'm5-adapter-routes.json telemetry route condition');
assertNotContains(m5Routes[0].condition, 'endpoint(5)', 'm5-adapter-routes.json telemetry route condition');

const identifyCommand = await readJson('data/m5-identify-command.json');
assertObjectKeys(identifyCommand, ['identify'], 'm5-identify-command.json');
assertSameValue(identifyCommand.identify, true, 'm5-identify-command.json identify');

const setIntervalCommand = await readJson('data/m5-set-interval-command.json');
assertObjectKeys(setIntervalCommand, ['setIntervalSeconds'], 'm5-set-interval-command.json');
assertSameValue(setIntervalCommand.setIntervalSeconds, 5, 'm5-set-interval-command.json setIntervalSeconds');

const dockerCompose = await readText('docker-compose.yaml');
assertContains(dockerCompose, 'services:', 'docker-compose.yaml');
assertMatches(dockerCompose, /^networks:\n {2}gateway:\s*$/m, 'docker-compose.yaml', 'must define shared gateway network');

const composeMosquitto = assertYamlBlock(dockerCompose, 'mosquitto', 2, 'docker-compose.yaml');
assertContains(composeMosquitto, 'image: eclipse-mosquitto:2', 'docker-compose.yaml mosquitto service');
assertContains(composeMosquitto, '"127.0.0.1:1883:1883"', 'docker-compose.yaml mosquitto service');
assertContains(
  composeMosquitto,
  './mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro',
  'docker-compose.yaml mosquitto service',
);
assertMatches(composeMosquitto, /networks:\n\s+- gateway/m, 'docker-compose.yaml mosquitto service', 'must use gateway network');

const composeNodeRed = assertYamlBlock(dockerCompose, 'node-red', 2, 'docker-compose.yaml');
assertContains(composeNodeRed, 'image: nodered/node-red:latest', 'docker-compose.yaml node-red service');
assertContains(composeNodeRed, 'entrypoint: /bin/bash', 'docker-compose.yaml node-red service');
assertContains(composeNodeRed, 'command: /opt/oci-iot-node-red/seed-sample.sh', 'docker-compose.yaml node-red service');
assertContains(composeNodeRed, '"127.0.0.1:1880:1880"', 'docker-compose.yaml node-red service');
assertMatches(
  composeNodeRed,
  /depends_on:\n\s+- mosquitto/m,
  'docker-compose.yaml node-red service',
  'must depend on mosquitto',
);
assertMatches(composeNodeRed, /env_file:\n\s+- \.env/m, 'docker-compose.yaml node-red service', 'must use .env env_file');
assertNotContains(composeNodeRed, 'environment:', 'docker-compose.yaml node-red service');
for (const volume of [
  'node-red-data:/data',
  './nodered/seed-sample.sh:/opt/oci-iot-node-red/seed-sample.sh:ro',
  './flows/flows.json:/opt/oci-iot-node-red/flows.json:ro',
  './flows/flows_cred.template.json:/opt/oci-iot-node-red/flows_cred.json:ro',
  './nodered/settings.js:/data/settings.js:ro',
  './nodered/package.json:/data/package.json:ro',
]) {
  assertContains(composeNodeRed, volume, 'docker-compose.yaml node-red service');
}
assertMatches(dockerCompose, /^volumes:\n {2}node-red-data:\s*$/m, 'docker-compose.yaml', 'must define node-red-data volume');
assertMatches(composeNodeRed, /networks:\n\s+- gateway/m, 'docker-compose.yaml node-red service', 'must use gateway network');

const podmanCompose = await readText('podman-compose.yaml');
assertContains(podmanCompose, 'services:', 'podman-compose.yaml');
assertContains(podmanCompose, 'image: eclipse-mosquitto:2', 'podman-compose.yaml');
assertContains(podmanCompose, './mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro,Z', 'podman-compose.yaml');
assertContains(podmanCompose, 'aliases:', 'podman-compose.yaml');
assertContains(podmanCompose, '- mosquitto', 'podman-compose.yaml');
assertContains(podmanCompose, 'image: nodered/node-red:latest', 'podman-compose.yaml');
assertContains(podmanCompose, 'entrypoint: /bin/bash', 'podman-compose.yaml');
assertContains(podmanCompose, 'command: /opt/oci-iot-node-red/seed-sample.sh', 'podman-compose.yaml');
assertContains(podmanCompose, 'node-red-data:/data:U', 'podman-compose.yaml');
assertContains(podmanCompose, 'name: oci-iot-node-red-compose-data', 'podman-compose.yaml');
for (const volume of [
  './nodered/seed-sample.sh:/opt/oci-iot-node-red/seed-sample.sh:ro,Z',
  './flows/flows.json:/opt/oci-iot-node-red/flows.json:ro,Z',
  './flows/flows_cred.template.json:/opt/oci-iot-node-red/flows_cred.json:ro,Z',
  './nodered/settings.js:/data/settings.js:ro,Z',
  './nodered/package.json:/data/package.json:ro,Z',
]) {
  assertContains(podmanCompose, volume, 'podman-compose.yaml');
}
assertMatches(podmanCompose, /^volumes:\n {2}node-red-data:\s*$/m, 'podman-compose.yaml', 'must define node-red-data volume');

const mosquittoConfig = await readText('mosquitto/mosquitto.conf');
assertContains(mosquittoConfig, 'listener 1883 0.0.0.0', 'mosquitto.conf');
assertContains(mosquittoConfig, 'allow_anonymous true', 'mosquitto.conf');
assertContains(mosquittoConfig, 'persistence false', 'mosquitto.conf');
assertContains(mosquittoConfig, 'log_type all', 'mosquitto.conf');

const nodeRedPackage = await readJson('nodered/package.json');
assertSameValue(nodeRedPackage.name, 'oci-iot-node-red-gateway-sample', 'nodered/package.json name');
assertSameValue(nodeRedPackage.private, true, 'nodered/package.json private');
if (typeof nodeRedPackage.description !== 'string' || nodeRedPackage.description.length === 0) {
  throw new Error('nodered/package.json description must be a non-empty string');
}
assertEmptyObject(nodeRedPackage.dependencies, 'nodered/package.json dependencies');
assertNoDependency(nodeRedPackage, 'node-red-dashboard', 'nodered/package.json');
assertNoDependency(nodeRedPackage, 'node-red-contrib-mqtt-broker', 'nodered/package.json');

const nodeRedSettings = await readText('nodered/settings.js');
assertContains(nodeRedSettings, 'flowFile: "flows.json"', 'nodered/settings.js');

const nodeRedSeedScript = await readText('nodered/seed-sample.sh');
assertContains(nodeRedSeedScript, '/data/.oci-iot-node-red-gateway-seeded', 'nodered/seed-sample.sh');
assertContains(
  nodeRedSeedScript,
  'WARNING: please check you have started this container',
  'nodered/seed-sample.sh',
);
assertContains(nodeRedSeedScript, 'cp /opt/oci-iot-node-red/flows.json /data/flows.json', 'nodered/seed-sample.sh');
assertContains(
  nodeRedSeedScript,
  'cp /opt/oci-iot-node-red/flows_cred.json /data/flows_cred.json',
  'nodered/seed-sample.sh',
);
assertContains(nodeRedSeedScript, 'exec /usr/src/node-red/entrypoint.sh', 'nodered/seed-sample.sh');

const flows = await readJson('flows/flows.json');
if (!Array.isArray(flows)) {
  throw new Error('flows/flows.json must be a JSON array');
}
const flowText = await readText('flows/flows.json');
assertNotContains(flowText, 'IOT_BASE_ENDPOINT', 'flows/flows.json');

const debugNodes = flows.filter((node) => node.type === 'debug');
const examplesTabForDebug = flows.find((node) => node.type === 'tab' && node.label === 'Examples');
if (debugNodes.length !== 1 || debugNodes[0].name !== 'Example debug' || debugNodes[0].z !== examplesTabForDebug?.id) {
  throw new Error('flows/flows.json must include only the Examples tab Example debug node');
}

const flowNodeIds = new Set(flows.map((node) => node.id));
for (const node of flows) {
  for (const wireGroup of node.wires ?? []) {
    for (const wireTarget of wireGroup) {
      if (!flowNodeIds.has(wireTarget)) {
        throw new Error(`flows/flows.json node ${node.id} wires unknown target ${wireTarget}`);
      }
    }
  }
}

for (const node of flows.filter((entry) => entry.type === 'function')) {
  assertContains(node.func, "context.get('handled')", `function node ${node.name}`);
  assertContains(node.func, "context.set('handled', handled)", `function node ${node.name}`);
  assertContains(node.func, 'node.status({', `function node ${node.name}`);
  assertContains(node.func, 'handled`', `function node ${node.name}`);
}

const flowCredentialsTemplate = await readJson('flows/flows_cred.template.json');
assertSameValue(
  flowCredentialsTemplate['oci-iot-gateway-broker']?.user,
  '${IOT_GATEWAY_EXTERNAL_KEY}',
  'flows_cred.template.json OCI IoT Gateway MQTT user',
);
assertSameValue(
  flowCredentialsTemplate['oci-iot-gateway-broker']?.password,
  '${IOT_GATEWAY_SECRET}',
  'flows_cred.template.json OCI IoT Gateway MQTT password',
);

const gatewayTab = assertFlowNode(flows, (node) => node.type === 'tab' && node.label === 'Gateway', 'Gateway flow tab');
assertGatewayNode(
  flows,
  gatewayTab.id,
  (node) => node.type === 'mqtt in' && node.topic === 'devices/+/telemetry',
  'MQTT in topic devices/+/telemetry',
);
assertGatewayNode(
  flows,
  gatewayTab.id,
  (node) => node.type === 'mqtt in' && node.topic === 'm5/+/cmd/+',
  'MQTT in topic m5/+/cmd/+',
);
assertGatewayNode(
  flows,
  gatewayTab.id,
  (node) => node.type === 'mqtt in' && node.topic === 'devices/+/rsp/+',
  'MQTT in topic devices/+/rsp/+',
);
for (const functionName of [
  'Map local telemetry to OCI endpoint',
  'Map OCI command to local topic',
  'Map local response to OCI topic',
  'Build gateway metrics',
]) {
  assertGatewayNode(
    flows,
    gatewayTab.id,
    (node) => node.type === 'function' && node.name === functionName,
    `function node ${functionName}`,
  );
}
const commandMapper = assertGatewayNode(
  flows,
  gatewayTab.id,
  (node) => node.type === 'function' && node.name === 'Map OCI command to local topic',
  'function node Map OCI command to local topic',
);
assertNotContains(commandMapper.func, 'IOT_BASE_ENDPOINT', 'Map OCI command to local topic');
assertNotContains(commandMapper.func, 'baseSegments', 'Map OCI command to local topic');
assertNotContains(commandMapper.func, 'topicParts.slice', 'Map OCI command to local topic');
assertContains(commandMapper.func, "topicParts[0] !== 'm5'", 'Map OCI command to local topic');
assertContains(commandMapper.func, "allowedDevices.has(deviceId)", 'Map OCI command to local topic');
const responseMapper = assertGatewayNode(
  flows,
  gatewayTab.id,
  (node) => node.type === 'function' && node.name === 'Map local response to OCI topic',
  'function node Map local response to OCI topic',
);
assertContains(responseMapper.func, "new Set(['m5-01', 'm5-02'])", 'Map local response to OCI topic');
assertContains(responseMapper.func, "allowedDevices.has(deviceId)", 'Map local response to OCI topic');
const metricsTimer = assertGatewayNode(
  flows,
  gatewayTab.id,
  (node) => node.type === 'inject' && node.name === 'Gateway metrics interval',
  'inject node Gateway metrics interval',
);
assertSameValue(
  metricsTimer.repeat,
  '${GATEWAY_METRICS_INTERVAL_SECONDS}',
  'Gateway metrics interval repeat',
);
assertFlowNode(
  flows,
  (node) => node.type === 'mqtt-broker' && node.name === 'Local Mosquitto',
  'mqtt-broker config node Local Mosquitto',
);
assertFlowNode(
  flows,
  (node) => node.type === 'mqtt-broker' && node.name === 'OCI IoT Gateway MQTT',
  'mqtt-broker config node OCI IoT Gateway MQTT',
);

const simulatorsTab = assertFlowNode(flows, (node) => node.type === 'tab' && node.label === 'Simulators', 'Simulators flow tab');
const simulatorPositions = {
  'm5-01 simulator start': [170, 100],
  'Build m5-01 telemetry': [430, 100],
  'Publish m5-01 telemetry': [730, 80],
  'm5-01 telemetry cadence': [730, 140],
  'm5-01 commands': [170, 220],
  'Handle m5-01 command': [430, 220],
  'Publish m5-01 response': [730, 220],
  'm5-02 simulator start': [170, 360],
  'Build m5-02 telemetry': [430, 360],
  'Publish m5-02 telemetry': [730, 340],
  'm5-02 telemetry cadence': [730, 400],
  'm5-02 commands': [170, 500],
  'Handle m5-02 command': [430, 500],
  'Publish m5-02 response': [730, 500],
};
for (const [name, [x, y]] of Object.entries(simulatorPositions)) {
  const node = assertTabNode(
    flows,
    simulatorsTab.id,
    'Simulators',
    (entry) => entry.name === name,
    `node ${name}`,
  );
  assertNodePosition(node, x, y, `Simulators node ${name}`);
}
for (const deviceId of ['m5-01', 'm5-02']) {
  const telemetryBuilder = assertTabNode(
    flows,
    simulatorsTab.id,
    'Simulators',
    (node) => node.type === 'function' && node.name === `Build ${deviceId} telemetry`,
    `function node Build ${deviceId} telemetry`,
  );
  for (const field of ['sht_temperature', 'qmp_temperature', 'humidity', 'pressure', 'count', 'time']) {
    assertContains(telemetryBuilder.func, field, `Build ${deviceId} telemetry`);
  }
  assertContains(telemetryBuilder.func, 'intervalSeconds', `Build ${deviceId} telemetry`);
  assertContains(telemetryBuilder.func, 'msg.delay', `Build ${deviceId} telemetry`);
  for (const expected of ['defaults', '...defaults', '...flow.get(key)', 'loopToken', 'running']) {
    assertContains(telemetryBuilder.func, expected, `Build ${deviceId} telemetry`);
  }
  assertNotContains(
    telemetryBuilder.func,
    'if (state.running && !state.disabled)',
    `Build ${deviceId} telemetry`,
  );
  assertContains(
    telemetryBuilder.func,
    `state.loopToken = \`${deviceId}-\${Date.now()}-\${Math.random()}\`;`,
    `Build ${deviceId} telemetry`,
  );
  for (const expected of ['stopped', "fill: 'red'", "shape: 'ring'"]) {
    assertContains(telemetryBuilder.func, expected, `Build ${deviceId} telemetry`);
  }
  assertNotContains(telemetryBuilder.func, 'simulatorControl', `Build ${deviceId} telemetry`);
  const stoppedRuntime = createFunctionRuntime({
    [`simulator:${deviceId}`]: {
      disabled: true,
      running: false,
      loopToken: 'stopped-loop',
    },
  });
  const stoppedResult = runFunctionNode(telemetryBuilder, { loopToken: 'stopped-loop' }, stoppedRuntime);
  if (stoppedResult !== null) {
    throw new Error(`Build ${deviceId} telemetry must return null for stopped loop messages`);
  }
  assertSameValue(
    stoppedRuntime.statuses.at(-1),
    { fill: 'red', shape: 'ring', text: 'stopped' },
    `Build ${deviceId} telemetry stopped status`,
  );
  const staleLoopRuntime = createFunctionRuntime({
    [`simulator:${deviceId}`]: {
      disabled: false,
      running: true,
      loopToken: 'current-loop',
    },
  });
  const staleLoopResult = runFunctionNode(telemetryBuilder, { loopToken: 'old-loop' }, staleLoopRuntime);
  if (staleLoopResult !== null) {
    throw new Error(`Build ${deviceId} telemetry must return null for stale loop messages`);
  }
  if (staleLoopRuntime.statuses.length !== 0) {
    throw new Error(`Build ${deviceId} telemetry must not show stopped status for stale loop messages`);
  }
  assertTabNode(
    flows,
    simulatorsTab.id,
    'Simulators',
    (node) => node.type === 'delay' && node.name === `${deviceId} telemetry cadence`,
    `delay node ${deviceId} telemetry cadence`,
  );
  assertTabNode(
    flows,
    simulatorsTab.id,
    'Simulators',
    (node) => node.type === 'mqtt out' && node.topic === `devices/${deviceId}/telemetry`,
    `MQTT out topic devices/${deviceId}/telemetry`,
  );
  assertTabNode(
    flows,
    simulatorsTab.id,
    'Simulators',
    (node) => node.type === 'mqtt in' && node.topic === `devices/${deviceId}/cmd/+`,
    `MQTT in topic devices/${deviceId}/cmd/+`,
  );
  const commandHandler = assertTabNode(
    flows,
    simulatorsTab.id,
    'Simulators',
    (node) => node.type === 'function' && node.name === `Handle ${deviceId} command`,
    `function node Handle ${deviceId} command`,
  );
  for (const expected of ['commandKey', 'identify', 'setIntervalSeconds', 'shutdown', `devices/${deviceId}/rsp/`]) {
    assertContains(commandHandler.func, expected, `Handle ${deviceId} command`);
  }
  for (const expected of ['defaults', '...defaults', '...flow.get(key)', 'loopToken', 'running']) {
    assertContains(commandHandler.func, expected, `Handle ${deviceId} command`);
  }
  assertNotContains(commandHandler.func, 'simulatorControl', `Handle ${deviceId} command`);
  if (commandHandler.outputs !== 1) {
    throw new Error(`Handle ${deviceId} command must have one output`);
  }
  const responseOut = assertTabNode(
    flows,
    simulatorsTab.id,
    'Simulators',
    (node) => node.type === 'mqtt out' && node.name === `Publish ${deviceId} response`,
    `MQTT out response node ${deviceId}`,
  );
  if (!commandHandler.wires?.[0]?.includes(responseOut.id)) {
    throw new Error(`Handle ${deviceId} command first output must wire to response MQTT node`);
  }
  if (commandHandler.wires?.some((output) => output.includes(telemetryBuilder.id))) {
    throw new Error(`Handle ${deviceId} command must not wire back to Build ${deviceId} telemetry`);
  }
  const shutdownRuntime = createFunctionRuntime();
  const shutdownResult = runFunctionNode(
    commandHandler,
    { topic: `devices/${deviceId}/cmd/shutdown`, payload: JSON.stringify({ shutdown: true }) },
    shutdownRuntime,
  );
  if (Array.isArray(shutdownResult) || !shutdownResult) {
    throw new Error(`Handle ${deviceId} command must return the response message for shutdown`);
  }
  const identifyRuntime = createFunctionRuntime();
  const identifyResult = runFunctionNode(
    commandHandler,
    { topic: `devices/${deviceId}/cmd/identify`, payload: JSON.stringify({ identify: true }) },
    identifyRuntime,
  );
  if (Array.isArray(identifyResult) || !identifyResult) {
    throw new Error(`Handle ${deviceId} command must return the response message for identify`);
  }
}

const examplesTab = assertFlowNode(flows, (node) => node.type === 'tab' && node.label === 'Examples', 'Examples flow tab');
const examplePositions = {
  'm5-01 telemetry example': [180, 100],
  'm5-02 telemetry example': [180, 170],
  'm5-01 command response example': [180, 240],
  'Publish example locally': [510, 170],
  'reset counters and clear shutdown example': [190, 360],
  'Reset counters and clear shutdown flags': [540, 360],
  'Example debug': [850, 360],
  'show topic mappings': [190, 460],
  'Build topic mapping examples': [540, 460],
};
for (const [name, [x, y]] of Object.entries(examplePositions)) {
  const node = assertTabNode(
    flows,
    examplesTab.id,
    'Examples',
    (entry) => entry.name === name,
    `node ${name}`,
  );
  assertNodePosition(node, x, y, `Examples node ${name}`);
}
const m501TelemetryExample = assertTabNode(
  flows,
  examplesTab.id,
  'Examples',
  (node) => node.type === 'inject' && node.name?.includes('m5-01 telemetry'),
  'inject node containing m5-01 telemetry',
);
assertNotContains(m501TelemetryExample.payload ?? '', '"time":0', 'm5-01 telemetry example payload');
const m502TelemetryExample = assertTabNode(
  flows,
  examplesTab.id,
  'Examples',
  (node) => node.type === 'inject' && node.name?.includes('m5-02 telemetry'),
  'inject node containing m5-02 telemetry',
);
assertNotContains(m502TelemetryExample.payload ?? '', '"time":0', 'm5-02 telemetry example payload');
assertTabNode(
  flows,
  examplesTab.id,
  'Examples',
  (node) => node.type === 'inject' && node.name?.includes('command response'),
  'inject node containing command response',
);
assertTabNode(
  flows,
  examplesTab.id,
  'Examples',
  (node) => node.type === 'inject' && node.name?.includes('reset counters'),
  'inject node containing reset counters',
);
for (const nodeName of [
  'm5-01 telemetry example',
  'm5-02 telemetry example',
  'm5-01 command response example',
  'Reset counters and clear shutdown flags',
  'Build topic mapping examples',
]) {
  const node = assertTabNode(
    flows,
    examplesTab.id,
    'Examples',
    (entry) => entry.name === nodeName,
    `node ${nodeName}`,
  );
  if (!node.wires?.some((wireGroup) => wireGroup.includes('examples-debug'))) {
    throw new Error(`Examples node ${nodeName} must wire to Example debug`);
  }
}
const topicMappings = assertTabNode(
  flows,
  examplesTab.id,
  'Examples',
  (node) => node.type === 'function' && node.name === 'Build topic mapping examples',
  'function node Build topic mapping examples',
);
for (const expected of ['devices/<device-id>/telemetry', 'm5/<device-id>/telemetry', 'devices/<device-id>/cmd/<command-key>', 'devices/<device-id>/rsp/<command-key>']) {
  assertContains(topicMappings.func, expected, 'Build topic mapping examples');
}

const quadletNetwork = await readText('quadlet/oci-iot-node-red-gateway.network');
assertContains(quadletNetwork, '[Network]', 'quadlet/oci-iot-node-red-gateway.network');
assertContains(
  quadletNetwork,
  'NetworkName=oci-iot-node-red-gateway',
  'quadlet/oci-iot-node-red-gateway.network',
);

const quadletNodeRedVolume = await readText('quadlet/oci-iot-node-red-data.volume');
assertContains(quadletNodeRedVolume, '[Volume]', 'quadlet/oci-iot-node-red-data.volume');
assertContains(
  quadletNodeRedVolume,
  'VolumeName=oci-iot-node-red-data',
  'quadlet/oci-iot-node-red-data.volume',
);

const quadletEnvExample = await readText('quadlet/oci-iot-node-red-gateway.env.example');
assertSameValue(envKeys(quadletEnvExample), envKeys(envExample), 'quadlet env example keys');
assertNotContains(quadletEnvExample, 'IOT_BASE_ENDPOINT', 'quadlet/oci-iot-node-red-gateway.env.example');

const quadletMosquitto = await readText('quadlet/oci-iot-mosquitto.container');
assertContains(quadletMosquitto, 'Image=docker.io/library/eclipse-mosquitto:2', 'quadlet/oci-iot-mosquitto.container');
assertContains(quadletMosquitto, 'PublishPort=127.0.0.1:1883:1883', 'quadlet/oci-iot-mosquitto.container');
assertContains(
  quadletMosquitto,
  'Volume=%h/.config/oci-iot-node-red-gateway/mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro,Z',
  'quadlet/oci-iot-mosquitto.container',
);
assertContains(
  quadletMosquitto,
  'Network=oci-iot-node-red-gateway.network',
  'quadlet/oci-iot-mosquitto.container',
);
assertContains(quadletMosquitto, 'NetworkAlias=mosquitto', 'quadlet/oci-iot-mosquitto.container');
assertContains(quadletMosquitto, 'LogDriver=journald', 'quadlet/oci-iot-mosquitto.container');
assertContains(quadletMosquitto, 'Requires=oci-iot-node-red-gateway-network.service', 'quadlet/oci-iot-mosquitto.container');

const quadletNodeRed = await readText('quadlet/oci-iot-node-red.container');
assertContains(quadletNodeRed, 'Image=docker.io/nodered/node-red:latest', 'quadlet/oci-iot-node-red.container');
assertContains(quadletNodeRed, 'PublishPort=127.0.0.1:1880:1880', 'quadlet/oci-iot-node-red.container');
assertContains(
  quadletNodeRed,
  'EnvironmentFile=%h/.config/oci-iot-node-red-gateway/oci-iot-node-red-gateway.env',
  'quadlet/oci-iot-node-red.container',
);
for (const volume of [
  'Entrypoint=/bin/bash',
  'Exec=/opt/oci-iot-node-red/seed-sample.sh',
  'Volume=oci-iot-node-red-data.volume:/data',
  'Volume=%h/.config/oci-iot-node-red-gateway/nodered/seed-sample.sh:/opt/oci-iot-node-red/seed-sample.sh:ro,Z',
  'Volume=%h/.config/oci-iot-node-red-gateway/flows/flows.json:/opt/oci-iot-node-red/flows.json:ro,Z',
  'Volume=%h/.config/oci-iot-node-red-gateway/flows/flows_cred.template.json:/opt/oci-iot-node-red/flows_cred.json:ro,Z',
  'Volume=%h/.config/oci-iot-node-red-gateway/nodered/settings.js:/data/settings.js:ro,Z',
  'Volume=%h/.config/oci-iot-node-red-gateway/nodered/package.json:/data/package.json:ro,Z',
]) {
  assertContains(quadletNodeRed, volume, 'quadlet/oci-iot-node-red.container');
}
assertContains(
  quadletNodeRed,
  'Network=oci-iot-node-red-gateway.network',
  'quadlet/oci-iot-node-red.container',
);
assertContains(quadletNodeRed, 'LogDriver=journald', 'quadlet/oci-iot-node-red.container');
assertContains(quadletNodeRed, 'Requires=oci-iot-mosquitto.service', 'quadlet/oci-iot-node-red.container');

const quadletReadme = await readText('quadlet/README.md');
for (const expected of [
  '~/.config/containers/systemd',
  '~/.config/oci-iot-node-red-gateway',
  'cp *.container *.network *.volume ~/.config/containers/systemd/',
  'systemctl --user daemon-reload',
  'systemctl --user reset-failed oci-iot-node-red.service',
  'systemctl --user start oci-iot-mosquitto.service oci-iot-node-red.service',
  'systemctl --user status oci-iot-mosquitto.service oci-iot-node-red.service',
  'journalctl --user -u oci-iot-node-red.service -f',
  'podman logs oci-iot-node-red',
  'podman logs -f oci-iot-node-red',
  'podman logs -f oci-iot-mosquitto',
  'journalctl CONTAINER_NAME=oci-iot-node-red -n 100 --no-pager',
  'journalctl CONTAINER_NAME=oci-iot-mosquitto -n 100 --no-pager',
  'A bare `journalctl --user` can be empty',
  'podman exec oci-iot-node-red getent hosts mosquitto',
  'systemctl --user stop oci-iot-node-red.service oci-iot-mosquitto.service',
]) {
  assertContains(quadletReadme, expected, 'quadlet/README.md');
}

const sampleReadme = await readText('README.md');
assertNotContains(sampleReadme, 'IOT_BASE_ENDPOINT', 'README.md');
assertNotContains(sampleReadme, 'export OCI_CLI_PROFILE', 'README.md');
for (const expected of [
  'use the OCI Console',
  'do not need to be exported',
  'one M5 model and one M5 adapter',
  'can extend the sample',
  'For simplicity',
  'Certificate-based gateway authentication',
  'cp .env.example .env',
  'docker compose up',
  'podman compose -f podman-compose.yaml up',
  'podman volume rm oci-iot-node-red-compose-data',
  'podman compose -f podman-compose.yaml exec node-red getent hosts mosquitto',
  'http://127.0.0.1:1880',
  'localhost by default',
  'Mosquitto port binding',
  'Node status badges',
  '![Node-RED Gateway tab](images/node-red-gateway.png)',
  '![Node-RED Simulators tab](images/node-red-simulators.png)',
]) {
  assertContains(sampleReadme, expected, 'README.md');
}

for (const expected of [
  'GATEWAY',
  'INDIRECT',
  'oci iot digital-twin-model create',
  'oci iot digital-twin-adapter create',
  'oci iot digital-twin-instance create',
  '--connectivity-type GATEWAY',
  '--connectivity-type INDIRECT',
  '--gateways',
  'invoke-raw-json-command',
  'docker compose up',
  'podman compose -f podman-compose.yaml up',
  'Quadlet',
  'devices/m5-01/telemetry',
  'm5/m5-01/cmd',
  'get-content',
]) {
  assertContains(sampleReadme, expected, 'README.md');
}

const rootReadme = await readFile(join(sampleDir, '../../../README.md'), 'utf8');
assertContains(rootReadme, 'Node-RED gateway', '../../../README.md');
assertContains(rootReadme, 'samples/node/node-red-gateway', '../../../README.md');
assertContains(rootReadme, 'local Node-RED gateway and Mosquitto broker', '../../../README.md');
assertContains(rootReadme, '`GATEWAY`', '../../../README.md');
assertContains(rootReadme, 'digital twin to `INDIRECT` devices', '../../../README.md');
assertContains(rootReadme, 'gateway metrics', '../../../README.md');

console.log('Node-RED gateway sample validation passed');
