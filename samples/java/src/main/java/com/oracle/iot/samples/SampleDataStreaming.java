/*
 * Sample client application that streams raw and normalized data consumed by the OCI IoT platform in real time.
 *
 * Copyright (c) 2026 Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at
 * https://oss.oracle.com/licenses/upl.
 *
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
 */

package com.oracle.iot.samples;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.sql.Blob;
import java.sql.SQLException;

import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.iot.samples.helpers.DirectDatabaseAccess;
import com.oracle.iot.samples.helpers.QueueSubscription;

import oracle.jdbc.aq.AQMessage;
import oracle.sql.json.OracleJsonObject;

/**
 * Demonstrates how to stream IoT data from an OCI IoT Domain by subscribing to
 * the domain's raw and normalized queues.
 *
 * <p>Command-line arguments:</p>
 * <ol>
 *     <li>IoT Domain OCID - required.</li>
 *     <li>Digital Twin Instance OCID - optional. When provided, both raw and normalized queues are filtered to include
 *         only messages for that digital twin instance.</li>
 * </ol>
 */
public class SampleDataStreaming {
    public static void main(String[] args) throws SQLException {
        if (args.length < 1 || args.length > 2) {
            System.err.println("Expected arguments: <iot-domain-ocid> [digital-twin-instance-ocid]");
            
            return;
        }
        
        // The first command-line argument is the IoT Domain OCID.
        var iotDomainOcid = args[0];
        // The optional second command-line argument limits streaming to one Digital Twin Instance.
        var digitalTwinInstanceOcid = args.length > 1 ? args[1] : null;
        // This sample uses instance principal authentication by default. With this authentication flow, run the sample
        // in OCI and configure the required dynamic group, policies, IoT Domain Group, and IoT Domain.
        // Replace this provider if your deployment uses another authentication flow.
        var authenticationDetailsProvider = InstancePrincipalsAuthenticationDetailsProvider.builder().build();
        
        var dbAccess = new DirectDatabaseAccess(authenticationDetailsProvider, iotDomainOcid);
        var schema = "%s__IOT".formatted(dbAccess.getDomainShortId());
        var rawDataQueueSubscription = new QueueSubscription(
                schema,
                "RAW_DATA_IN",
                "SAMPLE_RAW_DATA_SUBSCRIBER");
        var normalizedDataQueueSubscription = new QueueSubscription(
                schema,
                "NORMALIZED_DATA",
                "SAMPLE_NORMALIZED_DATA_SUBSCRIBER");
        
        try (
                var rawDataConnection = dbAccess.getDataSource().getConnection();
                var normalizedDataConnection = dbAccess.getDataSource().getConnection()) {
            var unregisterRawSubscriber = false;
            var unregisterNormalizedSubscriber = false;
            
            try {
                rawDataConnection.setAutoCommit(false);
                normalizedDataConnection.setAutoCommit(false);
                
                System.out.println("Registering raw data subscriber");
                
                if (rawDataQueueSubscription.registerSubscriber(
                        rawDataConnection,
                        digitalTwinInstanceOcid == null
                                ? null
                                : "tab.user_data.DIGITAL_TWIN_INSTANCE_ID = '%s'".formatted(digitalTwinInstanceOcid))) {
                    rawDataConnection.commit();
                    
                    System.out.println("Raw data subscriber is registered");
                    
                    unregisterRawSubscriber = true;
                } else {
                    System.out.println("Pre-registered raw data subscriber is found");
                }
                
                System.out.println("Registering normalized data subscriber");
                
                if (normalizedDataQueueSubscription.registerSubscriber(
                        normalizedDataConnection,
                        digitalTwinInstanceOcid == null
                                ? null
                                : "tab.user_data.digitalTwinInstanceId = '%s'".formatted(digitalTwinInstanceOcid))) {
                    normalizedDataConnection.commit();
                    
                    System.out.println("Normalized data subscriber is registered");
                    
                    unregisterNormalizedSubscriber = true;
                } else {
                    System.out.println("Pre-registered normalized data subscriber is found");
                }
                
                System.out.println("Starting streaming");
                
                rawDataQueueSubscription.startStreaming(
                        rawDataConnection,
                        schema + ".RAW_DATA_IN_TYPE",
                        SampleDataStreaming::onRawMessage);
                
                normalizedDataQueueSubscription.startStreaming(
                        normalizedDataConnection,
                        "JSON",
                        SampleDataStreaming::onNormalizedMessage);
                
                System.out.println("Press <Enter> to exit");
                
                try {
                    System.in.read();
                } catch (IOException ignored) {}
            } finally {
                System.out.println("Stopping streaming");
                
                try {
                    rawDataQueueSubscription.stopStreaming();
                } finally {
                    normalizedDataQueueSubscription.stopStreaming();
                }
                
                System.out.println("Streaming is stopped");
                
                try {
                    if (unregisterRawSubscriber) {
                        System.out.println("Unregistering raw data subscriber");
                        
                        rawDataQueueSubscription.unregisterSubscriber(rawDataConnection);
                        rawDataConnection.commit();
                        
                        System.out.println("Raw data subscriber is unregistered");
                    }
                } finally {
                    if (unregisterNormalizedSubscriber) {
                        System.out.println("Unregistering normalized data subscriber");
                        
                        normalizedDataQueueSubscription.unregisterSubscriber(normalizedDataConnection);
                        normalizedDataConnection.commit();
                        
                        System.out.println("Normalized data subscriber is unregistered");
                    }
                }
            }
        }
    }
    
    private static void onNormalizedMessage(AQMessage message) {
        try {
            var output = new StringBuilder("Normalized Data:");
            var messageObject = (OracleJsonObject) message.getJSONPayload().toJdbc();
            
            output.append("\n  digitalTwinInstanceId: ").append(messageObject.getString("digitalTwinInstanceId"));
            output.append("\n  contentPath: ").append(messageObject.getString("contentPath"));
            output.append("\n  value: ").append(messageObject.get("value"));
            output.append("\n  timeObserved: ").append(messageObject.getString("timeObserved"));
            
            System.out.println(output.toString());
        } catch (SQLException ex) {
            System.err.println("Invalid normalized message payload: " + ex.getMessage());
            ex.printStackTrace(System.err);
        }
    }
    
    private static void onRawMessage(AQMessage message) {
        try {
            var output = new StringBuilder("Raw Data:");
            var attributes = message.getStructPayload().getAttributes();
            
            output.append("\n  DIGITAL_TWIN_INSTANCE_ID: ").append(attributes[0]);
            output.append("\n  ENDPOINT: ").append(attributes[1]);
            
            var content = (Blob) attributes[2];
            
            try {
                output
                    .append("\n  CONTENT: ")
                    .append(formatRawDataContent(content.getBytes(1, (int) content.length())));
            } finally {
                try {
                    content.free();
                } catch (Exception ignored) {}
            }
            
            output.append("\n  CONTENT_TYPE: ").append(attributes[3]);
            output.append("\n  TIME_RECEIVED: ").append(attributes[4]);
            
            System.out.println(output.toString());
        } catch (Exception ex) {
            System.err.println("Invalid raw message payload: " + ex.getMessage());
            ex.printStackTrace(System.err);
        }
    }
    
    private static String formatRawDataContent(byte[] contentBytes) {
        var binaryContentDescription = "<binary (%d bytes)>".formatted(contentBytes.length);

        try {
            var content = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(contentBytes))
                    .toString();

            return isPrintable(content) ? content : binaryContentDescription;
        } catch (CharacterCodingException ex) {
            return binaryContentDescription;
        }
    }

    private static boolean isPrintable(String content) {
        return content.codePoints().allMatch(codePoint -> !Character.isISOControl(codePoint)
                || codePoint == '\n'
                || codePoint == '\r'
                || codePoint == '\t');
    }
}
