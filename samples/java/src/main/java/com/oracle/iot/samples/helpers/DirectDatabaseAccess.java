/*
 * Helper for connecting directly to an OCI IoT Domain database.
 *
 * Copyright (c) 2026 Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at
 * https://oss.oracle.com/licenses/upl.
 *
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
 */

package com.oracle.iot.samples.helpers;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.sql.SQLException;
import java.util.Base64;

import javax.sql.DataSource;

import com.oracle.bmc.auth.AbstractAuthenticationDetailsProvider;
import com.oracle.bmc.identitydataplane.DataplaneClient;
import com.oracle.bmc.identitydataplane.model.GenerateScopedAccessTokenDetails;
import com.oracle.bmc.identitydataplane.requests.GenerateScopedAccessTokenRequest;
import com.oracle.bmc.iot.IotClient;
import com.oracle.bmc.iot.model.IotDomainGroup;
import com.oracle.bmc.iot.requests.GetIotDomainGroupRequest;
import com.oracle.bmc.iot.requests.GetIotDomainRequest;

import oracle.jdbc.AccessToken;
import oracle.jdbc.pool.OracleDataSource;

/**
 * Creates and holds a data source for direct database access to an OCI IoT Domain.
 */
public class DirectDatabaseAccess {
    private static final String KEY_PAIR_ALGORITHM = "RSA";
    private static final int KEY_SIZE = 2048;
    private static final KeyPair KEY_PAIR;
    
    static {
        try {
            var keyPairGenerator = KeyPairGenerator.getInstance(KEY_PAIR_ALGORITHM);
            
            keyPairGenerator.initialize(KEY_SIZE);
            
            KEY_PAIR = keyPairGenerator.generateKeyPair();
        } catch (NoSuchAlgorithmException e) {
            throw new Error(e.getMessage(), e);
        }
    }
    
    private final AbstractAuthenticationDetailsProvider authenticationDetailsProvider;
    
    private final DataSource dataSource;
    private final String domainShortId;
    
    /**
     * Creates a direct database access helper for the specified IoT Domain.
     *
     * @param authenticationDetailsProvider OCI authentication details provider used to call the OCI services
     * @param iotDomainOcid OCID of the IoT Domain to access
     * @throws SQLException if the Oracle data source cannot be configured
     */
    public DirectDatabaseAccess(
            AbstractAuthenticationDetailsProvider authenticationDetailsProvider,
            String iotDomainOcid) throws SQLException {
        this.authenticationDetailsProvider = authenticationDetailsProvider;
        
        try (var iotClient = IotClient.builder().build(authenticationDetailsProvider)) {
            var iotDomain = iotClient
                    .getIotDomain(GetIotDomainRequest.builder()
                        .iotDomainId(iotDomainOcid)
                        .build())
                    .getIotDomain();
            
            var iotDomainGroup = iotClient
                    .getIotDomainGroup(GetIotDomainGroupRequest.builder()
                            .iotDomainGroupId(iotDomain.getIotDomainGroupId())
                            .build())
                    .getIotDomainGroup();
            
            this.domainShortId = iotDomain.getDeviceHost().split("\\.")[0].toUpperCase();
            this.dataSource = createDataSource(iotDomainGroup);
        }
    }
    
    /**
     * Returns the configured Oracle JDBC data source.
     *
     * @return data source that connects to the IoT Domain database
     */
    public DataSource getDataSource() {
        return dataSource;
    }

    /**
     * Returns the IoT Domain short ID.
     *
     * @return upper-case IoT Domain short ID
     */
    public String getDomainShortId() {
        return domainShortId;
    }

    private DataSource createDataSource(IotDomainGroup iotDomainGroup) throws SQLException {
        var dataSource = new OracleDataSource();
        
        dataSource.setURL("jdbc:oracle:thin:@" + iotDomainGroup.getDbConnectionString());
        dataSource.setTokenSupplier(
                AccessToken.createJsonWebTokenCache(() -> createDatabaseAccessToken(iotDomainGroup.getDbTokenScope())));
        
        return dataSource;
    }

    private AccessToken createDatabaseAccessToken(String dbTokenScope) {
        try (var iddpClient = DataplaneClient.builder().build(authenticationDetailsProvider)) {
            return AccessToken.createJsonWebToken(
                    iddpClient
                        .generateScopedAccessToken(GenerateScopedAccessTokenRequest.builder()
                                .generateScopedAccessTokenDetails(GenerateScopedAccessTokenDetails.builder()
                                        .publicKey(Base64.getEncoder()
                                                .encodeToString(KEY_PAIR.getPublic().getEncoded()))
                                        .scope(dbTokenScope)
                                        .build())
                                .build())
                        .getSecurityToken()
                        .getToken().toCharArray(),
                    KEY_PAIR.getPrivate());
        }
    }
}
