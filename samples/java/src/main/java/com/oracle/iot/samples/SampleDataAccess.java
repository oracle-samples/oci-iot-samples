/*
 * Sample client application that queries raw data consumed by the OCI IoT platform directly.
 *
 * Copyright (c) 2026 Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at
 * https://oss.oracle.com/licenses/upl.
 *
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
 */

package com.oracle.iot.samples;

import java.io.IOException;
import java.sql.SQLException;

import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.iot.samples.helpers.DirectDatabaseAccess;

/**
 * Demonstrates how to access data directly in an OCI IoT Domain by connecting to
 * the domain database and querying the raw data table.
 *
 * <p>Command-line arguments:</p>
 * <ol>
 *     <li>IoT Domain OCID - required.</li>
 * </ol>
 */
public class SampleDataAccess {
    public static void main(String[] args) throws SQLException, IOException {
        if (args.length != 1) {
            System.err.println("Expected arguments: <iot-domain-ocid>");

            return;
        }

        // The first command-line argument is the IoT Domain OCID.
        var iotDomainOcid = args[0];
        // This sample uses instance principal authentication by default. With this authentication flow, run the sample
        // in OCI and configure the required dynamic group, policies, IoT Domain Group, and IoT Domain.
        // Replace this provider if your deployment uses another authentication flow.
        var authenticationDetailsProvider = InstancePrincipalsAuthenticationDetailsProvider.builder().build();

        var dbAccess = new DirectDatabaseAccess(authenticationDetailsProvider, iotDomainOcid);

        try (var connection = dbAccess.getDataSource().getConnection()) {
            try (var statement = connection
                    .prepareStatement("SELECT COUNT(*) FROM %s__IOT.RAW_DATA".formatted(dbAccess.getDomainShortId()))) {
                try (var resultSet = statement.executeQuery()) {
                    if (resultSet.next()) {
                        System.out.println("Raw data records count: %d".formatted(resultSet.getInt(1)));
                    }
                }
            }
        }
    }
}
