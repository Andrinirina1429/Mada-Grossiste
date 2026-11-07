create extension if not exists pgcrypto with schema extensions;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) between 2 and 80),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.categories (name, slug) values
  ('Vêtements', 'vetements'),
  ('Accessoires', 'accessoires'),
  ('Téléphonie', 'telephonie'),
  ('Chaussures', 'chaussures'),
  ('Maison et équipement', 'maison-equipement'),
  ('Alimentation', 'alimentation'),
  ('Autres', 'autres')
on conflict (slug) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text not null default '',
  shop_name text not null default '',
  phone text not null default '',
  public_phone_consent boolean not null default false,
  city text not null default '',
  business text not null default '',
  about text not null default '',
  role text not null default 'buyer' check (role in ('buyer', 'seller', 'admin')),
  requested_role text not null default 'buyer' check (requested_role in ('buyer', 'seller')),
  seller_status text not null default 'none'
    check (seller_status in ('none', 'pending', 'approved', 'rejected', 'changes_requested')),
  seller_rejection_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.seller_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  shop_name text not null,
  business text not null default '',
  phone text not null default '',
  public_phone_consent boolean not null default false,
  city text not null default '',
  about text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'changes_requested')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null check (length(trim(name)) between 2 and 120),
  description text not null default '' check (length(description) <= 3000),
  variants text not null default '' check (length(variants) <= 500),
  price numeric(14,2) not null check (price > 0 and price = trunc(price)),
  wholesale_price numeric(14,2) check (wholesale_price is null or (wholesale_price > 0 and wholesale_price = trunc(wholesale_price))),
  min_wholesale_qty integer not null default 1 check (min_wholesale_qty > 0),
  selling_mode text not null default 'wholesale' check (selling_mode in ('classic', 'wholesale', 'both')),
  stock integer not null default 0 check (stock >= 0),
  seller_name text not null default '',
  seller_phone text not null default '',
  image_url text,
  image_path text,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.products
  add column if not exists wholesale_price numeric(14,2)
    check (wholesale_price is null or (wholesale_price > 0 and wholesale_price = trunc(wholesale_price))),
  add column if not exists min_wholesale_qty integer not null default 1
    check (min_wholesale_qty > 0),
  add column if not exists selling_mode text not null default 'wholesale'
  check (selling_mode in ('classic', 'wholesale', 'both'));

create table if not exists public.product_price_tiers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  quantity_min integer not null check (quantity_min > 0),
  unit_price numeric(14,2) not null check (unit_price > 0 and unit_price = trunc(unit_price)),
  created_at timestamptz not null default now(),
  unique (product_id, quantity_min)
);

create or replace function public.validate_product_price_tiers()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and (
    new.price is distinct from old.price
    or new.wholesale_price is distinct from old.wholesale_price
    or new.min_wholesale_qty is distinct from old.min_wholesale_qty
    or new.selling_mode is distinct from old.selling_mode
  ) and exists (
    select 1
    from public.product_price_tiers t
    where t.product_id = new.id
      and (
        new.selling_mode = 'classic'
        or t.quantity_min < new.min_wholesale_qty
      )
  ) then
    raise exception 'Product pricing changes must preserve or replace all existing price tiers';
  end if;

  if tg_op = 'UPDATE' and (
    new.price is distinct from old.price
    or new.wholesale_price is distinct from old.wholesale_price
    or new.min_wholesale_qty is distinct from old.min_wholesale_qty
    or new.selling_mode is distinct from old.selling_mode
  ) and exists (
    select 1
    from (
      select t.quantity_min, t.unit_price,
        lag(t.unit_price, 1, coalesce(new.wholesale_price, new.price))
          over (order by t.quantity_min) as previous_price
      from public.product_price_tiers t
      where t.product_id = new.id
    ) tiers
    where tiers.unit_price >= tiers.previous_price
  ) then
    raise exception 'Product pricing changes must preserve descending price tiers';
  end if;

  return new;
end;
$$;

drop trigger if exists products_validate_price_tiers on public.products;
create trigger products_validate_price_tiers
  before update of price, wholesale_price, min_wholesale_qty, selling_mode on public.products
  for each row execute function public.validate_product_price_tiers();

create table if not exists public.carts (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'converted', 'abandoned')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists carts_one_active_per_buyer
  on public.carts (buyer_id) where status = 'active';

create table if not exists public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.carts(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cart_id, product_id)
);

create table if not exists public.buyer_favorites (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (buyer_id, product_id)
);

create table if not exists public.shipping_addresses (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  recipient_name text not null,
  phone text not null,
  address text not null,
  city text not null,
  region text,
  instructions text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('MG-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
  buyer_name text not null,
  phone text not null,
  city text not null,
  delivery text not null default '',
  note text not null default '',
  total numeric(14,2) not null default 0 check (total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  product_name text not null,
  unit_price numeric(14,2) not null check (unit_price > 0),
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  previous_status text check (previous_status in ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
  new_status text not null check (new_status in ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
  created_at timestamptz not null default now()
);
create index if not exists order_status_history_order_idx
  on public.order_status_history (order_id, created_at desc);

create or replace function public.record_order_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history (order_id, actor_id, previous_status, new_status)
    values (new.id, auth.uid(), null, new.status);
  elsif old.status is distinct from new.status then
    insert into public.order_status_history (order_id, actor_id, previous_status, new_status)
    values (new.id, auth.uid(), old.status, new.status);
  end if;
  return new;
end;
$$;

drop trigger if exists marketplace_order_status_history on public.orders;
create trigger marketplace_order_status_history
  after insert or update of status on public.orders
  for each row execute function public.record_order_status_history();

insert into public.order_status_history (order_id, actor_id, previous_status, new_status)
select o.id, null, null, o.status
from public.orders o
where not exists (
  select 1 from public.order_status_history h
  where h.order_id = o.id and h.previous_status is null
);

create table if not exists public.quote_requests (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  requested_quantity integer not null check (requested_quantity > 0),
  buyer_note text not null default '' check (length(buyer_note) <= 2000),
  status text not null default 'pending'
    check (status in ('pending', 'responded', 'rejected', 'accepted', 'cancelled')),
  proposed_unit_price numeric(14,2)
    check (proposed_unit_price is null or (proposed_unit_price > 0 and proposed_unit_price = trunc(proposed_unit_price))),
  seller_note text not null default '' check (length(seller_note) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz
);
create index if not exists quote_requests_buyer_idx on public.quote_requests (buyer_id, created_at desc);
create index if not exists quote_requests_seller_status_idx on public.quote_requests (seller_id, status, created_at desc);

alter table public.order_items
  add column if not exists quote_id uuid references public.quote_requests(id) on delete set null;

create table if not exists public.marketplace_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  message text not null check (length(trim(message)) between 1 and 5000),
  created_at timestamptz not null default now(),
  check (sender_id <> receiver_id)
);

create table if not exists public.marketplace_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.seller_delivery_zones (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  city text not null check (length(trim(city)) between 1 and 120),
  delivery_fee numeric(14,2) not null default 0 check (delivery_fee >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.product_media (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  media_url text not null,
  storage_path text,
  media_type text not null default 'image' check (media_type in ('image', 'video')),
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.marketplace_promotions (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 120),
  discount_percent numeric(5,2) not null check (discount_percent > 0 and discount_percent <= 100),
  active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index if not exists products_active_created_idx on public.products (created_at desc) where is_active;
create index if not exists products_seller_created_idx on public.products (seller_id, created_at desc);
create index if not exists products_category_active_idx on public.products (category_id, created_at desc) where is_active;
create index if not exists seller_applications_status_idx on public.seller_applications (status, created_at desc);
create index if not exists cart_items_cart_idx on public.cart_items (cart_id);
create index if not exists buyer_favorites_buyer_idx on public.buyer_favorites (buyer_id, created_at desc);
create index if not exists shipping_addresses_buyer_idx on public.shipping_addresses (buyer_id, created_at desc);
create index if not exists orders_buyer_idx on public.orders (buyer_id, created_at desc);
create index if not exists orders_status_idx on public.orders (status, created_at desc);
create index if not exists order_items_seller_idx on public.order_items (seller_id, order_id);
create index if not exists marketplace_messages_participants_idx
  on public.marketplace_messages (sender_id, receiver_id, created_at desc);
create index if not exists marketplace_notifications_user_idx
  on public.marketplace_notifications (user_id, created_at desc);
create index if not exists seller_delivery_zones_seller_idx on public.seller_delivery_zones (seller_id);
create index if not exists product_media_product_idx on public.product_media (product_id, position);
create index if not exists marketplace_promotions_seller_idx on public.marketplace_promotions (seller_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.is_marketplace_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

create or replace function public.mg_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_marketplace_admin();
$$;

create or replace function public.mg_is_order_seller(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.order_items oi
    where oi.order_id = p_order_id and oi.seller_id = (select auth.uid())
  );
$$;

create or replace function public.mg_is_order_buyer(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.buyer_id = (select auth.uid())
  );
$$;

create or replace function public.mg_is_approved_seller(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_seller_id and p.role = 'seller' and p.seller_status = 'approved'
  );
$$;

create or replace function public.handle_new_marketplace_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested text := case when new.raw_user_meta_data ->> 'role' = 'seller' then 'seller' else 'buyer' end;
  name_value text := coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '');
  shop_value text := coalesce(new.raw_user_meta_data ->> 'shop', '');
begin
  insert into public.profiles (
    id, email, full_name, shop_name, phone, public_phone_consent, city, business, about,
    role, requested_role, seller_status
  ) values (
    new.id, new.email, name_value, shop_value,
    coalesce(new.raw_user_meta_data ->> 'phone', ''), false,
    coalesce(new.raw_user_meta_data ->> 'city', ''),
    coalesce(new.raw_user_meta_data ->> 'business', ''),
    coalesce(new.raw_user_meta_data ->> 'about', ''),
    'buyer', requested, case when requested = 'seller' then 'pending' else 'none' end
  );

  if requested = 'seller' then
    insert into public.seller_applications (user_id, shop_name, business, phone, public_phone_consent, city, about)
    values (
      new.id, coalesce(nullif(shop_value, ''), 'Boutique à compléter'),
      coalesce(new.raw_user_meta_data ->> 'business', ''),
      coalesce(new.raw_user_meta_data ->> 'phone', ''),
      false,
      coalesce(new.raw_user_meta_data ->> 'city', ''),
      coalesce(new.raw_user_meta_data ->> 'about', '')
    );
  end if;
  return new;
end;
$$;

create or replace function public.sync_product_seller_details()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.seller_id is distinct from old.seller_id then
      select coalesce(nullif(p.shop_name, ''), p.full_name),
             case when p.role = 'seller' and p.seller_status = 'approved' and p.public_phone_consent then p.phone else '' end
        into new.seller_name, new.seller_phone
      from public.profiles p
      where p.id = new.seller_id and p.role = 'seller' and p.seller_status = 'approved';
      if not found then
        raise exception 'An approved seller profile is required to manage products';
      end if;
    else
      select coalesce(nullif(p.shop_name, ''), p.full_name),
             case when p.role = 'seller' and p.seller_status = 'approved' and p.public_phone_consent then p.phone else '' end
        into new.seller_name, new.seller_phone
      from public.profiles p
      where p.id = new.seller_id;
      if not found then
        raise exception 'Product seller profile not found';
      end if;
    end if;
  else
    select coalesce(nullif(p.shop_name, ''), p.full_name),
           case when p.public_phone_consent then p.phone else '' end
      into new.seller_name, new.seller_phone
    from public.profiles p
    where p.id = new.seller_id and p.role = 'seller' and p.seller_status = 'approved';
    if not found then
      raise exception 'An approved seller profile is required to manage products';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.sync_marketplace_products_from_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.products
    set seller_name = coalesce(nullif(new.shop_name, ''), new.full_name),
        seller_phone = case
          when new.role = 'seller' and new.seller_status = 'approved' and new.public_phone_consent then new.phone
          else ''
        end
    where seller_id = new.id;
  return new;
end;
$$;

create or replace function public.mg_set_public_phone_consent(p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  applicant uuid := auth.uid();
begin
  if applicant is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
    set public_phone_consent = coalesce(p_enabled, false)
    where id = applicant
      and (
        (role = 'seller' and seller_status = 'approved')
        or (requested_role = 'seller' and seller_status = 'pending')
      );
  if not found then
    raise exception 'Only approved sellers and pending seller applicants can change public phone consent'
      using errcode = '42501';
  end if;

  update public.seller_applications
    set public_phone_consent = coalesce(p_enabled, false)
    where user_id = applicant;
end;
$$;

create or replace function public.notify_marketplace_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.marketplace_notifications (user_id, title, message)
  values (new.receiver_id, 'Nouveau message', 'Vous avez reçu un nouveau message sur MadaGrossiste.');
  return new;
end;
$$;

create or replace function public.mg_apply_as_seller(
  p_shop_name text,
  p_business text,
  p_phone text,
  p_city text,
  p_about text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  applicant uuid := auth.uid();
  shop_value text := trim(coalesce(p_shop_name, ''));
  business_value text := trim(coalesce(p_business, ''));
  phone_value text := trim(coalesce(p_phone, ''));
  city_value text := trim(coalesce(p_city, ''));
  about_value text := trim(coalesce(p_about, ''));
begin
  if applicant is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if length(shop_value) not between 2 and 120
    or length(phone_value) not between 7 and 32
    or length(city_value) not between 1 and 120
    or length(business_value) > 160
    or length(about_value) > 3000 then
    raise exception 'Seller application details are invalid';
  end if;
  if exists (
    select 1 from public.profiles p
    where p.id = applicant
      and (p.role = 'admin' or (p.role = 'seller' and p.seller_status = 'approved'))
  ) then
    raise exception 'This account cannot submit another seller application';
  end if;

  update public.profiles
    set shop_name = shop_value,
        business = business_value,
        phone = phone_value,
        city = city_value,
        about = about_value,
        requested_role = 'seller',
        seller_status = 'pending',
        seller_rejection_reason = ''
    where id = applicant;
  if not found then
    raise exception 'Marketplace profile not found';
  end if;

  insert into public.seller_applications (user_id, shop_name, business, phone, city, about, status, admin_note)
  values (applicant, shop_value, business_value, phone_value, city_value, about_value, 'pending', null)
  on conflict (user_id) do update
    set shop_name = excluded.shop_name,
        business = excluded.business,
        phone = excluded.phone,
        city = excluded.city,
        about = excluded.about,
        status = 'pending',
        admin_note = null;
end;
$$;

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

  update public.seller_applications
    set status = p_decision, admin_note = nullif(trim(p_note), '')
    where user_id = p_user_id;
  if not found then
    raise exception 'Seller application not found';
  end if;

  if p_decision <> 'approved' then
    update public.products set is_active = false where seller_id = p_user_id;
  end if;

  update public.profiles
    set role = case when p_decision = 'approved' then 'seller' else 'buyer' end,
        seller_status = p_decision,
        seller_rejection_reason = coalesce(nullif(trim(p_note), ''), '')
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
end;
$$;

create or replace function public.mg_save_product_price_tiers(p_product_id uuid, p_tiers jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  product_row public.products;
begin
  if caller is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_tiers) is distinct from 'array' then
    raise exception 'Price tiers must be an array containing at most 20 entries';
  end if;
  if jsonb_array_length(p_tiers) > 20 then
    raise exception 'Price tiers must be an array containing at most 20 entries';
  end if;

  select p.* into product_row
  from public.products p
  where p.id = p_product_id
    and (p.seller_id = caller or public.is_marketplace_admin())
    and public.mg_is_approved_seller(p.seller_id)
  for update;
  if not found then
    raise exception 'Approved product ownership is required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_tiers) as entry(value)
    where jsonb_typeof(entry.value) is distinct from 'object'
      or jsonb_typeof(entry.value -> 'quantity_min') is distinct from 'number'
      or (entry.value ->> 'quantity_min') !~ '^[1-9][0-9]*$'
      or jsonb_typeof(entry.value -> 'unit_price') is distinct from 'number'
      or (entry.value ->> 'unit_price') !~ '^[1-9][0-9]*$'
  ) then
    raise exception 'Each price tier needs a positive integer quantity and unit price';
  end if;
  if product_row.selling_mode = 'classic' and jsonb_array_length(p_tiers) > 0 then
    raise exception 'Classic-only products cannot have wholesale price tiers';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric)
    where x.quantity_min < product_row.min_wholesale_qty
      or x.unit_price > 999999999999.99
  ) or (
    select count(*) <> count(distinct x.quantity_min)
    from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric)
  ) then
    raise exception 'Price tiers must be unique and start at or above the wholesale minimum';
  end if;
  if exists (
    select 1
    from (
      select x.quantity_min, x.unit_price,
        lag(x.unit_price, 1, coalesce(product_row.wholesale_price, product_row.price))
          over (order by x.quantity_min) as previous_price
      from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric)
    ) ordered_tiers
    where ordered_tiers.unit_price >= ordered_tiers.previous_price
  ) then
    raise exception 'Each higher-quantity tier must have a lower unit price';
  end if;

  delete from public.product_price_tiers where product_id = p_product_id;
  insert into public.product_price_tiers (product_id, quantity_min, unit_price)
  select p_product_id, x.quantity_min, x.unit_price
  from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric);
end;
$$;

create or replace function public.mg_save_product_pricing(
  p_product_id uuid,
  p_price numeric,
  p_wholesale_price numeric,
  p_min_wholesale_qty integer,
  p_selling_mode text,
  p_tiers jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_price is null or p_price <= 0 or p_price <> trunc(p_price) or p_price > 999999999999.99
    or (p_wholesale_price is not null and (
      p_wholesale_price <= 0 or p_wholesale_price <> trunc(p_wholesale_price)
      or p_wholesale_price > 999999999999.99
    ))
    or p_min_wholesale_qty is null or p_min_wholesale_qty < 1
    or p_selling_mode is null or p_selling_mode not in ('classic', 'wholesale', 'both') then
    raise exception 'Product pricing is invalid';
  end if;
  if jsonb_typeof(p_tiers) is distinct from 'array' then
    raise exception 'Price tiers must be an array containing at most 20 entries';
  end if;
  if jsonb_array_length(p_tiers) > 20 then
    raise exception 'Price tiers must be an array containing at most 20 entries';
  end if;
  if p_selling_mode = 'classic' and (
    p_wholesale_price is not null or p_min_wholesale_qty <> 1 or jsonb_array_length(p_tiers) > 0
  ) then
    raise exception 'Classic-only products cannot have wholesale terms';
  end if;

  perform p.id
  from public.products p
  where p.id = p_product_id
    and (p.seller_id = caller or public.is_marketplace_admin())
    and public.mg_is_approved_seller(p.seller_id)
  for update;
  if not found then
    raise exception 'Approved product ownership is required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_tiers) as entry(value)
    where jsonb_typeof(entry.value) is distinct from 'object'
      or jsonb_typeof(entry.value -> 'quantity_min') is distinct from 'number'
      or (entry.value ->> 'quantity_min') !~ '^[1-9][0-9]*$'
      or jsonb_typeof(entry.value -> 'unit_price') is distinct from 'number'
      or (entry.value ->> 'unit_price') !~ '^[1-9][0-9]*$'
  ) then
    raise exception 'Each price tier needs a positive integer quantity and unit price';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric)
    where x.quantity_min < p_min_wholesale_qty
      or x.unit_price > 999999999999.99
  ) or (
    select count(*) <> count(distinct x.quantity_min)
    from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric)
  ) then
    raise exception 'Price tiers must be unique and start at or above the wholesale minimum';
  end if;
  if exists (
    select 1
    from (
      select x.quantity_min, x.unit_price,
        lag(x.unit_price, 1, coalesce(p_wholesale_price, p_price))
          over (order by x.quantity_min) as previous_price
      from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric)
    ) ordered_tiers
    where ordered_tiers.unit_price >= ordered_tiers.previous_price
  ) then
    raise exception 'Each higher-quantity tier must have a lower unit price';
  end if;

  delete from public.product_price_tiers where product_id = p_product_id;
  update public.products
  set price = p_price,
      wholesale_price = case when p_selling_mode = 'classic' then null else p_wholesale_price end,
      min_wholesale_qty = p_min_wholesale_qty,
      selling_mode = p_selling_mode
  where id = p_product_id;
  insert into public.product_price_tiers (product_id, quantity_min, unit_price)
  select p_product_id, x.quantity_min, x.unit_price
  from jsonb_to_recordset(p_tiers) as x(quantity_min integer, unit_price numeric);
end;
$$;

create or replace function public.mg_create_quote_request(
  p_product_id uuid,
  p_quantity integer,
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  buyer uuid := auth.uid();
  product_row public.products;
  quote_id uuid;
begin
  if buyer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity < 1 or length(coalesce(p_note, '')) > 2000 then
    raise exception 'Quote quantity or note is invalid';
  end if;

  select p.* into product_row
  from public.products p
  where p.id = p_product_id and p.is_active
    and p.seller_id <> buyer
    and public.mg_is_approved_seller(p.seller_id);
  if not found then
    raise exception 'Product is unavailable';
  end if;
  if p_quantity > product_row.stock then
    raise exception 'Requested quantity exceeds available stock';
  end if;
  if product_row.selling_mode in ('wholesale', 'both')
    and p_quantity < product_row.min_wholesale_qty then
    raise exception 'Quote quantity is below the wholesale minimum';
  end if;

  insert into public.quote_requests (buyer_id, seller_id, product_id, requested_quantity, buyer_note)
  values (buyer, product_row.seller_id, product_row.id, p_quantity, coalesce(trim(p_note), ''))
  returning id into quote_id;

  insert into public.marketplace_notifications (user_id, title, message)
  values (product_row.seller_id, 'Nouvelle demande de devis', 'Un acheteur demande un tarif pour un produit.');
  return quote_id;
end;
$$;

create or replace function public.mg_respond_to_quote(
  p_quote_id uuid,
  p_decision text,
  p_unit_price numeric default null,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  quote_row public.quote_requests;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('responded', 'rejected')
    or length(coalesce(p_note, '')) > 2000
    or (p_decision = 'responded' and (
      p_unit_price is null or p_unit_price <= 0 or p_unit_price <> trunc(p_unit_price)
      or p_unit_price > 999999999999.99
    ))
    or (p_decision = 'rejected' and p_unit_price is not null) then
    raise exception 'Quote response is invalid';
  end if;

  select q.* into quote_row
  from public.quote_requests q
  where q.id = p_quote_id and q.seller_id = auth.uid()
    and public.mg_is_approved_seller(auth.uid())
  for update;
  if not found or quote_row.status <> 'pending' then
    raise exception 'Pending quote owned by the current seller was not found' using errcode = '42501';
  end if;

  update public.quote_requests
  set status = p_decision,
      proposed_unit_price = case when p_decision = 'responded' then p_unit_price else null end,
      seller_note = coalesce(trim(p_note), ''),
      responded_at = now()
  where id = p_quote_id;

  insert into public.marketplace_notifications (user_id, title, message)
  values (
    quote_row.buyer_id,
    case when p_decision = 'responded' then 'Votre devis est prêt' else 'Demande de devis refusée' end,
    case when p_decision = 'responded' then 'Le vendeur a répondu à votre demande de devis.'
      else 'Le vendeur ne peut pas répondre favorablement à votre demande de devis.' end
  );
end;
$$;

create or replace function public.mg_decline_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  quote_row public.quote_requests;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select q.* into quote_row
  from public.quote_requests q
  where q.id = p_quote_id and q.buyer_id = auth.uid()
  for update;
  if not found or quote_row.status not in ('pending', 'responded') then
    raise exception 'Open quote owned by the current buyer was not found' using errcode = '42501';
  end if;

  update public.quote_requests
  set status = 'cancelled'
  where id = p_quote_id;
end;
$$;

create or replace function public.mg_place_order(
  p_buyer_name text,
  p_phone text,
  p_city text,
  p_delivery text,
  p_note text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  buyer uuid := auth.uid();
  product_ids uuid[];
  item_count integer;
  order_row public.orders;
  seller_row record;
  total_value numeric(14,2);
  created_orders jsonb := '[]'::jsonb;
begin
  if buyer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'The order must contain at least one item';
  end if;
  if jsonb_array_length(p_items) = 0 then
    raise exception 'The order must contain at least one item';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'An order cannot contain more than 100 lines';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) as entry(value)
    where jsonb_typeof(entry.value) is distinct from 'object'
      or jsonb_typeof(entry.value -> 'product_id') is distinct from 'string'
      or nullif(entry.value ->> 'product_id', '') is null
      or jsonb_typeof(entry.value -> 'quantity') is distinct from 'number'
      or (entry.value ->> 'quantity') !~ '^[1-9][0-9]*$'
      or (entry.value ? 'quote_id' and jsonb_typeof(entry.value -> 'quote_id') is distinct from 'string')
  ) then
    raise exception 'Each order line must contain a product UUID and a positive integer quantity';
  end if;
  if nullif(trim(p_buyer_name), '') is null or length(trim(p_buyer_name)) > 160
    or nullif(trim(p_phone), '') is null or length(trim(p_phone)) > 32
    or nullif(trim(p_city), '') is null or length(trim(p_city)) > 120
    or length(coalesce(p_delivery, '')) > 500
    or length(coalesce(p_note, '')) > 3000 then
    raise exception 'Buyer name, phone and city are required';
  end if;

  select array_agg(distinct x.product_id), count(distinct x.product_id)
    into product_ids, item_count
  from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid);
  if coalesce(cardinality(product_ids), 0) = 0
    or exists (
      select 1 from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
      where x.quantity is null or x.quantity <= 0
    ) then
    raise exception 'Invalid order items';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
    group by x.product_id
    having count(*) > 1
  ) then
    raise exception 'Each product may appear only once in an order';
  end if;

  perform p.id
  from public.products p
  where p.id = any(product_ids)
  order by p.id
  for update;

  perform q.id
  from public.quote_requests q
  where q.id in (
    select x.quote_id
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
    where x.quote_id is not null
  )
  order by q.id
  for update;

  if (select count(*) from public.products p where p.id = any(product_ids)) <> item_count then
    raise exception 'One or more products are unavailable';
  end if;

  if exists (
    select 1
    from public.products p
    join (
      select x.product_id, sum(x.quantity)::integer as quantity
      from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
      group by x.product_id
    ) x on x.product_id = p.id
    where not p.is_active
      or not exists (
        select 1 from public.profiles seller
        where seller.id = p.seller_id and seller.role = 'seller' and seller.seller_status = 'approved'
      )
      or (p.selling_mode = 'wholesale' and x.quantity < p.min_wholesale_qty)
      or x.quantity > p.stock
  ) then
    raise exception 'A product is inactive or its stock/minimum quantity is invalid';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
    left join public.quote_requests q on q.id = x.quote_id
    left join public.products p on p.id = x.product_id
    where x.quote_id is not null
      and (
        q.id is null or q.buyer_id <> buyer or q.product_id <> x.product_id
        or q.seller_id <> p.seller_id
        or q.requested_quantity <> x.quantity or q.status <> 'responded'
        or q.proposed_unit_price is null
      )
  ) or exists (
    select 1 from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
    where x.quote_id is not null
    group by x.product_id
    having count(*) > 1
  ) then
    raise exception 'A quote is invalid, expired or does not match the order line';
  end if;

  for seller_row in
    select distinct p.seller_id
    from public.products p
    where p.id = any(product_ids)
    order by p.seller_id
  loop
    select coalesce(sum(
      case
        when x.quote_id is not null then q.proposed_unit_price
        when p.selling_mode = 'classic'
          or (p.selling_mode = 'both' and x.quantity < p.min_wholesale_qty) then p.price
        else coalesce(
          (select t.unit_price from public.product_price_tiers t
           where t.product_id = p.id and t.quantity_min <= x.quantity
           order by t.quantity_min desc limit 1),
          p.wholesale_price,
          p.price
        )
      end * x.quantity
    ), 0)::numeric(14,2)
      into total_value
    from public.products p
    join (
      select x.product_id, sum(x.quantity)::integer as quantity,
             (array_agg(x.quote_id) filter (where x.quote_id is not null))[1] as quote_id
      from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
      group by x.product_id
    ) x on x.product_id = p.id
    left join public.quote_requests q on q.id = x.quote_id
    where p.seller_id = seller_row.seller_id;

    insert into public.orders (buyer_id, buyer_name, phone, city, delivery, note, total)
    values (buyer, trim(p_buyer_name), trim(p_phone), trim(p_city), coalesce(p_delivery, ''), coalesce(p_note, ''), total_value)
    returning * into order_row;
    created_orders := created_orders || jsonb_build_array(
      jsonb_build_object('id', order_row.id, 'order_number', order_row.order_number)
    );

    insert into public.order_items (order_id, product_id, seller_id, product_name, unit_price, quantity, quote_id)
    select order_row.id, p.id, p.seller_id, p.name,
      case
        when x.quote_id is not null then q.proposed_unit_price
        when p.selling_mode = 'classic'
          or (p.selling_mode = 'both' and x.quantity < p.min_wholesale_qty) then p.price
        else coalesce(
          (select t.unit_price from public.product_price_tiers t
           where t.product_id = p.id and t.quantity_min <= x.quantity
           order by t.quantity_min desc limit 1),
          p.wholesale_price,
          p.price
        )
      end,
      x.quantity,
      x.quote_id
    from public.products p
    join (
      select x.product_id, sum(x.quantity)::integer as quantity,
             (array_agg(x.quote_id) filter (where x.quote_id is not null))[1] as quote_id
      from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
      group by x.product_id
    ) x on x.product_id = p.id
    left join public.quote_requests q on q.id = x.quote_id
    where p.seller_id = seller_row.seller_id
    ;

    update public.quote_requests q
    set status = 'accepted'
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
    where q.id = x.quote_id and q.buyer_id = buyer;

    insert into public.marketplace_notifications (user_id, title, message)
    values (
      seller_row.seller_id, 'Nouvelle demande de commande',
      'Une nouvelle demande de commande est disponible dans votre espace vendeur.'
    );

    update public.products p
      set stock = p.stock - x.quantity
    from (
      select x.product_id, sum(x.quantity)::integer as quantity
      from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer, quote_id uuid)
      group by x.product_id
    ) x
    where p.id = x.product_id and p.seller_id = seller_row.seller_id;
  end loop;

  update public.carts set status = 'converted'
  where buyer_id = buyer and status = 'active';

  return jsonb_build_object('orders', created_orders);
end;
$$;

create or replace function public.mg_update_order_status(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  order_row public.orders;
begin
  if p_status is null or p_status not in ('confirmed', 'shipped', 'delivered', 'cancelled') then
    raise exception 'Invalid order status';
  end if;
  select o.* into order_row from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if not public.is_marketplace_admin()
    and (not public.mg_is_approved_seller(auth.uid()) or not public.mg_is_order_seller(order_row.id)) then
    raise exception 'Seller or administrator access required' using errcode = '42501';
  end if;
  if not (
    (order_row.status = 'pending' and p_status in ('confirmed', 'cancelled'))
    or (order_row.status = 'confirmed' and p_status in ('shipped', 'cancelled'))
    or (order_row.status = 'shipped' and p_status = 'delivered')
  ) then
    raise exception 'Invalid order status transition';
  end if;

  update public.orders set status = p_status where id = p_order_id;
  if p_status = 'cancelled' then
    update public.products p set stock = p.stock + oi.quantity
    from public.order_items oi
    where oi.order_id = p_order_id and oi.product_id = p.id;
  end if;
end;
$$;

create or replace function public.mg_seller_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  product_stats record;
  order_stats record;
  pending_quote_count bigint;
begin
  if caller is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_marketplace_admin() and not public.mg_is_approved_seller(caller) then
    raise exception 'Approved seller access required' using errcode = '42501';
  end if;

  select count(*) filter (where p.is_active) as published_products,
         count(*) filter (where p.stock = 0) as out_of_stock_products
  into product_stats
  from public.products p
  where p.seller_id = caller;

  select count(distinct o.id) as received_orders,
         count(distinct o.id) filter (where o.status = 'pending') as pending_orders,
         count(distinct o.id) filter (where o.status = 'delivered') as completed_orders,
         coalesce(sum(oi.unit_price * oi.quantity)
           filter (where o.status in ('confirmed', 'shipped', 'delivered')), 0) as confirmed_revenue
  into order_stats
  from public.orders o
  join public.order_items oi on oi.order_id = o.id
  where oi.seller_id = caller;

  select count(*) into pending_quote_count
  from public.quote_requests q
  where q.seller_id = caller and q.status = 'pending';

  return jsonb_build_object(
    'published_products', coalesce(product_stats.published_products, 0),
    'out_of_stock_products', coalesce(product_stats.out_of_stock_products, 0),
    'received_orders', coalesce(order_stats.received_orders, 0),
    'pending_orders', coalesce(order_stats.pending_orders, 0),
    'completed_orders', coalesce(order_stats.completed_orders, 0),
    'confirmed_revenue', coalesce(order_stats.confirmed_revenue, 0),
    'pending_quotes', coalesce(pending_quote_count, 0)
  );
end;
$$;

create or replace function public.notify_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status then
    insert into public.marketplace_notifications (user_id, title, message)
    values (
      new.buyer_id, 'Mise à jour de votre commande',
      'Le statut de votre commande ' || new.order_number || ' est maintenant « ' || new.status || ' ».'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists auth_user_marketplace_profile on auth.users;
create trigger auth_user_marketplace_profile
  after insert on auth.users
  for each row execute function public.handle_new_marketplace_user();

do $$
declare
  v_table_name text;
begin
  foreach v_table_name in array array[
    'profiles', 'seller_applications', 'products', 'product_price_tiers', 'quote_requests', 'carts', 'cart_items',
    'buyer_favorites', 'shipping_addresses', 'orders', 'order_items',
    'marketplace_messages', 'marketplace_notifications', 'seller_delivery_zones',
    'product_media', 'marketplace_promotions'
  ] loop
    execute format('drop trigger if exists set_updated_at on public.%I', v_table_name);
    if exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = v_table_name and c.column_name = 'updated_at'
    ) then
      execute format(
        'create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',
        v_table_name
      );
    end if;
  end loop;
end;
$$;

drop trigger if exists products_sync_seller_details on public.products;
create trigger products_sync_seller_details
  before insert or update on public.products
  for each row execute function public.sync_product_seller_details();

drop trigger if exists profile_sync_marketplace_products on public.profiles;
create trigger profile_sync_marketplace_products
  after update of full_name, shop_name, phone, public_phone_consent, role, seller_status on public.profiles
  for each row execute function public.sync_marketplace_products_from_profile();

drop trigger if exists marketplace_message_notification on public.marketplace_messages;
create trigger marketplace_message_notification
  after insert on public.marketplace_messages
  for each row execute function public.notify_marketplace_message();

drop trigger if exists marketplace_order_status_notification on public.orders;
create trigger marketplace_order_status_notification
  after update of status on public.orders
  for each row execute function public.notify_order_status_change();

drop trigger if exists set_updated_at on public.quote_requests;
create trigger set_updated_at before update on public.quote_requests
  for each row execute function public.set_updated_at();

do $$
declare
  v_table_name text;
begin
  foreach v_table_name in array array[
    'categories', 'profiles', 'seller_applications', 'products', 'product_price_tiers', 'quote_requests', 'carts', 'cart_items',
    'buyer_favorites', 'shipping_addresses', 'orders', 'order_items',
    'marketplace_messages', 'marketplace_notifications', 'seller_delivery_zones',
    'product_media', 'marketplace_promotions'
  ] loop
    execute format('alter table public.%I enable row level security', v_table_name);
  end loop;
end;
$$;

drop policy if exists categories_public_read on public.categories;
create policy categories_public_read on public.categories for select to anon, authenticated using (active or public.is_marketplace_admin());
drop policy if exists categories_admin_manage on public.categories;
create policy categories_admin_manage on public.categories for all to authenticated
  using (public.is_marketplace_admin()) with check (public.is_marketplace_admin());

drop policy if exists profiles_read_self_or_admin on public.profiles;
create policy profiles_read_self_or_admin on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_marketplace_admin());
drop policy if exists profiles_update_self_or_admin on public.profiles;
create policy profiles_update_self_or_admin on public.profiles for update to authenticated
  using (id = (select auth.uid()) or public.is_marketplace_admin())
  with check (id = (select auth.uid()) or public.is_marketplace_admin());

drop policy if exists seller_applications_read_owner_admin on public.seller_applications;
create policy seller_applications_read_owner_admin on public.seller_applications for select to authenticated
  using (user_id = (select auth.uid()) or public.is_marketplace_admin());
drop policy if exists seller_applications_insert_owner on public.seller_applications;
create policy seller_applications_insert_owner on public.seller_applications for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');
drop policy if exists seller_applications_update_admin on public.seller_applications;
create policy seller_applications_update_admin on public.seller_applications for update to authenticated
  using (public.is_marketplace_admin()) with check (public.is_marketplace_admin());

drop policy if exists products_public_or_owner_read on public.products;
create policy products_public_or_owner_read on public.products for select to anon, authenticated
  using (
    (is_active and public.mg_is_approved_seller(seller_id))
    or seller_id = (select auth.uid())
    or public.is_marketplace_admin()
  );
drop policy if exists products_approved_seller_insert on public.products;
create policy products_approved_seller_insert on public.products for insert to authenticated
  with check (
    seller_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'seller' and p.seller_status = 'approved'
    )
  );
drop policy if exists products_owner_update on public.products;
create policy products_owner_update on public.products for update to authenticated
  using (seller_id = (select auth.uid()) or public.is_marketplace_admin())
  with check (
    (seller_id = (select auth.uid()) and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'seller' and p.seller_status = 'approved'
    )) or public.is_marketplace_admin()
  );
drop policy if exists products_owner_delete on public.products;
create policy products_owner_delete on public.products for delete to authenticated
  using (seller_id = (select auth.uid()) or public.is_marketplace_admin());

drop policy if exists product_price_tiers_public_read on public.product_price_tiers;
create policy product_price_tiers_public_read on public.product_price_tiers for select to anon, authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_id
      and (
        (p.is_active and public.mg_is_approved_seller(p.seller_id))
        or p.seller_id = (select auth.uid())
        or public.is_marketplace_admin()
      )
  ));

drop policy if exists carts_owner_manage on public.carts;
create policy carts_owner_manage on public.carts for all to authenticated
  using (buyer_id = (select auth.uid()) or public.is_marketplace_admin())
  with check (buyer_id = (select auth.uid()) or public.is_marketplace_admin());

drop policy if exists cart_items_owner_manage on public.cart_items;
create policy cart_items_owner_manage on public.cart_items for all to authenticated
  using (
    exists (select 1 from public.carts c where c.id = cart_id and c.buyer_id = (select auth.uid()))
    or public.is_marketplace_admin()
  )
  with check (
    exists (select 1 from public.carts c where c.id = cart_id and c.buyer_id = (select auth.uid()))
    or public.is_marketplace_admin()
  );

drop policy if exists buyer_favorites_owner_manage on public.buyer_favorites;
create policy buyer_favorites_owner_manage on public.buyer_favorites for all to authenticated
  using (buyer_id = (select auth.uid()) or public.is_marketplace_admin())
  with check (buyer_id = (select auth.uid()) or public.is_marketplace_admin());

drop policy if exists shipping_addresses_owner_manage on public.shipping_addresses;
create policy shipping_addresses_owner_manage on public.shipping_addresses for all to authenticated
  using (buyer_id = (select auth.uid()) or public.is_marketplace_admin())
  with check (buyer_id = (select auth.uid()) or public.is_marketplace_admin());

drop policy if exists orders_buyer_or_seller_read on public.orders;
create policy orders_buyer_or_seller_read on public.orders for select to authenticated
  using (
    buyer_id = (select auth.uid())
    or public.is_marketplace_admin()
    or public.mg_is_order_seller(orders.id)
  );

drop policy if exists order_items_buyer_seller_read on public.order_items;
create policy order_items_buyer_seller_read on public.order_items for select to authenticated
  using (
    seller_id = (select auth.uid())
    or public.is_marketplace_admin()
    or public.mg_is_order_buyer(order_id)
  );

alter table public.order_status_history enable row level security;
drop policy if exists order_status_history_participant_read on public.order_status_history;
create policy order_status_history_participant_read on public.order_status_history for select to authenticated
  using (
    public.mg_is_order_buyer(order_id)
    or public.mg_is_order_seller(order_id)
    or public.is_marketplace_admin()
  );

drop policy if exists quote_requests_participant_read on public.quote_requests;
create policy quote_requests_participant_read on public.quote_requests for select to authenticated
  using (
    buyer_id = (select auth.uid())
    or seller_id = (select auth.uid())
    or public.is_marketplace_admin()
  );

drop policy if exists marketplace_messages_participant_read on public.marketplace_messages;
create policy marketplace_messages_participant_read on public.marketplace_messages for select to authenticated
  using (sender_id = (select auth.uid()) or receiver_id = (select auth.uid()) or public.is_marketplace_admin());
drop policy if exists marketplace_messages_sender_insert on public.marketplace_messages;
create policy marketplace_messages_sender_insert on public.marketplace_messages for insert to authenticated
  with check (sender_id = (select auth.uid()));

drop policy if exists marketplace_notifications_owner_read on public.marketplace_notifications;
create policy marketplace_notifications_owner_read on public.marketplace_notifications for select to authenticated
  using (user_id = (select auth.uid()) or public.is_marketplace_admin());
drop policy if exists marketplace_notifications_owner_update on public.marketplace_notifications;
create policy marketplace_notifications_owner_update on public.marketplace_notifications for update to authenticated
  using (user_id = (select auth.uid()) or public.is_marketplace_admin())
  with check (user_id = (select auth.uid()) or public.is_marketplace_admin());

drop policy if exists seller_delivery_zones_public_read on public.seller_delivery_zones;
create policy seller_delivery_zones_public_read on public.seller_delivery_zones for select to anon, authenticated
  using (
    (active and public.mg_is_approved_seller(seller_id))
    or seller_id = (select auth.uid())
    or public.is_marketplace_admin()
  );
drop policy if exists seller_delivery_zones_owner_manage on public.seller_delivery_zones;
create policy seller_delivery_zones_owner_manage on public.seller_delivery_zones for all to authenticated
  using (
    seller_id = (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'seller' and p.seller_status = 'approved')
  )
  with check (
    seller_id = (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'seller' and p.seller_status = 'approved')
  );

drop policy if exists product_media_public_read on public.product_media;
create policy product_media_public_read on public.product_media for select to anon, authenticated
  using (
    exists (
      select 1 from public.products p
      where p.id = product_id and p.is_active and public.mg_is_approved_seller(p.seller_id)
    )
    or seller_id = (select auth.uid())
    or public.is_marketplace_admin()
  );
drop policy if exists product_media_owner_manage on public.product_media;
create policy product_media_owner_manage on public.product_media for all to authenticated
  using (
    (seller_id = (select auth.uid()) and public.mg_is_approved_seller(seller_id) and exists (
      select 1 from public.products p where p.id = product_id and p.seller_id = (select auth.uid())
    )) or public.is_marketplace_admin()
  )
  with check (
    (seller_id = (select auth.uid()) and public.mg_is_approved_seller(seller_id) and exists (
      select 1 from public.products p where p.id = product_id and p.seller_id = (select auth.uid())
    )) or public.is_marketplace_admin()
  );

drop policy if exists marketplace_promotions_public_read on public.marketplace_promotions;
create policy marketplace_promotions_public_read on public.marketplace_promotions for select to anon, authenticated
  using (
    (active and public.mg_is_approved_seller(seller_id))
    or seller_id = (select auth.uid())
    or public.is_marketplace_admin()
  );
drop policy if exists marketplace_promotions_owner_manage on public.marketplace_promotions;
create policy marketplace_promotions_owner_manage on public.marketplace_promotions for all to authenticated
  using (
    seller_id = (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'seller' and p.seller_status = 'approved')
  )
  with check (
    seller_id = (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'seller' and p.seller_status = 'approved')
  );

revoke all on public.categories, public.profiles, public.seller_applications, public.products,
  public.carts, public.cart_items, public.buyer_favorites, public.shipping_addresses,
  public.orders, public.order_items, public.marketplace_messages, public.marketplace_notifications,
  public.seller_delivery_zones, public.product_media, public.marketplace_promotions,
  public.product_price_tiers, public.quote_requests, public.order_status_history
  from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.profiles to authenticated;
grant select on public.seller_applications to authenticated;
grant update (full_name, shop_name, phone, city, business, about) on public.profiles to authenticated;
grant select on public.categories, public.products, public.seller_delivery_zones, public.product_media,
  public.marketplace_promotions, public.product_price_tiers to anon, authenticated;
grant insert, update, delete on public.categories to authenticated;
grant insert, delete on public.products to authenticated;
revoke update on public.products from authenticated;
revoke update (price, wholesale_price, min_wholesale_qty, selling_mode) on public.products from authenticated;
grant update (category_id, name, description, variants, stock, image_path, image_url, is_active)
  on public.products to authenticated;
grant select, insert, update, delete on public.carts, public.cart_items, public.buyer_favorites,
  public.shipping_addresses, public.marketplace_messages, public.marketplace_notifications,
  public.seller_delivery_zones, public.product_media, public.marketplace_promotions to authenticated;
revoke update on public.marketplace_notifications from authenticated;
grant update (is_read) on public.marketplace_notifications to authenticated;
grant select on public.orders, public.order_items to authenticated;
grant select on public.quote_requests to authenticated;
grant select on public.order_status_history to authenticated;

revoke all on function public.is_marketplace_admin() from public, anon;
revoke all on function public.mg_is_admin() from public, anon;
revoke all on function public.mg_is_order_seller(uuid) from public, anon;
revoke all on function public.mg_is_order_buyer(uuid) from public, anon;
revoke all on function public.mg_is_approved_seller(uuid) from public, anon;
revoke all on function public.mg_apply_as_seller(text, text, text, text, text) from public, anon;
revoke all on function public.mg_review_seller(uuid, text, text) from public, anon;
revoke all on function public.mg_set_public_phone_consent(boolean) from public, anon;
revoke all on function public.mg_place_order(text, text, text, text, text, jsonb) from public, anon;
revoke all on function public.mg_update_order_status(uuid, text) from public, anon;
revoke all on function public.mg_seller_dashboard_stats() from public, anon;
revoke all on function public.mg_save_product_price_tiers(uuid, jsonb) from public, anon;
revoke all on function public.mg_save_product_pricing(uuid, numeric, numeric, integer, text, jsonb) from public, anon;
revoke all on function public.mg_create_quote_request(uuid, integer, text) from public, anon;
revoke all on function public.mg_respond_to_quote(uuid, text, numeric, text) from public, anon;
revoke all on function public.mg_decline_quote(uuid) from public, anon;
grant execute on function public.is_marketplace_admin() to anon, authenticated;
grant execute on function public.mg_is_admin() to authenticated;
grant execute on function public.mg_is_order_seller(uuid) to authenticated;
grant execute on function public.mg_is_order_buyer(uuid) to authenticated;
grant execute on function public.mg_is_approved_seller(uuid) to anon, authenticated;
grant execute on function public.mg_apply_as_seller(text, text, text, text, text) to authenticated;
grant execute on function public.mg_review_seller(uuid, text, text) to authenticated;
grant execute on function public.mg_set_public_phone_consent(boolean) to authenticated;
grant execute on function public.mg_place_order(text, text, text, text, text, jsonb) to authenticated;
grant execute on function public.mg_update_order_status(uuid, text) to authenticated;
grant execute on function public.mg_seller_dashboard_stats() to authenticated;
grant execute on function public.mg_save_product_price_tiers(uuid, jsonb) to authenticated;
grant execute on function public.mg_save_product_pricing(uuid, numeric, numeric, integer, text, jsonb) to authenticated;
grant execute on function public.mg_create_quote_request(uuid, integer, text) to authenticated;
grant execute on function public.mg_respond_to_quote(uuid, text, numeric, text) to authenticated;
grant execute on function public.mg_decline_quote(uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/avif'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists product_images_public_read on storage.objects;
create policy product_images_public_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'product-images');
drop policy if exists product_images_seller_insert on storage.objects;
create policy product_images_seller_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'seller' and p.seller_status = 'approved'
    )
  );
drop policy if exists product_images_seller_update on storage.objects;
create policy product_images_seller_update on storage.objects for update to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.mg_is_approved_seller((select auth.uid()))
  )
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.mg_is_approved_seller((select auth.uid()))
  );
drop policy if exists product_images_seller_delete on storage.objects;
create policy product_images_seller_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'product-images'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or public.is_marketplace_admin())
  );
