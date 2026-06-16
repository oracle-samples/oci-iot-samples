/*
 * Helper for managing a queue subscription.
 *
 * Copyright (c) 2026 Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at
 * https://oss.oracle.com/licenses/upl.
 *
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
 */

package com.oracle.iot.samples.helpers;

import java.sql.Connection;
import java.sql.SQLException;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import java.util.stream.Stream;

import oracle.jdbc.aq.AQDequeueOptions;
import oracle.jdbc.aq.AQMessage;
import oracle.jdbc.driver.OracleConnection;

/**
 * Manages a queue subscriber and streams messages from an IoT Domain queue.
 */
public class QueueSubscription {
    private static final Duration DEQUEUE_WAIT_TIME = Duration.ofSeconds(5);
    private static final int DEQUEUE_BUFFER_SIZE = 10;

    private static final int ORA_DEQUEUE_TIMEOUT = 25228;
    private static final int ORA_SUBSCRIBER_EXISTS = 24034;

    private final String schema;
    private final String queue;
    private final String subscriber;

    private final AtomicReference<Thread> streamingThread = new AtomicReference<>();

    /**
     * Creates a queue subscription helper.
     *
     * @param schema database schema that owns the queue
     * @param queue queue name
     * @param subscriber subscriber name
     */
    public QueueSubscription(String schema, String queue, String subscriber) {
        this.schema = schema.toUpperCase();
        this.queue = queue.toUpperCase();
        this.subscriber = subscriber.toUpperCase();
    }

    /**
     * Registers the subscriber for the underlying queue.
     *
     * @param connection Oracle JDBC connection used to register the subscriber
     * @param rule optional queue rule expression, or {@code null} to receive all messages visible to the subscriber
     * @return {@code true} when a new subscriber is registered, or {@code false} when the subscriber already exists
     * @throws SQLException if subscriber registration fails
     */
    public boolean registerSubscriber(Connection connection, String rule) throws SQLException {
        try {
            ((OracleConnection) connection).addDurableAQSubscriber(fullyQualifiedQueueName(), subscriber, rule);

            return true;
        } catch (SQLException ex) {
            if (ex.getErrorCode() == ORA_SUBSCRIBER_EXISTS) {
                return false;
            } else {
                throw ex;
            }
        }
    }

    /**
     * Removes the subscriber from the underlying queue.
     *
     * @param connection Oracle JDBC connection used to remove the subscriber
     * @throws SQLException if subscriber removal fails
     */
    public void unregisterSubscriber(Connection connection) throws SQLException {
        ((OracleConnection) connection).removeDurableAQSubscriber(fullyQualifiedQueueName(), subscriber);
    }

    /**
     * Starts streaming messages in the background.
     *
     * @param connection Oracle JDBC connection used to dequeue messages
     * @param queueType queue payload type name used by the JDBC dequeue API
     * @param onMessage handler invoked for each dequeued message
     * @throws IllegalStateException if streaming has already started
     */
    public void startStreaming(Connection connection, String queueType, Consumer<AQMessage> onMessage) {
        var newStreamingThread = Thread.ofVirtual()
                .name("queue-streaming-thread (%s.%s)".formatted(schema, queue))
                .unstarted(() -> streamQueue((OracleConnection) connection, queueType, onMessage));

        if (!streamingThread.compareAndSet(null, newStreamingThread)) {
            throw new IllegalStateException("Streaming has already started");
        }

        newStreamingThread.start();
    }

    /**
     * Stops streaming if it was started and waits for the streaming thread to finish.
     */
    public void stopStreaming() {
        var startedStreamingThread = streamingThread.getAndSet(null);

        if (startedStreamingThread != null) {
            while (startedStreamingThread.isAlive()) {
                try {
                    startedStreamingThread.join();
                } catch (InterruptedException ignored) {}
            }
        }
    }

    private void streamQueue(OracleConnection connection, String queueType, Consumer<AQMessage> onMessage) {
        while (Thread.currentThread() == streamingThread.get()) {
            try {
                var dequeued = connection.dequeue(
                        fullyQualifiedQueueName(),
                        dequeueOptions(),
                        queueType,
                        DEQUEUE_BUFFER_SIZE);

                if (dequeued != null) {
                    Stream.of(dequeued).forEach(onMessage);

                    connection.commit();
                }
            } catch (SQLException ex) {
                if (ex.getErrorCode() != ORA_DEQUEUE_TIMEOUT) {
                    System.err.println("Dequeue error: " + ex.getMessage());
                    ex.printStackTrace(System.err);
                }
            }
        }
    }

    private AQDequeueOptions dequeueOptions() throws SQLException {
        var dequeueOptions = new AQDequeueOptions();

        dequeueOptions.setVisibility(AQDequeueOptions.VisibilityOption.ON_COMMIT);
        dequeueOptions.setConsumerName(subscriber);
        dequeueOptions.setWait((int) DEQUEUE_WAIT_TIME.toSeconds());
        dequeueOptions.setDequeueMode(AQDequeueOptions.DequeueMode.REMOVE);

        return dequeueOptions;
    }

    private String fullyQualifiedQueueName() {
        return schema + "." + queue;
    }
}
