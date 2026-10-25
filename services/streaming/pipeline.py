from pyflink.table import EnvironmentSettings, TableEnvironment

def run_pipeline():
    # 1. Initialize Table Environment
    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    t_env = TableEnvironment.create(settings)

    # 2. Define Kafka Source Table
    t_env.execute_sql("""
        CREATE TABLE kafka_orders (
            order_id BIGINT,
            customer_id BIGINT,
            external_order_reference STRING,
            order_status STRING,
            currency STRING,
            total_amount DECIMAL(12, 2),
            created_at TIMESTAMP(3),
            updated_at TIMESTAMP(3)
        ) WITH (
            'connector' = 'kafka',
            'topic' = 'aether.public.orders',
            'properties.bootstrap.servers' = 'kafka:19092',
            'properties.group.id' = 'aether-flink-consumer',
            'scan.startup.mode' = 'earliest-offset',
            'format' = 'debezium-json'
        )
    """)

    # 3. Define Iceberg Sink Table
    t_env.execute_sql("""
        CREATE TABLE iceberg_orders (
            order_id BIGINT,
            customer_id BIGINT,
            external_order_reference STRING,
            order_status STRING,
            currency STRING,
            total_amount DECIMAL(12, 2),
            created_at TIMESTAMP(3),
            updated_at TIMESTAMP(3),
            PRIMARY KEY (order_id) NOT ENFORCED
        ) WITH (
            'connector' = 'iceberg',
            'catalog-name' = 'aether_catalog',
            'catalog-type' = 'hadoop',
            'warehouse' = 's3://aether-lakehouse/warehouse'
        )
    """)

    # 4. Execute the streaming insert
    t_env.execute_sql("""
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
        FROM kafka_orders
    """).wait()

if __name__ == '__main__':
    run_pipeline()
