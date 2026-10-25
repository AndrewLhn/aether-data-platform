-- 1. Create Kafka Source Table
CREATE TABLE kafka_orders (
    order_id BIGINT,
    customer_id BIGINT,
    external_order_reference STRING,
    order_status STRING,
    currency STRING,
    total_amount DECIMAL(12, 2),
    created_at TIMESTAMP(3),
    updated_at TIMESTAMP(3),
    event_time AS PROCTIME() 
) WITH (
    'connector' = 'kafka',
    'topic' = 'aether.public.orders',
    'properties.bootstrap.servers' = 'kafka:19092',
    'properties.group.id' = 'aether-flink-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'debezium-json'
);

-- 2. Create Iceberg Sink Table
CREATE TABLE iceberg_orders (
    order_id BIGINT,
    customer_id BIGINT,
    external_order_reference STRING,
    order_status STRING,
    currency STRING,
    total_amount DECIMAL(12, 2),
    created_at TIMESTAMP(3),
    updated_at TIMESTAMP(3),
    PRIMARY KEY (order_id)
) WITH (
    'connector' = 'iceberg',
    'catalog-name' = 'aether_catalog',
    'catalog-type' = 'hadoop',
    'warehouse' = 's3://aether-lakehouse/warehouse'
);

-- 3. Start Streaming Pipeline
INSERT INTO iceberg_orders
SELECT 
    order_id, 
    customer_id, 
    external_order_reference, 
    order_status, 
    currency, 
    total_amount, 
    created_at, 
    updated_at 
FROM kafka_orders;
