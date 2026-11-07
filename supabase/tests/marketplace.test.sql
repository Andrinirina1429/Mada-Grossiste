create extension if not exists pgtap with schema extensions;

begin;
set local search_path = extensions, public;

select no_plan();

select has_table('public', 'categories');
select has_table('public', 'profiles');
select has_table('public', 'seller_applications');
select has_table('public', 'products');
select has_table('public', 'product_price_tiers');
select has_table('public', 'carts');
select has_table('public', 'cart_items');
select has_table('public', 'buyer_favorites');
select has_table('public', 'shipping_addresses');
select has_table('public', 'orders');
select has_table('public', 'order_items');
select has_table('public', 'order_status_history');
select has_table('public', 'admin_activity_log');
select has_table('public', 'quote_requests');
select has_table('public', 'marketplace_messages');
select has_table('public', 'marketplace_notifications');
select has_table('public', 'seller_delivery_zones');
select has_table('public', 'product_media');
select has_table('public', 'marketplace_promotions');

select has_column('public', 'products', 'seller_id');
select has_column('public', 'products', 'category_id');
select has_column('public', 'products', 'image_path');
select has_column('public', 'profiles', 'seller_status');
select has_column('public', 'orders', 'buyer_id');
select has_column('public', 'order_items', 'order_id');
select has_column('public', 'products', 'moderation_status');

select ok(
  has_column('public', 'categories', 'active')
  and has_column('public', 'categories', 'slug')
  and has_column('public', 'profiles', 'requested_role')
  and has_column('public', 'profiles', 'public_phone_consent')
  and has_column('public', 'profiles', 'seller_rejection_reason'),
  'Category and profile columns match the application queries'
);
select ok(
  has_column('public', 'seller_applications', 'admin_note')
  and has_column('public', 'seller_applications', 'public_phone_consent')
  and has_column('public', 'seller_applications', 'status')
  and has_column('public', 'products', 'wholesale_price')
  and has_column('public', 'products', 'selling_mode')
  and has_column('public', 'products', 'min_wholesale_qty')
  and has_column('public', 'products', 'seller_phone')
  and has_column('public', 'products', 'is_active'),
  'Seller applications and product columns match the application queries'
);
select ok(
  has_column('public', 'carts', 'buyer_id')
  and has_column('public', 'carts', 'status')
  and has_column('public', 'cart_items', 'quantity')
  and has_column('public', 'buyer_favorites', 'product_id')
  and has_column('public', 'shipping_addresses', 'recipient_name'),
  'Cart, favorite, and address columns match the application queries'
);
select ok(
  has_column('public', 'orders', 'order_number')
  and has_column('public', 'orders', 'delivery')
  and has_column('public', 'orders', 'total')
  and has_column('public', 'order_items', 'seller_id')
  and has_column('public', 'order_items', 'unit_price')
  and has_column('public', 'marketplace_messages', 'receiver_id')
  and has_column('public', 'marketplace_messages', 'message'),
  'Order and message columns match the application queries'
);
select ok(
  has_column('public', 'marketplace_notifications', 'is_read')
  and has_column('public', 'seller_delivery_zones', 'delivery_fee')
  and has_column('public', 'product_media', 'storage_path')
  and has_column('public', 'marketplace_promotions', 'discount_percent')
  and has_column('public', 'marketplace_promotions', 'ends_at'),
  'Notification, delivery, media, and promotion columns match the application queries'
);

select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.products'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass)
  and exists (select 1 from pg_constraint where conrelid = 'public.products'::regclass and contype = 'f' and confrelid = 'public.categories'::regclass),
  'Products reference seller profiles and categories'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.product_price_tiers'::regclass and contype = 'f' and confrelid = 'public.products'::regclass)
  and exists (select 1 from pg_constraint where conrelid = 'public.quote_requests'::regclass and contype = 'f' and confrelid = 'public.products'::regclass)
  and exists (select 1 from pg_constraint where conrelid = 'public.quote_requests'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass),
  'Price tiers and quotes reference their product and participants'
);
select ok(
  has_column('public', 'order_items', 'quote_id')
  and has_column('public', 'quote_requests', 'proposed_unit_price')
  and has_column('public', 'quote_requests', 'status'),
  'Orders retain the quote reference and negotiated response'
);
select ok(
  has_column('public', 'product_price_tiers', 'quantity_min')
  and has_column('public', 'product_price_tiers', 'unit_price')
  and has_column('public', 'products', 'selling_mode'),
  'Products store sale mode and quantity-based unit prices'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.cart_items'::regclass and contype = 'f' and confrelid = 'public.carts'::regclass)
  and exists (select 1 from pg_constraint where conrelid = 'public.cart_items'::regclass and contype = 'f' and confrelid = 'public.products'::regclass),
  'Cart items reference carts and products'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.orders'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass)
  and exists (select 1 from pg_constraint where conrelid = 'public.order_items'::regclass and contype = 'f' and confrelid = 'public.orders'::regclass),
  'Orders and order items have their buyer/order relationships'
);
select ok(
  not exists (
    select 1
    from (values
      ('public.profiles', 'auth.users'),
      ('public.seller_applications', 'public.profiles'),
      ('public.products', 'public.profiles'),
      ('public.products', 'public.categories'),
      ('public.carts', 'public.profiles'),
      ('public.cart_items', 'public.carts'),
      ('public.cart_items', 'public.products'),
      ('public.buyer_favorites', 'public.profiles'),
      ('public.buyer_favorites', 'public.products'),
      ('public.shipping_addresses', 'public.profiles'),
      ('public.orders', 'public.profiles'),
      ('public.order_items', 'public.orders'),
      ('public.order_items', 'public.products'),
      ('public.order_items', 'public.profiles'),
      ('public.marketplace_messages', 'public.profiles'),
      ('public.marketplace_messages', 'public.products'),
      ('public.marketplace_notifications', 'public.profiles'),
      ('public.seller_delivery_zones', 'public.profiles'),
      ('public.product_media', 'public.products'),
      ('public.product_media', 'public.profiles'),
      ('public.marketplace_promotions', 'public.profiles')
    ) as expected(child_table, parent_table)
    where not exists (
      select 1 from pg_constraint c
      where c.contype = 'f'
        and c.conrelid = to_regclass(expected.child_table)
        and c.confrelid = to_regclass(expected.parent_table)
    )
  ),
  'All expected foreign-key relationships exist'
);
select ok(
  (select count(*) = 2 from pg_constraint
   where conrelid = 'public.marketplace_messages'::regclass
     and contype = 'f' and confrelid = 'public.profiles'::regclass),
  'Messages independently reference both sender and receiver profiles'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.products'::regclass),
  'Products have row-level security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.orders'::regclass),
  'Orders have row-level security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.order_status_history'::regclass)
  and exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'order_status_history'
      and policyname = 'order_status_history_participant_read'
  ),
  'Order status history is restricted to order participants'
);
select ok(
  exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'products' and policyname = 'products_public_or_owner_read'),
  'Products have a public-active and owner read policy'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.product_price_tiers'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.quote_requests'::regclass)
  and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'product_price_tiers' and policyname = 'product_price_tiers_public_read')
  and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'quote_requests' and policyname = 'quote_requests_participant_read'),
  'Price tiers are visible with their product and quote records are participant-only'
);
select ok(
  exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'products' and policyname = 'products_approved_seller_insert'),
  'Only approved sellers can insert products'
);
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE'),
  'Authenticated users cannot change their own profile role'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%trunc(price)%'
  )
  and exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%trunc(wholesale_price)%'
  ),
  'Stored prices are whole ariary values, matching displayed prices'
);
select ok(
  has_column_privilege('authenticated', 'public.marketplace_notifications', 'is_read', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.marketplace_notifications', 'message', 'UPDATE'),
  'Users can mark notifications read but cannot rewrite their content'
);
select ok(
  not has_table_privilege('anon', 'public.products', 'INSERT'),
  'Anonymous users cannot insert products'
);
select ok(
  not has_table_privilege('authenticated', 'public.orders', 'INSERT')
  and not has_table_privilege('authenticated', 'public.order_items', 'INSERT')
  and not has_table_privilege('authenticated', 'public.orders', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_items', 'UPDATE'),
  'Orders, line items and historical prices cannot be directly changed'
);
select ok(
  has_table_privilege('authenticated', 'public.order_status_history', 'SELECT')
  and not has_table_privilege('authenticated', 'public.order_status_history', 'INSERT')
  and not has_table_privilege('authenticated', 'public.order_status_history', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_status_history', 'DELETE'),
  'Status history is read-only for authenticated participants'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'products'
      and policyname = 'products_owner_update'
      and qual ilike '%seller_id%'
      and with_check ilike '%seller_id%'
      and with_check ilike '%approved%'
  ),
  'Product updates require the authenticated seller identity and approval'
);

select ok(
  to_regprocedure('public.mg_is_admin()') is not null,
  'Admin role-check RPC exists'
);
select ok(
  to_regprocedure('public.mg_admin_dashboard_stats()') is not null
  and to_regprocedure('public.mg_admin_set_seller_status(uuid,text,text)') is not null
  and to_regprocedure('public.mg_admin_moderate_product(uuid,text,text)') is not null
  and to_regprocedure('public.mg_submit_product_for_review(uuid)') is not null,
  'Protected admin dashboard, seller management, and product moderation RPCs exist'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.admin_activity_log'::regclass)
  and exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'admin_activity_log'
      and policyname = 'admin_activity_log_admin_read'
  )
  and has_table_privilege('authenticated', 'public.admin_activity_log', 'SELECT')
  and not has_table_privilege('authenticated', 'public.admin_activity_log', 'INSERT'),
  'Admin activity history is readable by administrators and not directly writable'
);
select ok(
  not has_column_privilege('authenticated', 'public.products', 'moderation_status', 'UPDATE')
  and exists (
    select 1 from pg_trigger
    where tgrelid = 'public.products'::regclass
      and tgname = 'marketplace_product_activation_guard'
      and not tgisinternal
  ),
  'Sellers cannot change moderation state and unapproved products cannot be activated'
);
select ok(
  has_function_privilege('authenticated', 'public.mg_admin_dashboard_stats()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mg_admin_dashboard_stats()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mg_admin_moderate_product(uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mg_admin_moderate_product(uuid,text,text)', 'EXECUTE'),
  'Admin RPCs are authenticated-only and enforce administrator authorization internally'
);
select ok(
  to_regprocedure('public.mg_review_seller(uuid,text,text)') is not null,
  'Seller review RPC exists'
);
select ok(
  to_regprocedure('public.mg_apply_as_seller(text,text,text,text,text)') is not null,
  'Existing buyers can submit a protected seller application'
);
select ok(
  to_regprocedure('public.mg_set_public_phone_consent(boolean)') is not null
  and has_function_privilege('authenticated', 'public.mg_set_public_phone_consent(boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mg_set_public_phone_consent(boolean)', 'EXECUTE'),
  'Only authenticated users can change their seller phone visibility preference'
);
select ok(
  position('auth.uid()' in pg_get_functiondef('public.mg_set_public_phone_consent(boolean)'::regprocedure)) > 0
  and position('seller_status' in pg_get_functiondef('public.mg_set_public_phone_consent(boolean)'::regprocedure)) > 0,
  'Phone visibility RPC is scoped to the caller and eligible seller states'
);
select ok(
  position('public_phone_consent' in pg_get_functiondef('public.sync_product_seller_details()'::regprocedure)) > 0
  and position('public_phone_consent' in pg_get_functiondef('public.sync_marketplace_products_from_profile()'::regprocedure)) > 0,
  'Public product phone fields are derived from the seller consent setting'
);
select ok(
  position('raw_user_meta_data ->> ''public_phone_consent''' in pg_get_functiondef('public.handle_new_marketplace_user()'::regprocedure)) = 0
  and position('false' in pg_get_functiondef('public.handle_new_marketplace_user()'::regprocedure)) > 0,
  'New accounts start with phone visibility disabled instead of trusting signup metadata'
);
select ok(
  to_regprocedure('public.mg_place_order(text,text,text,text,text,jsonb)') is not null,
  'Atomic order-placement RPC exists'
);
select ok(
  to_regprocedure('public.mg_save_product_price_tiers(uuid,jsonb)') is not null
  and to_regprocedure('public.mg_save_product_pricing(uuid,numeric,numeric,integer,text,jsonb)') is not null
  and to_regprocedure('public.mg_create_quote_request(uuid,integer,text)') is not null
  and to_regprocedure('public.mg_respond_to_quote(uuid,text,numeric,text)') is not null
  and to_regprocedure('public.mg_decline_quote(uuid)') is not null,
  'Seller tier management and buyer/seller quote decision RPCs exist'
);
select ok(
  to_regprocedure('public.mg_update_order_status(uuid,text)') is not null,
  'Order status RPC exists'
);
select ok(
  to_regprocedure('public.mg_seller_dashboard_stats()') is not null
  and has_function_privilege('authenticated', 'public.mg_seller_dashboard_stats()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mg_seller_dashboard_stats()', 'EXECUTE'),
  'Seller dashboard aggregates are provided by a protected authenticated RPC'
);
select ok(
  to_regprocedure('public.record_order_status_history()') is not null
  and exists (
    select 1 from pg_trigger
    where tgrelid = 'public.orders'::regclass
      and tgname = 'marketplace_order_status_history'
      and not tgisinternal
  ),
  'Order creation and status updates are captured by the history trigger'
);
select ok(
  to_regprocedure('public.mg_is_order_seller(uuid)') is not null
  and to_regprocedure('public.mg_is_order_buyer(uuid)') is not null,
  'Order visibility helpers avoid recursive RLS checks'
);
select ok(
  has_function_privilege('anon', 'public.is_marketplace_admin()', 'EXECUTE'),
  'Anonymous product policies can safely evaluate the admin predicate'
);
select ok(
  not has_function_privilege('anon', 'public.mg_place_order(text,text,text,text,text,jsonb)', 'EXECUTE'),
  'Anonymous users cannot execute order-placement RPC'
);
select ok(
  has_function_privilege('authenticated', 'public.mg_apply_as_seller(text,text,text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mg_apply_as_seller(text,text,text,text,text)', 'EXECUTE'),
  'Seller applications are restricted to authenticated accounts'
);
select ok(
  not has_table_privilege('authenticated', 'public.seller_applications', 'INSERT')
  and not has_table_privilege('authenticated', 'public.seller_applications', 'UPDATE'),
  'Seller application records can only be changed through protected RPCs'
);
select ok(
  position('auth.uid()' in pg_get_functiondef('public.mg_place_order(text,text,text,text,text,jsonb)'::regprocedure)) > 0
  and position('product_price_tiers' in pg_get_functiondef('public.mg_place_order(text,text,text,text,text,jsonb)'::regprocedure)) > 0
  and position('proposed_unit_price' in pg_get_functiondef('public.mg_place_order(text,text,text,text,text,jsonb)'::regprocedure)) > 0
  and position('p_items' in pg_get_functiondef('public.mg_place_order(text,text,text,text,text,jsonb)'::regprocedure)) > 0,
  'Order RPC derives buyer identity and classic, tiered, or accepted quote prices on the server'
);
select ok(
  not has_table_privilege('authenticated', 'public.quote_requests', 'INSERT')
  and not has_table_privilege('authenticated', 'public.quote_requests', 'UPDATE')
  and has_function_privilege('authenticated', 'public.mg_create_quote_request(uuid,integer,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mg_respond_to_quote(uuid,text,numeric,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mg_decline_quote(uuid)', 'EXECUTE'),
  'Quote changes are restricted to authenticated RPCs'
);
select ok(
  not has_table_privilege('authenticated', 'public.product_price_tiers', 'INSERT')
  and not has_table_privilege('authenticated', 'public.product_price_tiers', 'UPDATE')
  and has_function_privilege('authenticated', 'public.mg_save_product_price_tiers(uuid,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mg_save_product_pricing(uuid,numeric,numeric,integer,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mg_save_product_price_tiers(uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mg_save_product_pricing(uuid,numeric,numeric,integer,text,jsonb)', 'EXECUTE'),
  'Only authenticated protected RPCs can change seller price tiers'
);
select ok(
  not has_column_privilege('authenticated', 'public.products', 'price', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.products', 'wholesale_price', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.products', 'min_wholesale_qty', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.products', 'selling_mode', 'UPDATE')
  and has_column_privilege('authenticated', 'public.products', 'name', 'UPDATE'),
  'Product price fields are writable only through the protected pricing RPC'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.mg_review_seller(uuid,text,text)'::regprocedure),
  'Seller review RPC runs with protected definer privileges'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.mg_place_order('Acheteur', '+261341234567', 'Antananarivo', '', '', '[{"product_id":"00000000-0000-0000-0000-000000000002","quantity":1.5}]'::jsonb)$$,
  'P0001',
  'Each order line must contain a product UUID and a positive integer quantity',
  'Order RPC rejects fractional quantities before creating an order'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('90000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'hybrid-buyer@example.test', '', now(), '{}', '{}', now(), now()),
  ('90000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'hybrid-other-buyer@example.test', '', now(), '{}', '{}', now(), now()),
  ('90000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'hybrid-seller@example.test', '', now(), '{}', '{}', now(), now()),
  ('90000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'hybrid-other-seller@example.test', '', now(), '{}', '{}', now(), now());

update public.profiles
set role = 'seller', requested_role = 'seller', seller_status = 'approved'
where id in (
  '90000000-0000-0000-0000-000000000201',
  '90000000-0000-0000-0000-000000000202'
);

insert into public.products (
  id, seller_id, category_id, name, price, wholesale_price,
  min_wholesale_qty, selling_mode, stock, is_active, moderation_status
)
select '90000000-0000-0000-0000-000000000301',
  '90000000-0000-0000-0000-000000000201', c.id,
  'Hybrid test product', 10000, 7000, 5, 'both', 50, true, 'approved'
from public.categories c
where c.active
order by c.name
limit 1;

insert into public.products (
  id, seller_id, category_id, name, price, wholesale_price,
  min_wholesale_qty, selling_mode, stock, is_active, moderation_status
)
select '90000000-0000-0000-0000-000000000302',
  '90000000-0000-0000-0000-000000000201', c.id,
  'Wholesale test product', 10000, 7000, 5, 'wholesale', 5, true, 'approved'
from public.categories c
where c.active
order by c.name
limit 1;

insert into public.products (
  id, seller_id, category_id, name, price, min_wholesale_qty,
  selling_mode, stock, is_active
)
select '90000000-0000-0000-0000-000000000303',
  '90000000-0000-0000-0000-000000000201', c.id,
  'Out of stock test product', 1000, 1, 'classic', 0, false
from public.categories c
where c.active
order by c.name
limit 1;

create temporary table marketplace_test_quote_ids (
  quote_no integer generated always as identity,
  quote_id uuid not null
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000201', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.mg_save_product_price_tiers(
    '90000000-0000-0000-0000-000000000301',
    '[{"quantity_min":10,"unit_price":6000},{"quantity_min":20,"unit_price":6500}]'::jsonb
  )$$,
  'P0001',
  'Each higher-quantity tier must have a lower unit price',
  'Seller cannot save a higher unit price at a larger quantity'
);
select lives_ok(
  $$select public.mg_save_product_price_tiers(
    '90000000-0000-0000-0000-000000000301',
    '[{"quantity_min":10,"unit_price":6000},{"quantity_min":20,"unit_price":5000}]'::jsonb
  )$$,
  'Seller can save descending wholesale price tiers'
);
select lives_ok(
  $$select public.mg_save_product_pricing(
    '90000000-0000-0000-0000-000000000301',
    9500,
    6800,
    8,
    'both',
    '[{"quantity_min":10,"unit_price":6000},{"quantity_min":20,"unit_price":5000}]'::jsonb
  )$$,
  'Seller can atomically replace base prices, minimum, mode, and tiers'
);
select is(
  (select price from public.products where id = '90000000-0000-0000-0000-000000000301'),
  9500::numeric,
  'Pricing RPC updates the classic base price'
);
select is(
  (select min_wholesale_qty from public.products where id = '90000000-0000-0000-0000-000000000301'),
  8,
  'Pricing RPC updates the wholesale minimum'
);
select is(
  (select unit_price from public.product_price_tiers
   where product_id = '90000000-0000-0000-0000-000000000301' and quantity_min = 10),
  6000::numeric,
  'Pricing RPC replaces the matching quantity tier'
);
select is(
  (select moderation_status from public.products where id = '90000000-0000-0000-0000-000000000301'),
  'pending',
  'Changed product prices require moderation before republication'
);
select ok(
  not (select is_active from public.products where id = '90000000-0000-0000-0000-000000000301'),
  'Changed product pricing deactivates the old public offer until approval'
);
select throws_ok(
  $$select public.mg_save_product_pricing(
    '90000000-0000-0000-0000-000000000301',
    9500,
    6800,
    8,
    'both',
    '[{"quantity_min":10,"unit_price":6000},{"quantity_min":20,"unit_price":6500}]'::jsonb
  )$$,
  'P0001',
  'Each higher-quantity tier must have a lower unit price',
  'Invalid pricing update is rejected before changing product terms'
);
select is(
  (select wholesale_price from public.products where id = '90000000-0000-0000-0000-000000000301'),
  6800::numeric,
  'Rejected pricing update leaves the prior product terms intact'
);

update public.profiles
set role = 'admin'
where id = '90000000-0000-0000-0000-000000000102';
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000102","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.mg_admin_moderate_product('90000000-0000-0000-0000-000000000301', 'approved', null)$$,
  'Admin can approve changed pricing before the product is used in checkout tests'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000201', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000101', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.mg_save_product_price_tiers(
    '90000000-0000-0000-0000-000000000301',
    '[]'::jsonb
  )$$,
  '42501',
  'Approved product ownership is required',
  'Buyer cannot change a seller product price'
);
select throws_ok(
  $$select public.mg_save_product_pricing(
    '90000000-0000-0000-0000-000000000301',
    9000,
    6500,
    5,
    'both',
    '[]'::jsonb
  )$$,
  '42501',
  'Approved product ownership is required',
  'Buyer cannot change the product base price or minimum'
);
select throws_ok(
  $$select public.mg_seller_dashboard_stats()$$,
  '42501',
  'Approved seller access required',
  'A buyer cannot access seller dashboard aggregates'
);
select throws_ok(
  $$select public.mg_place_order(
    'Acheteur', '+261341234567', 'Antananarivo', '', '',
    '[{"product_id":"90000000-0000-0000-0000-000000000302","quantity":4}]'::jsonb
  )$$,
  'P0001',
  'A product is inactive or its stock/minimum quantity is invalid',
  'Wholesale order below minimum quantity is rejected'
);
select throws_ok(
  $$select public.mg_place_order(
    'Acheteur', '+261341234567', 'Antananarivo', '', '',
    '[{"product_id":"90000000-0000-0000-0000-000000000302","quantity":6}]'::jsonb
  )$$,
  'P0001',
  'A product is inactive or its stock/minimum quantity is invalid',
  'Order exceeding available stock is rejected'
);
select lives_ok(
  $$select public.mg_place_order(
    'Acheteur', '+261341234567', 'Antananarivo', '', '',
    '[{"product_id":"90000000-0000-0000-0000-000000000301","quantity":1,"price":1}]'::jsonb
  )$$,
  'Hybrid product supports a classic purchase below its wholesale minimum'
);
select is(
  (select unit_price from public.order_items
   where product_id = '90000000-0000-0000-0000-000000000301' and unit_price = 9500),
  9500::numeric,
  'Classic order price is calculated from PostgreSQL, ignoring the submitted browser price'
);
select is(
  (select stock from public.products where id = '90000000-0000-0000-0000-000000000301'),
  49,
  'Classic order decrements stock atomically'
);
select ok(
  exists (
    select 1 from public.order_status_history h
    where h.order_id = (
      select oi.order_id from public.order_items oi
      where oi.product_id = '90000000-0000-0000-0000-000000000301' and oi.unit_price = 9500
      order by oi.created_at desc limit 1
    )
      and h.previous_status is null and h.new_status = 'pending'
  ),
  'Order creation records its initial status'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000202', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);
select throws_ok(
  format(
    'select public.mg_update_order_status(%L::uuid, %L)',
    (select oi.order_id from public.order_items oi
     where oi.product_id = '90000000-0000-0000-0000-000000000301' and oi.unit_price = 9500
     order by oi.created_at desc limit 1),
    'confirmed'
  ),
  '42501',
  'Seller or administrator access required',
  'A different seller cannot change this order status'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000201', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select throws_ok(
  format(
    'select public.mg_update_order_status(%L::uuid, %L)',
    (select oi.order_id from public.order_items oi
     where oi.product_id = '90000000-0000-0000-0000-000000000301' and oi.unit_price = 9500
     order by oi.created_at desc limit 1),
    'delivered'
  ),
  'P0001',
  'Invalid order status transition',
  'Seller cannot skip an order status transition'
);
select lives_ok(
  format(
    'select public.mg_update_order_status(%L::uuid, %L)',
    (select oi.order_id from public.order_items oi
     where oi.product_id = '90000000-0000-0000-0000-000000000301' and oi.unit_price = 9500
     order by oi.created_at desc limit 1),
    'confirmed'
  ),
  'Order seller can confirm its pending order'
);
select lives_ok(
  format(
    'select public.mg_update_order_status(%L::uuid, %L)',
    (select oi.order_id from public.order_items oi
     where oi.product_id = '90000000-0000-0000-0000-000000000301' and oi.unit_price = 9500
     order by oi.created_at desc limit 1),
    'shipped'
  ),
  'Order seller can ship its confirmed order'
);
select lives_ok(
  format(
    'select public.mg_update_order_status(%L::uuid, %L)',
    (select oi.order_id from public.order_items oi
     where oi.product_id = '90000000-0000-0000-0000-000000000301' and oi.unit_price = 9500
     order by oi.created_at desc limit 1),
    'delivered'
  ),
  'Order seller can complete a shipped order'
);
select is(
  (select count(*)::integer from public.order_status_history h
   where h.order_id = (
     select oi.order_id from public.order_items oi
     where oi.product_id = '90000000-0000-0000-0000-000000000301' and oi.unit_price = 9500
     order by oi.created_at desc limit 1
   )),
  4,
  'Order status history records creation and every successful transition'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000101', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.mg_place_order(
    'Acheteur', '+261341234567', 'Antananarivo', '', '',
    '[{"product_id":"90000000-0000-0000-0000-000000000301","quantity":10,"price":1}]'::jsonb
  )$$,
  'Hybrid product supports a wholesale order at the first price tier'
);
select is(
  (select unit_price from public.order_items
   where product_id = '90000000-0000-0000-0000-000000000301' and quantity = 10),
  6000::numeric,
  'Wholesale order uses the database tier matching the requested quantity'
);
select is(
  (select total from public.orders where id = (
    select order_id from public.order_items
    where product_id = '90000000-0000-0000-0000-000000000301' and quantity = 10
  )),
  60000::numeric,
  'Wholesale order total is calculated from its PostgreSQL tier price'
);
select is(
  (select stock from public.products where id = '90000000-0000-0000-0000-000000000301'),
  39,
  'Wholesale tier order reserves the requested stock'
);
select throws_ok(
  $$select public.mg_create_quote_request(
    '90000000-0000-0000-0000-000000000302', 4, ''
  )$$,
  'P0001',
  'Quote quantity is below the wholesale minimum',
  'Quote request below the wholesale minimum is rejected'
);

insert into marketplace_test_quote_ids (quote_id)
select public.mg_create_quote_request(
  '90000000-0000-0000-0000-000000000301', 20, 'Tarif pour commande importante'
);
select is(
  (select stock from public.products where id = '90000000-0000-0000-0000-000000000301'),
  39,
  'Creating a quote does not reserve or alter product stock'
);
select throws_ok(
  format(
    'select public.mg_respond_to_quote(%L::uuid, %L, %s, %L)',
    (select quote_id from marketplace_test_quote_ids where quote_no = 1),
    'responded',
    4500,
    'Prix confidentiel'
  ),
  '42501',
  'Pending quote owned by the current seller was not found',
  'Buyer cannot respond to its own quote request'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000202', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);
select throws_ok(
  format(
    'select public.mg_respond_to_quote(%L::uuid, %L, %s, %L)',
    (select quote_id from marketplace_test_quote_ids where quote_no = 1),
    'responded',
    4500,
    'Prix confidentiel'
  ),
  '42501',
  'Pending quote owned by the current seller was not found',
  'A different seller cannot answer another seller quote'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000201', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select lives_ok(
  format(
    'select public.mg_respond_to_quote(%L::uuid, %L, %s, %L)',
    (select quote_id from marketplace_test_quote_ids where quote_no = 1),
    'responded',
    4500,
    'Prix proposé pour 20 unités'
  ),
  'Seller can respond with a negotiated quote'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000102","role":"authenticated"}',
  true
);
select throws_ok(
  format(
    'select public.mg_place_order(%L, %L, %L, %L, %L, jsonb_build_array(jsonb_build_object(''product_id'', %L, ''quantity'', 20, ''quote_id'', %L)))',
    'Autre acheteur',
    '+261341234567',
    'Antananarivo',
    '',
    '',
    '90000000-0000-0000-0000-000000000301',
    (select quote_id from marketplace_test_quote_ids where quote_no = 1)
  ),
  'P0001',
  'A quote is invalid, expired or does not match the order line',
  'A different buyer cannot accept another buyer quote'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000101', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select lives_ok(
  format(
    'select public.mg_place_order(%L, %L, %L, %L, %L, jsonb_build_array(jsonb_build_object(''product_id'', %L, ''quantity'', 20, ''quote_id'', %L)))',
    'Acheteur',
    '+261341234567',
    'Antananarivo',
    '',
    '',
    '90000000-0000-0000-0000-000000000301',
    (select quote_id from marketplace_test_quote_ids where quote_no = 1)
  ),
  'Buyer acceptance creates an order from the negotiated quote'
);
select is(
  (select unit_price from public.order_items where quote_id = (select quote_id from marketplace_test_quote_ids where quote_no = 1)),
  4500::numeric,
  'Accepted quote price is stored on the order line'
);
select is(
  (select total from public.orders where id = (
    select order_id from public.order_items where quote_id = (select quote_id from marketplace_test_quote_ids where quote_no = 1)
  )),
  90000::numeric,
  'Order total uses the accepted server-side quote price'
);
select is(
  (select stock from public.products where id = '90000000-0000-0000-0000-000000000301'),
  19,
  'Quote order decrements stock exactly once'
);
select is(
  (select status from public.quote_requests where id = (select quote_id from marketplace_test_quote_ids where quote_no = 1)),
  'accepted',
  'Accepted quote cannot be reused'
);
select throws_ok(
  format(
    'select public.mg_place_order(%L, %L, %L, %L, %L, jsonb_build_array(jsonb_build_object(''product_id'', %L, ''quantity'', 20, ''quote_id'', %L)))',
    'Acheteur',
    '+261341234567',
    'Antananarivo',
    '',
    '',
    '90000000-0000-0000-0000-000000000301',
    (select quote_id from marketplace_test_quote_ids where quote_no = 1)
  ),
  'P0001',
  'A quote is invalid, expired or does not match the order line',
  'Accepted quote cannot create a duplicate order'
);

insert into marketplace_test_quote_ids (quote_id)
select public.mg_create_quote_request(
  '90000000-0000-0000-0000-000000000301', 5, 'Seconde demande'
);
select lives_ok(
  format('select public.mg_decline_quote(%L::uuid)', (select quote_id from marketplace_test_quote_ids order by quote_no desc limit 1)),
  'Buyer can decline an open quote request'
);
select is(
  (select status from public.quote_requests where id = (select quote_id from marketplace_test_quote_ids order by quote_no desc limit 1)),
  'cancelled',
  'Declining a quote records its cancelled state'
);
select throws_ok(
  format('select public.mg_decline_quote(%L::uuid)', (select quote_id from marketplace_test_quote_ids order by quote_no desc limit 1)),
  '42501',
  'Open quote owned by the current buyer was not found',
  'A different buyer cannot decline the quote'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000201', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select is(
  public.mg_seller_dashboard_stats() ->> 'published_products',
  '2',
  'Seller dashboard returns the current seller published-product count'
);
select is(
  public.mg_seller_dashboard_stats() ->> 'out_of_stock_products',
  '1',
  'Seller dashboard includes the seller own out-of-stock products'
);
select is(
  public.mg_seller_dashboard_stats() ->> 'received_orders',
  '3',
  'Seller dashboard counts only orders containing this seller items'
);
select is(
  public.mg_seller_dashboard_stats() ->> 'pending_orders',
  '2',
  'Seller dashboard counts orders currently pending'
);
select is(
  public.mg_seller_dashboard_stats() ->> 'completed_orders',
  '1',
  'Seller dashboard counts delivered orders as completed'
);
select is(
  (public.mg_seller_dashboard_stats() ->> 'confirmed_revenue')::numeric,
  69500::numeric,
  'Seller revenue includes confirmed, shipped, and delivered line totals only'
);
select is(
  public.mg_seller_dashboard_stats() ->> 'pending_quotes',
  '0',
  'Seller dashboard counts only quotes that still await a response'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000202', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);
select is(
  public.mg_seller_dashboard_stats() ->> 'received_orders',
  '0',
  'A different seller receives no order counts from this seller'
);
select is(
  (public.mg_seller_dashboard_stats() ->> 'confirmed_revenue')::numeric,
  0::numeric,
  'A different seller receives no revenue from this seller'
);

select throws_ok(
  $$select public.mg_admin_dashboard_stats()$$,
  '42501',
  'Administrator access required',
  'A seller cannot read administrator dashboard metrics'
);
select throws_ok(
  $$select public.mg_admin_set_seller_status('90000000-0000-0000-0000-000000000201', 'suspend', 'Unauthorized')$$,
  '42501',
  'Administrator access required',
  'A seller cannot suspend another seller'
);
select throws_ok(
  $$select public.mg_admin_moderate_product('90000000-0000-0000-0000-000000000303', 'approved', null)$$,
  '42501',
  'Administrator access required',
  'A seller cannot approve a product through the admin moderation RPC'
);
select throws_ok(
  $$select public.mg_submit_product_for_review('90000000-0000-0000-0000-000000000303')$$,
  '42501',
  'Owned product was not found',
  'A different seller cannot submit another seller product for moderation'
);
select throws_ok(
  $$update public.products set is_active = true where id = '90000000-0000-0000-0000-000000000303'$$,
  'P0001',
  'Product must be approved before publication',
  'Unapproved product cannot be activated through a direct table update'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000201', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.mg_submit_product_for_review('90000000-0000-0000-0000-000000000303')$$,
  'Product owner can submit their product for moderation'
);
select is(
  (select moderation_status from public.products where id = '90000000-0000-0000-0000-000000000303'),
  'pending',
  'Seller submission keeps the product pending until an administrator decision'
);

update public.profiles
set role = 'admin'
where id = '90000000-0000-0000-0000-000000000102';
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000102","role":"authenticated"}',
  true
);
select ok(
  public.mg_admin_dashboard_stats() ? 'total_users'
  and public.mg_admin_dashboard_stats() ? 'pending_moderation_products'
  and public.mg_admin_dashboard_stats() ? 'confirmed_gross_sales'
  and (public.mg_admin_dashboard_stats() ->> 'confirmed_gross_sales')::numeric >= 0,
  'Admin dashboard returns real aggregate counts and order volume without implying commission'
);
select lives_ok(
  $$select public.mg_admin_moderate_product('90000000-0000-0000-0000-000000000303', 'approved', null)$$,
  'Administrator can approve a seller product through the protected moderation RPC'
);
select is(
  (select moderation_status from public.products where id = '90000000-0000-0000-0000-000000000303'),
  'approved',
  'Admin approval marks a product approved'
);
select ok(
  (select is_active from public.products where id = '90000000-0000-0000-0000-000000000303'),
  'Admin approval publishes the product'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000101', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.mg_apply_as_seller('Boutique test', 'Commerce', '+261341234567', 'Antananarivo', 'Demande de test')$$,
  'Buyer can submit a seller application for admin review'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000201', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.mg_review_seller('90000000-0000-0000-0000-000000000101', 'approved', null)$$,
  '42501',
  'Administrator access required',
  'A seller cannot approve seller applications'
);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"90000000-0000-0000-0000-000000000102","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.mg_review_seller('90000000-0000-0000-0000-000000000101', 'approved', null)$$,
  'Administrator can approve a seller application through the audited RPC'
);
select is(
  (select seller_status from public.profiles where id = '90000000-0000-0000-0000-000000000101'),
  'approved',
  'Seller application approval updates the user profile'
);
select lives_ok(
  $$select public.mg_admin_set_seller_status('90000000-0000-0000-0000-000000000201', 'suspend', 'Test suspension')$$,
  'Administrator can suspend an approved seller through the protected RPC'
);
select is(
  (select seller_status from public.profiles where id = '90000000-0000-0000-0000-000000000201'),
  'suspended',
  'Seller suspension is persisted on the profile'
);
select ok(
  not (select is_active from public.products where id = '90000000-0000-0000-0000-000000000303'),
  'Suspending a seller deactivates their offers'
);
select lives_ok(
  $$select public.mg_admin_set_seller_status('90000000-0000-0000-0000-000000000201', 'reactivate', null)$$,
  'Administrator can reactivate a suspended seller'
);
select is(
  (select seller_status from public.profiles where id = '90000000-0000-0000-0000-000000000201'),
  'approved',
  'Seller reactivation restores the approved seller state'
);
select ok(
  not (select is_active from public.products where id = '90000000-0000-0000-0000-000000000303'),
  'Reactivating a seller does not automatically republish old offers'
);
select ok(
  (select count(*) >= 4 from public.admin_activity_log
   where target_id in (
     '90000000-0000-0000-0000-000000000201',
     '90000000-0000-0000-0000-000000000303',
     (select id from public.seller_applications where user_id = '90000000-0000-0000-0000-000000000101')
   )),
  'Seller review, suspension, reactivation, and product moderation are recorded in the admin audit log'
);

select ok(
  exists (select 1 from storage.buckets where id = 'product-images' and public),
  'Public product image bucket exists'
);
select ok(
  exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'product_images_seller_insert'),
  'Product image uploads are restricted by storage policy'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'product_images_seller_update'
      and qual ilike '%mg_is_approved_seller%'
      and with_check ilike '%mg_is_approved_seller%'
  ),
  'Storage object updates also require an approved owner'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'product_media'
      and policyname = 'product_media_owner_manage'
      and qual ilike '%mg_is_approved_seller%'
      and with_check ilike '%mg_is_approved_seller%'
  ),
  'Only approved sellers can change product media records'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'product_media'
      and policyname = 'product_media_public_read'
      and qual ilike '%is_active%'
      and qual ilike '%mg_is_approved_seller%'
  ),
  'Public product media follows the active, approved-seller catalogue visibility rule'
);

select * from finish();
rollback;
