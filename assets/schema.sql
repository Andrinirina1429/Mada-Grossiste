-- 1. Table des profils clients (Acheteurs)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    full_name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    city TEXT NOT NULL,
    subscription_status TEXT NOT NULL DEFAULT 'en_attente_5000ar',
    role TEXT NOT NULL DEFAULT 'buyer'
);

-- 2. Table des produits
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_id UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    variants TEXT NOT NULL DEFAULT '',
    price NUMERIC(14, 2) NOT NULL,
    wholesale_price NUMERIC(14, 2),
    min_wholesale_qty INT NOT NULL DEFAULT 1,
    selling_mode TEXT NOT NULL DEFAULT 'wholesale',
    stock INT NOT NULL DEFAULT 0,
    seller_name TEXT NOT NULL DEFAULT '',
    seller_phone TEXT NOT NULL DEFAULT '',
    image_url TEXT,
    image_path TEXT,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    moderation_status TEXT NOT NULL DEFAULT 'draft',
    moderation_note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Table des commandes
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    customer_name TEXT NOT NULL,
    customer_phone TEXT NOT NULL,
    destination_city TEXT NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    status TEXT NOT NULL DEFAULT 'en_attente_validation',
    notes TEXT
);

-- 4. Table des détails de commande (Articles du panier)
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_title TEXT NOT NULL,
    unit_price NUMERIC(12, 2) NOT NULL,
    quantity INT NOT NULL DEFAULT 1
);
