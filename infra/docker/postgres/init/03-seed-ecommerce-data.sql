INSERT INTO public.customers (customer_id, email, full_name, customer_status)
VALUES
  (1, 'olivia.martin@example.test', 'Olivia Martin', 'active'),
  (2, 'liam.chen@example.test', 'Liam Chen', 'active');

INSERT INTO public.orders (
  order_id,
  customer_id,
  external_order_reference,
  order_status,
  currency,
  total_amount
)
VALUES
  (1001, 1, 'seed-order-1001', 'paid', 'USD', 129.90),
  (1002, 2, 'seed-order-1002', 'created', 'EUR', 49.50);

INSERT INTO public.payments (
  payment_id,
  order_id,
  provider,
  provider_payment_reference,
  payment_status,
  amount,
  currency
)
VALUES
  (5001, 1001, 'stripe', 'seed-payment-5001', 'captured', 129.90, 'USD');

INSERT INTO public.inventory (
  sku,
  product_name,
  available_quantity,
  reserved_quantity
)
VALUES
  ('SKU-CHAIR-01', 'Ergonomic Chair', 24, 2),
  ('SKU-LAMP-02', 'Desk Lamp', 80, 5);

SELECT setval(pg_get_serial_sequence('public.customers', 'customer_id'), 2, true);
SELECT setval(pg_get_serial_sequence('public.orders', 'order_id'), 1002, true);
SELECT setval(pg_get_serial_sequence('public.payments', 'payment_id'), 5001, true);
