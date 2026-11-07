alter table public.profiles
  drop constraint if exists profiles_seller_status_check;
alter table public.profiles
  add constraint profiles_seller_status_check
  check (seller_status in ('none', 'pending', 'approved', 'rejected', 'changes_requested', 'suspended'));

alter table public.products
  add column if not exists moderation_status text,
  add column if not exists moderation_note text not null default '';

update public.products
set moderation_status = case when is_active then 'approved' else 'draft' end
where moderation_status is null;

alter table public.products
  alter column moderation_status set default 'draft',
  alter column moderation_status set not null;
alter table public.products
  drop constraint if exists products_moderation_status_check;
alter table public.products
  add constraint products_moderation_status_check
  check (moderation_status in ('draft', 'pending', 'approved', 'rejected'));

create table if not exists public.admin_activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check (length(trim(action)) between 2 and 80),
  target_type text not null check (target_type in ('seller_application', 'seller', 'product')),
  target_id uuid,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);

create index if not exists admin_activity_log_created_idx
  on public.admin_activity_log (created_at desc);
create index if not exists products_moderation_status_created_idx
  on public.products (moderation_status, created_at desc);

create or replace function public.track_product_moderation_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.category_id is distinct from old.category_id
    or new.name is distinct from old.name
    or new.description is distinct from old.description
    or new.variants is distinct from old.variants
    or new.price is distinct from old.price
    or new.wholesale_price is distinct from old.wholesale_price
    or new.min_wholesale_qty is distinct from old.min_wholesale_qty
    or new.selling_mode is distinct from old.selling_mode
    or new.image_url is distinct from old.image_url
    or new.image_path is distinct from old.image_path
  then
    if old.moderation_status in ('approved', 'rejected') then
      new.moderation_status := 'pending';
    end if;
    new.moderation_note := '';
    new.is_active := false;
  end if;
  return new;
end;
$$;

drop trigger if exists marketplace_product_moderation_changes on public.products;
create trigger marketplace_product_moderation_changes
  before update on public.products
  for each row execute function public.track_product_moderation_changes();

create or replace function public.prevent_unmoderated_product_activation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_active and new.moderation_status is distinct from 'approved' then
    raise exception 'Product must be approved before publication';
  end if;
  return new;
end;
$$;

drop trigger if exists marketplace_product_activation_guard on public.products;
create trigger marketplace_product_activation_guard
  before insert or update of is_active, moderation_status on public.products
  for each row execute function public.prevent_unmoderated_product_activation();

drop policy if exists products_public_or_owner_read on public.products;
create policy products_public_or_owner_read on public.products for select to anon, authenticated
  using (
    (is_active and moderation_status = 'approved' and public.mg_is_approved_seller(seller_id))
    or seller_id = (select auth.uid())
    or public.is_marketplace_admin()
  );

alter table public.admin_activity_log enable row level security;
drop policy if exists admin_activity_log_admin_read on public.admin_activity_log;
create policy admin_activity_log_admin_read on public.admin_activity_log for select to authenticated
  using (public.is_marketplace_admin());
revoke all on public.admin_activity_log from anon, authenticated;
grant select on public.admin_activity_log to authenticated;

create or replace function public.mg_review_seller(
  p_user_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  application_row public.seller_applications;
  previous_status text;
  note_value text := nullif(trim(p_note), '');
begin
  if p_decision is null or p_user_id is null then
    raise exception 'Seller and decision are required';
  end if;
  if not public.is_marketplace_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_decision not in ('approved', 'rejected', 'changes_requested') then
    raise exception 'Invalid seller decision';
  end if;
  if length(coalesce(note_value, '')) > 2000 then
    raise exception 'Seller review note cannot exceed 2000 characters';
  end if;
  if p_decision in ('rejected', 'changes_requested') and note_value is null then
    raise exception 'A review note is required for this seller decision';
  end if;

  select a.* into application_row
  from public.seller_applications a
  where a.user_id = p_user_id
  for update;
  if not found then
    raise exception 'Seller application not found';
  end if;

  select p.seller_status into previous_status
  from public.profiles p
  where p.id = p_user_id
  for update;
  if not found then
    raise exception 'Marketplace profile not found';
  end if;

  update public.seller_applications
    set status = p_decision, admin_note = note_value
    where user_id = p_user_id;

  if p_decision <> 'approved' then
    update public.products set is_active = false where seller_id = p_user_id;
  end if;

  update public.profiles
    set role = case when p_decision = 'approved' then 'seller' else 'buyer' end,
        seller_status = p_decision,
        seller_rejection_reason = coalesce(note_value, '')
    where id = p_user_id;

  insert into public.marketplace_notifications (user_id, title, message)
  values (
    p_user_id,
    'Mise à jour de votre demande vendeur',
    case p_decision
      when 'approved' then 'Votre boutique est approuvée. Vous pouvez maintenant gérer vos produits.'
      when 'rejected' then 'Votre demande vendeur a été refusée.'
      else 'Des modifications sont demandées pour votre demande vendeur.'
    end
  );

  insert into public.admin_activity_log (actor_id, action, target_type, target_id, details)
  values (
    auth.uid(), 'seller_application_' || p_decision, 'seller_application', application_row.id,
    jsonb_build_object(
      'user_id', p_user_id,
      'previous_status', previous_status,
      'new_status', p_decision,
      'admin_note', note_value
    )
  );
end;
$$;

create or replace function public.mg_admin_set_seller_status(
  p_user_id uuid,
  p_action text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  seller_row public.profiles;
  next_status text;
  note_value text := nullif(trim(p_note), '');
begin
  if not public.is_marketplace_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_user_id is null or p_action is null or p_action not in ('suspend', 'reactivate') then
    raise exception 'Seller and a valid action are required';
  end if;
  if length(coalesce(note_value, '')) > 2000 then
    raise exception 'Seller status note cannot exceed 2000 characters';
  end if;

  select p.* into seller_row
  from public.profiles p
  where p.id = p_user_id
  for update;
  if not found or seller_row.role <> 'seller' then
    raise exception 'Seller profile not found';
  end if;

  if p_action = 'suspend' and seller_row.seller_status = 'approved' then
    next_status := 'suspended';
  elsif p_action = 'reactivate' and seller_row.seller_status = 'suspended' then
    next_status := 'approved';
  else
    raise exception 'Seller status does not allow this action';
  end if;

  update public.profiles
  set seller_status = next_status,
      seller_rejection_reason = coalesce(note_value, '')
  where id = p_user_id;

  if p_action = 'suspend' then
    update public.products set is_active = false where seller_id = p_user_id;
  end if;

  insert into public.marketplace_notifications (user_id, title, message)
  values (
    p_user_id,
    case when p_action = 'suspend' then 'Compte vendeur suspendu' else 'Compte vendeur réactivé' end,
    case when p_action = 'suspend'
      then coalesce(note_value, 'Votre compte vendeur a été suspendu par l’administration.')
      else 'Votre compte vendeur est réactivé. Vos offres restent désactivées jusqu’à leur republication.'
    end
  );

  insert into public.admin_activity_log (actor_id, action, target_type, target_id, details)
  values (
    auth.uid(), 'seller_' || p_action, 'seller', p_user_id,
    jsonb_build_object(
      'previous_status', seller_row.seller_status,
      'new_status', next_status,
      'admin_note', note_value
    )
  );
end;
$$;

create or replace function public.mg_submit_product_for_review(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_row public.products;
  caller uuid := auth.uid();
begin
  if caller is null or not public.mg_is_approved_seller(caller) then
    raise exception 'Approved seller access required' using errcode = '42501';
  end if;
  select p.* into product_row
  from public.products p
  where p.id = p_product_id and p.seller_id = caller
  for update;
  if not found then
    raise exception 'Owned product was not found' using errcode = '42501';
  end if;
  if product_row.moderation_status = 'approved' then
    raise exception 'Product is already approved';
  end if;

  update public.products
  set moderation_status = 'pending', moderation_note = '', is_active = false
  where id = p_product_id;
end;
$$;

create or replace function public.mg_admin_moderate_product(
  p_product_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_row public.products;
  note_value text := nullif(trim(p_note), '');
begin
  if not public.is_marketplace_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_product_id is null or p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'Product and a valid moderation decision are required';
  end if;
  if length(coalesce(note_value, '')) > 2000 then
    raise exception 'Product moderation note cannot exceed 2000 characters';
  end if;
  if p_decision = 'rejected' and note_value is null then
    raise exception 'A moderation note is required when rejecting a product';
  end if;

  select p.* into product_row
  from public.products p
  where p.id = p_product_id
  for update;
  if not found then
    raise exception 'Product not found';
  end if;
  if p_decision = 'approved' and not public.mg_is_approved_seller(product_row.seller_id) then
    raise exception 'Only products of an approved seller can be published';
  end if;

  update public.products
  set moderation_status = p_decision,
      moderation_note = coalesce(note_value, ''),
      is_active = (p_decision = 'approved')
  where id = p_product_id;

  insert into public.marketplace_notifications (user_id, title, message)
  values (
    product_row.seller_id,
    case when p_decision = 'approved' then 'Produit approuvé' else 'Produit refusé' end,
    case when p_decision = 'approved'
      then 'Votre produit « ' || product_row.name || ' » est approuvé et publié.'
      else 'Votre produit « ' || product_row.name || ' » nécessite des modifications. ' || coalesce(note_value, '')
    end
  );

  insert into public.admin_activity_log (actor_id, action, target_type, target_id, details)
  values (
    auth.uid(), 'product_' || p_decision, 'product', p_product_id,
    jsonb_build_object(
      'seller_id', product_row.seller_id,
      'product_name', product_row.name,
      'previous_status', product_row.moderation_status,
      'new_status', p_decision,
      'admin_note', note_value
    )
  );
end;
$$;

create or replace function public.mg_admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  product_counts record;
  order_counts record;
begin
  if not public.is_marketplace_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  select count(*) as total_products,
         count(*) filter (where p.moderation_status = 'approved' and p.is_active) as published_products,
         count(*) filter (where p.moderation_status = 'pending') as pending_moderation_products
  into product_counts
  from public.products p;

  select count(distinct o.id) as total_orders,
         count(distinct o.id) filter (where o.status = 'pending') as pending_orders,
         count(distinct o.id) filter (where o.status = 'delivered') as completed_orders,
         coalesce(sum(oi.unit_price * oi.quantity)
           filter (where o.status in ('confirmed', 'shipped', 'delivered')), 0) as confirmed_gross_sales
  into order_counts
  from public.orders o
  left join public.order_items oi on oi.order_id = o.id;

  return jsonb_build_object(
    'total_users', (select count(*) from public.profiles),
    'buyers', (select count(*) from public.profiles p where p.role = 'buyer'),
    'approved_sellers', (select count(*) from public.profiles p where p.role = 'seller' and p.seller_status = 'approved'),
    'pending_sellers', (select count(*) from public.profiles p where p.seller_status = 'pending'),
    'suspended_sellers', (select count(*) from public.profiles p where p.role = 'seller' and p.seller_status = 'suspended'),
    'total_products', coalesce(product_counts.total_products, 0),
    'published_products', coalesce(product_counts.published_products, 0),
    'pending_moderation_products', coalesce(product_counts.pending_moderation_products, 0),
    'total_orders', coalesce(order_counts.total_orders, 0),
    'pending_orders', coalesce(order_counts.pending_orders, 0),
    'completed_orders', coalesce(order_counts.completed_orders, 0),
    'confirmed_gross_sales', coalesce(order_counts.confirmed_gross_sales, 0),
    'pending_quotes', (select count(*) from public.quote_requests q where q.status = 'pending')
  );
end;
$$;

revoke all on function public.track_product_moderation_changes() from public, anon, authenticated;
revoke all on function public.prevent_unmoderated_product_activation() from public, anon, authenticated;
revoke all on function public.mg_review_seller(uuid, text, text) from public, anon;
revoke all on function public.mg_admin_set_seller_status(uuid, text, text) from public, anon;
revoke all on function public.mg_submit_product_for_review(uuid) from public, anon;
revoke all on function public.mg_admin_moderate_product(uuid, text, text) from public, anon;
revoke all on function public.mg_admin_dashboard_stats() from public, anon;
grant execute on function public.mg_review_seller(uuid, text, text) to authenticated;
grant execute on function public.mg_admin_set_seller_status(uuid, text, text) to authenticated;
grant execute on function public.mg_submit_product_for_review(uuid) to authenticated;
grant execute on function public.mg_admin_moderate_product(uuid, text, text) to authenticated;
grant execute on function public.mg_admin_dashboard_stats() to authenticated;
