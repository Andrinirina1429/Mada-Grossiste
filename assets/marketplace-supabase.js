(function () {
  'use strict';

  const PRODUCT_COLUMNS = 'id,seller_id,category_id,name,description,variants,price,wholesale_price,min_wholesale_qty,selling_mode,stock,seller_name,seller_phone,image_url,image_path,is_active,moderation_status,moderation_note,created_at,categories(name)';
  const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[char]));
  const money = (value) => Math.round(Number(value) || 0).toLocaleString('fr-FR') + ' Ar';
  const userId = () => state.session?.id || null;
  let sellerProducts = [];
  const setBusy = (busy) => {
    const form = document.getElementById('product-form');
    if (!form) return;
    form.querySelectorAll('input,select,textarea,button').forEach((control) => { control.disabled = busy; });
  };
  let categories = [];

  function requireSupabase() {
    if (!mgSupabase) throw new Error('Supabase n’est pas connecté. Vérifiez la configuration du nouveau projet.');
    return mgSupabase;
  }

  function requireSeller() {
    if (!userId()) throw new Error('Connectez-vous pour continuer.');
    if (state.session.role !== 'seller' && state.session.role !== 'admin') {
      throw new Error('Votre compte vendeur doit être approuvé avant de gérer des produits.');
    }
  }

  function showCatalogError(element, error) {
    console.error('Chargement Supabase du catalogue impossible:', error);
    state.products = [];
    categories = [];
    CATS = [];
    element.innerHTML = `<section class="empty catalog-state catalog-error" role="alert"><i class="fa-solid fa-triangle-exclamation"></i><h3>Catalogue momentanément indisponible</h3><p>Les offres de MadaGrossiste sont en cours de mise à jour. Merci de réessayer dans quelques instants.</p><button class="btn btn-primary" onclick="loadSupabaseProducts()">Réessayer</button></section>`;
  }

  function showCatalogLoading(element) {
    element.innerHTML = `<section class="catalog-loading" aria-label="Chargement du catalogue" aria-busy="true">
      <div class="sectionhead"><div><h2>Catalogue des produits</h2><p>Chargement des offres depuis Supabase…</p></div></div>
      <div class="catalog-skeleton-grid">${Array.from({ length: 4 }, () => `<div class="catalog-skeleton" aria-hidden="true"><div class="catalog-skeleton-image"></div><div class="catalog-skeleton-line"></div><div class="catalog-skeleton-line short"></div><div class="catalog-skeleton-line"></div></div>`).join('')}</div>
    </section>`;
  }

  window.loadSupabaseProducts = async function () {
    const element = document.getElementById('app');
    if (state.view === 'catalog') showCatalogLoading(element);
    try {
      const client = requireSupabase();
      const [categoryResult, productResult] = await Promise.all([
        client.from('categories').select('id,name,slug').eq('active', true).order('name'),
        client.from('products').select(PRODUCT_COLUMNS).eq('is_active', true).order('created_at', { ascending: false })
      ]);
      if (categoryResult.error) throw categoryResult.error;
      if (productResult.error) throw productResult.error;
      const rows = productResult.data || [];
      const tierResult = rows.length
        ? await client.from('product_price_tiers').select('product_id,quantity_min,unit_price')
          .in('product_id', rows.map((row) => row.id)).order('quantity_min')
        : { data: [], error: null };
      if (tierResult.error) throw tierResult.error;
      const tiersByProduct = new Map();
      for (const tier of tierResult.data || []) {
        const tiers = tiersByProduct.get(tier.product_id) || [];
        tiers.push({ quantity: Number(tier.quantity_min), price: Number(tier.unit_price) });
        tiersByProduct.set(tier.product_id, tiers);
      }
      categories = categoryResult.data || [];
      CATS = categories.map((item) => item.name);
      state.products = rows.map((row) => ({
        id: row.id,
        owner: row.seller_id,
        seller_id: row.seller_id,
        category_id: row.category_id,
        name: row.name,
        description: row.description || '',
        variants: row.variants || '',
        price: Number(row.price),
        wholesalePrice: row.wholesale_price == null ? null : Number(row.wholesale_price),
        sellingMode: row.selling_mode || 'wholesale',
        wholesaleMin: Number(row.min_wholesale_qty),
        priceTiers: tiersByProduct.get(row.id) || [],
        stock: Number(row.stock),
        min: row.selling_mode === 'wholesale' ? Number(row.min_wholesale_qty) : 1,
        category: row.categories?.name || 'Autres',
        seller: row.seller_name,
        phone: row.seller_phone || '',
        image: row.image_url || '',
        image_path: row.image_path || '',
        createdAt: row.created_at,
        active: row.is_active,
        remote: true
      }));
      state.cart = Object.fromEntries(Object.entries(state.cart || {}).filter(([id]) =>
        state.products.some((product) => String(product.id) === String(id))
      ));
      if (state.view === 'catalog') renderCatalog(element);
      if (state.view === 'seller') renderSeller(element);
      if (state.view === 'cart') renderCart(element);
    } catch (error) {
      if (state.view === 'catalog') showCatalogError(element, error);
      else console.error('Actualisation Supabase des produits impossible:', error);
      throw error;
    }
  };

  window.renderCatalog = function (element) {
    const list = state.products.filter((product) =>
      (!search || searchFold(product.name).includes(searchFold(search))
        || searchFold(product.category).includes(searchFold(search))
        || searchFold(product.seller).includes(searchFold(search)))
      && (category === 'Toutes' || product.category === category)
    );
    if (sort === 'priceup') list.sort((a, b) => a.price - b.price);
    if (sort === 'pricedown') list.sort((a, b) => b.price - a.price);
    if (sort === 'name') list.sort((a, b) => a.name.localeCompare(b.name, 'fr'));
    const stores = [...new Set(state.products.map((product) => product.seller).filter(Boolean))].slice(0, 4);
    element.innerHTML = `<section class="sectionhead"><div><h2>Catalogue des produits</h2><p>Produits actifs publiés par les vendeurs MadaGrossiste.</p></div><button class="btn btn-light" onclick="loadSupabaseProducts()">Actualiser</button></section>
      <div class="toolbar"><label class="searchbox"><i class="fa-solid fa-magnifying-glass"></i><input id="catalog-search-input" placeholder="Produit, catégorie, vendeur…" value="${escapeHtml(search)}" oninput="setSearch(this.value)"></label>
      <select class="select" aria-label="Trier" onchange="sort=this.value;renderCatalog(document.getElementById('app'))"><option value="recent" ${sort === 'recent' ? 'selected' : ''}>Plus récents</option><option value="priceup" ${sort === 'priceup' ? 'selected' : ''}>Prix croissant</option><option value="pricedown" ${sort === 'pricedown' ? 'selected' : ''}>Prix décroissant</option><option value="name" ${sort === 'name' ? 'selected' : ''}>Nom A–Z</option></select></div>
      <div class="chips"><button class="chip ${category === 'Toutes' ? 'active' : ''}" onclick="category='Toutes';renderCatalog(document.getElementById('app'))">Toutes les catégories</button>${categories.map((item) => `<button class="chip ${category === item.name ? 'active' : ''}" onclick="category=${inlineJsArg(item.name)};renderCatalog(document.getElementById('app'))">${escapeHtml(item.name)}</button>`).join('')}</div>
      ${stores.length ? `<p class="muted">Vendeurs actifs : ${stores.map(escapeHtml).join(' · ')}</p>` : ''}
      ${list.length ? `<div class="grid">${list.map((product) => productCard(product)).join('')}</div>` : `<div class="empty catalog-state"><i class="fa-solid ${state.products.length ? 'fa-magnifying-glass' : 'fa-box-open'}"></i><h3>${state.products.length ? 'Aucun produit ne correspond' : 'Le catalogue se prépare'}</h3><p>${state.products.length ? 'Essayez d’autres mots-clés ou modifiez les filtres de recherche.' : 'Les premières offres seront affichées ici dès leur publication.'}</p>${state.products.length ? `<button class="btn btn-light" onclick="mgResetCatalogFilters()">Réinitialiser la recherche</button>` : `<button class="btn btn-primary" onclick="go('seller')">Devenir vendeur</button><a class="btn btn-light" href="https://wa.me/261325297833?text=Bonjour%20MadaGrossiste%2C%20je%20souhaite%20devenir%20vendeur." target="_blank" rel="noopener noreferrer">Nous contacter</a>`}</div>`}
      <section class="how-it-works"><div class="sectionhead"><div><h2>Comment ça marche ?</h2><p>Des étapes simples, avec les conditions de vente visibles avant la commande.</p></div></div><div class="how-steps">
        <article class="how-step"><span>1</span><h3>Trouvez vos produits</h3><p>Recherchez dans le catalogue et comparez les offres réelles des vendeurs.</p></article>
        <article class="how-step"><span>2</span><h3>Vérifiez les tarifs</h3><p>Consultez les prix par quantité, les minimums et la disponibilité affichée.</p></article>
        <article class="how-step"><span>3</span><h3>Envoyez votre commande</h3><p>Le stock et les prix sont revérifiés par PostgreSQL; aucun paiement en ligne n’est prélevé ici.</p></article>
      </div></section>
      <section class="seller-invitation"><div><span class="eyebrow">Vous êtes vendeur ?</span><h2>Présentez vos offres aux commerçants.</h2><p>Créez un compte, demandez l’accès vendeur puis publiez vos produits après validation.</p></div><button class="btn btn-primary" onclick="go('seller')">Découvrir l’espace vendeur <i class="fa-solid fa-arrow-right"></i></button></section>`;
  };

  window.mgResetCatalogFilters = function () {
    search = '';
    category = 'Toutes';
    sort = 'recent';
    const headerSearch = document.getElementById('global-search-input');
    if (headerSearch) headerSearch.value = '';
    window.renderCatalog(document.getElementById('app'));
  };

  const priceForQuantity = (product, quantity) => {
    const wholesale = product.sellingMode === 'wholesale'
      || (product.sellingMode === 'both' && quantity >= product.wholesaleMin);
    if (!wholesale) return Number(product.price);
    const tier = (product.priceTiers || [])
      .filter((item) => item.quantity <= quantity)
      .sort((a, b) => b.quantity - a.quantity)[0];
    return Number(tier?.price ?? product.wholesalePrice ?? product.price);
  };
  const pricingRows = (product) => {
    if (product.sellingMode === 'classic') {
      return [{ key: 'classic', label: 'Toutes quantités', price: Number(product.price) }];
    }

    const minimum = Math.max(1, Number(product.wholesaleMin) || 1);
    const tiers = [...(product.priceTiers || [])]
      .sort((a, b) => a.quantity - b.quantity);
    const rows = [];
    if (product.sellingMode === 'both' && minimum > 1) {
      rows.push({
        key: 'retail',
        label: `1–${minimum - 1} unité(s)`,
        price: Number(product.price)
      });
    }

    const atMinimum = tiers.filter((tier) => tier.quantity <= minimum).pop();
    const firstHigherTierIndex = tiers.findIndex((tier) => tier.quantity > minimum);
    const firstHigherTier = firstHigherTierIndex < 0 ? null : tiers[firstHigherTierIndex];
    const wholesaleRow = atMinimum
      ? { key: `tier-${atMinimum.quantity}`, price: Number(atMinimum.price) }
      : { key: 'wholesale', price: Number(product.wholesalePrice ?? product.price) };
    rows.push({
      ...wholesaleRow,
      label: firstHigherTier
        ? `${minimum}–${firstHigherTier.quantity - 1} unité(s)`
        : `Dès ${minimum} unité(s)`
    });

    for (let index = firstHigherTierIndex; index >= 0 && index < tiers.length; index += 1) {
      const tier = tiers[index];
      const nextTier = tiers[index + 1];
      rows.push({
        key: `tier-${tier.quantity}`,
        label: nextTier
          ? `${tier.quantity}–${nextTier.quantity - 1} unité(s)`
          : `Dès ${tier.quantity} unité(s)`,
        price: Number(tier.price)
      });
    }
    return rows;
  };
  const pricingRowForQuantity = (product, quantity) => {
    if (product.sellingMode === 'classic') return 'classic';
    if (product.sellingMode === 'both' && quantity < product.wholesaleMin) return 'retail';
    const tier = [...(product.priceTiers || [])]
      .filter((item) => item.quantity <= quantity)
      .sort((a, b) => b.quantity - a.quantity)[0];
    return tier ? `tier-${tier.quantity}` : 'wholesale';
  };
  const setFormBusy = (form, busy, loadingText) => {
    const button = form?.querySelector('button[type="submit"]');
    if (!button) return;
    if (busy) {
      button.dataset.idleHtml = button.innerHTML;
      button.disabled = true;
      button.textContent = loadingText;
    } else {
      button.disabled = false;
      if (button.dataset.idleHtml) {
        button.innerHTML = button.dataset.idleHtml;
        delete button.dataset.idleHtml;
      }
    }
  };
  const setButtonBusy = (button, busy, loadingText) => {
    if (!button) return;
    if (busy) {
      button.dataset.idleHtml = button.innerHTML;
      button.disabled = true;
      button.textContent = loadingText;
    } else {
      button.disabled = false;
      if (button.dataset.idleHtml) {
        button.innerHTML = button.dataset.idleHtml;
        delete button.dataset.idleHtml;
      }
    }
  };
  window.productCard = function (product) {
    const imageSource = safeImageSource(product.image || product.image_url);
    const image = imageSource
      ? `<img loading="lazy" decoding="async" src="${escapeHtml(imageSource)}" alt="${escapeHtml(product.name)}" onerror="this.style.display='none';this.nextElementSibling.style.display='grid'">`
      : '';
    const id = inlineJsArg(product.id);
    const min = Math.max(1, Number(product.min) || 1);
    const wholesaleMin = Math.max(1, Number(product.wholesaleMin) || 1);
    const stock = Math.max(0, Number(product.stock) || 0);
    const quantity = stock >= min
      ? Math.min(stock, Math.max(min, Number(state.cart?.[product.id]) || min))
      : min;
    const priceRows = pricingRows(product);
    const selectedPricingRow = pricingRowForQuantity(product, quantity);
    const phone = validPhone(product.phone) ? normPhone(product.phone) : '';
    const message = encodeURIComponent(`Bonjour, je vous contacte au sujet de « ${product.name} » sur MadaGrossiste.`);
    const whatsapp = phone
      ? `<a class="btn btn-whatsapp" href="https://wa.me/${phone}?text=${message}" target="_blank" rel="noopener noreferrer"><i class="fa-brands fa-whatsapp"></i> Contacter le vendeur</a>`
      : '';
    const mode = product.sellingMode === 'both' ? 'Classique et gros'
      : product.sellingMode === 'classic' ? 'Détail' : 'Gros';
    const quoteMin = product.sellingMode === 'classic' ? 1 : wholesaleMin;
    const unavailableReason = stock === 0
      ? 'Rupture de stock'
      : stock < min
        ? `Stock insuffisant pour le minimum de commande (${min} unité(s))`
        : '';
    return `<article class="product"><div class="product-image">${image}
      <div class="image-placeholder" style="${imageSource ? 'display:none' : ''}"><i class="fa-solid fa-box"></i></div>
      <span class="stock-pill">${stock > 0 ? `${stock} disponible(s)` : 'Rupture de stock'}</span>
      <button type="button" class="btn btn-light" style="position:absolute;z-index:2;margin:10px;padding:7px 10px"
        aria-label="Ajouter aux favoris" onclick="mgToggleFavorite(${id})"><i class="fa-regular fa-heart"></i></button>
    </div><div class="product-content">
      <span class="product-cat">${escapeHtml(product.category || 'Autre')}</span>
      <h3>${escapeHtml(product.name || 'Produit sans nom')}</h3>
      ${product.description ? `<p class="product-desc">${escapeHtml(product.description)}</p>` : ''}
      <div class="vendor"><i class="fa-solid fa-store mr-1"></i>${escapeHtml(product.seller || 'Vendeur indépendant')}</div>
      <div class="pricebox">
      <div class="pricelabel">Mode de vente : ${mode}</div>
      <div class="minimum">${product.sellingMode === 'classic'
        ? 'Minimum de commande : 1 unité'
        : product.sellingMode === 'both'
          ? `Détail dès 1 unité · Gros dès ${wholesaleMin} unité(s)`
          : `Minimum de commande en gros : ${wholesaleMin} unité(s)`}</div>
      </div>
      <div class="mg-pricing-wrap" style="overflow-x:auto;margin:12px 0">
        <table class="mg-pricing-table" style="width:100%;border-collapse:collapse;text-align:left">
          <thead><tr><th style="padding:7px;border-bottom:1px solid #e5e7eb">Quantité</th><th style="padding:7px;border-bottom:1px solid #e5e7eb">Prix / unité</th><th style="padding:7px;border-bottom:1px solid #e5e7eb">Tarif</th></tr></thead>
          <tbody>${priceRows.map((row) => `<tr data-price-row="${escapeHtml(row.key)}" class="${row.key === selectedPricingRow ? 'mg-tier-active' : ''}" style="${row.key === selectedPricingRow ? 'background:#f0fdf4;font-weight:700' : ''}">
            <td style="padding:7px;border-bottom:1px solid #f1f5f9">${escapeHtml(row.label)}</td>
            <td style="padding:7px;border-bottom:1px solid #f1f5f9">${money(row.price)}</td>
            <td style="padding:7px;border-bottom:1px solid #f1f5f9">${row.key === selectedPricingRow ? '<b>Applicable</b>' : ''}</td>
          </tr>`).join('')}</tbody>
        </table>
      </div>
      <label class="field">Quantité souhaitée
      <input id="mg-qty-${escapeHtml(product.id)}" type="number" min="${min}" max="${stock}" value="${quantity}" inputmode="numeric"
        oninput="mgPreviewProductPrice(${id},this.value)" aria-label="Quantité de ${escapeHtml(product.name)}">
      </label>
      <p class="muted" aria-live="polite">Prix unitaire sélectionné : <b id="mg-price-${escapeHtml(product.id)}">${money(priceForQuantity(product, quantity))}</b> ·
        Total indicatif : <b id="mg-total-${escapeHtml(product.id)}">${money(quantity * priceForQuantity(product, quantity))}</b></p>
      ${unavailableReason ? `<p class="notice" role="status">${escapeHtml(unavailableReason)}</p>` : '<p class="muted">Disponibilité finale et prix de commande vérifiés par PostgreSQL à la validation.</p>'}
      <button class="btn btn-primary" onclick="mgAddSelectedToCart(${id},document.getElementById('mg-qty-${escapeHtml(product.id)}').value)" ${stock < min ? 'disabled' : ''}>
      Ajouter au panier <i class="fa-solid fa-plus"></i>
      </button>
      <button class="btn btn-light" onclick="mgOpenQuoteForm(${id})" ${stock < quoteMin ? 'disabled' : ''}>Demander un devis</button>
      ${whatsapp}
      <button type="button" class="btn btn-light" onclick="mgStartMessage(${inlineJsArg(product.seller_id)},${id})"><i class="fa-regular fa-message"></i> Écrire au vendeur</button>
    </div></article>`;
  };

  window.mgPreviewProductPrice = function (productId, value) {
    const product = state.products.find((item) => String(item.id) === String(productId));
    const output = document.getElementById(`mg-price-${productId}`);
    const total = document.getElementById(`mg-total-${productId}`);
    const selectedQuantity = Number(value);
    if (!product || !output || !total) return;
    const validQuantity = Number.isInteger(selectedQuantity)
      && selectedQuantity >= product.min
      && selectedQuantity <= product.stock;
    if (!validQuantity) {
      output.textContent = 'Quantité invalide';
      total.textContent = '—';
      const card = document.getElementById(`mg-qty-${productId}`)?.closest('.product-content');
      card?.querySelectorAll('[data-price-row]').forEach((row) => {
        row.classList.remove('mg-tier-active');
        row.style.backgroundColor = '';
        row.style.fontWeight = '';
        const label = row.querySelector('td:last-child');
        if (label) label.textContent = '';
      });
      return;
    }
    const unitPrice = priceForQuantity(product, selectedQuantity);
    output.textContent = money(unitPrice);
    total.textContent = money(selectedQuantity * unitPrice);
    const activeRow = pricingRowForQuantity(product, selectedQuantity);
    const card = document.getElementById(`mg-qty-${productId}`)?.closest('.product-content');
    card?.querySelectorAll('[data-price-row]').forEach((row) => {
      const active = row.dataset.priceRow === activeRow;
      row.classList.toggle('mg-tier-active', active);
      row.style.backgroundColor = active ? '#f0fdf4' : '';
      row.style.fontWeight = active ? '700' : '';
      const label = row.querySelector('td:last-child');
      if (label) label.textContent = active ? 'Applicable' : '';
    });
  };
  window.mgAddSelectedToCart = async function (productId, value) {
    const product = state.products.find((item) => String(item.id) === String(productId));
    if (!product) return notify('Produit introuvable. Actualisez le catalogue.');
    const quantity = Number.parseInt(value, 10);
    if (!Number.isInteger(quantity) || quantity < product.min || quantity > product.stock) {
      return notify(`La quantité doit être comprise entre ${product.min} et ${product.stock}.`);
    }
    const previousQuantity = state.cart[productId];
    state.cart[productId] = quantity;
    save();
    if (state.session?.id && window.mgPersistCartItem) {
      const saved = await window.mgPersistCartItem(productId);
      if (!saved) {
        if (previousQuantity === undefined) delete state.cart[productId];
        else state.cart[productId] = previousQuantity;
        renderCatalog(document.getElementById('app'));
        return;
      }
    }
    go('cart');
    notify(state.session?.id ? 'Panier synchronisé avec Supabase.' : 'Produit ajouté au panier sur cet appareil.');
  };

  window.mgOpenQuoteForm = function (productId) {
    const product = state.products.find((item) => String(item.id) === String(productId));
    if (!product) return notify('Produit introuvable. Actualisez le catalogue.');
    if (!userId()) {
      notify('Connectez-vous pour demander un devis.');
      go('account');
      return;
    }
    document.getElementById('modaltitle').textContent = 'Demander un devis';
    const minQuote = product.sellingMode === 'classic' ? 1 : product.wholesaleMin;
    document.getElementById('modalbody').innerHTML = `<form class="formgrid" onsubmit="mgSubmitQuote(event,${inlineJsArg(product.id)})">
      <p class="field full">Demande pour <b>${escapeHtml(product.name)}</b>. Minimum : ${minQuote} unité(s) · Stock affiché : ${product.stock}. Le stock ne sera vérifié définitivement qu’à la commande.</p>
      <label class="field">Quantité demandée<input name="quantity" type="number" min="${minQuote}" max="${product.stock}" value="${Math.min(product.stock, Math.max(minQuote, Number(state.cart?.[product.id]) || minQuote))}" required></label>
      <label class="field full">Précisions<textarea name="note" rows="3" maxlength="2000" placeholder="Délais, variantes ou conditions souhaitées"></textarea></label>
      <button class="btn btn-primary" type="submit">Envoyer la demande de devis</button>
    </form>`;
    document.getElementById('modalback').classList.add('open');
  };

  window.mgDeclineQuote = async function (quoteId, button) {
    if (!confirm('Refuser cette offre de devis ?')) return;
    setButtonBusy(button, true, 'Refus en cours…');
    try {
      const { error } = await requireSupabase().rpc('mg_decline_quote', { p_quote_id: quoteId });
      if (error) throw error;
      notify('Offre de devis refusée.');
      await window.renderOrders(document.getElementById('app'));
    } catch (error) {
      console.error('Refus du devis impossible:', error);
      notify(error.message || 'Impossible de refuser cette offre.');
    } finally {
      setButtonBusy(button, false);
    }
  };

  window.mgSubmitQuote = async function (event, productId) {
    event.preventDefault();
    const form = event.currentTarget;
    const quantity = Number(form.elements.quantity.value);
    if (!Number.isInteger(quantity) || quantity < Number(form.elements.quantity.min)
      || quantity > Number(form.elements.quantity.max)) {
      return notify('La quantité demandée ne respecte pas le minimum ou le stock affiché.');
    }
    setFormBusy(form, true, 'Envoi en cours…');
    try {
      const { data, error } = await requireSupabase().rpc('mg_create_quote_request', {
        p_product_id: productId,
        p_quantity: quantity,
        p_note: form.elements.note.value.trim()
      });
      if (error) throw error;
      if (!data) throw new Error('Supabase n’a pas confirmé la création de la demande.');
      closeModal();
      go('orders');
      notify('Demande de devis enregistrée. Consultez son statut dans vos commandes.');
    } catch (error) {
      console.error('Demande de devis impossible:', error);
      notify(error.message || 'Impossible d’envoyer la demande de devis.');
    } finally {
      setFormBusy(form, false);
    }
  };

  window.mgRespondToQuote = async function (event, quoteId) {
    event.preventDefault();
    const form = event.currentTarget;
    setFormBusy(form, true, 'Envoi en cours…');
    try {
      const { error } = await requireSupabase().rpc('mg_respond_to_quote', {
        p_quote_id: quoteId,
        p_decision: 'responded',
        p_unit_price: Number(form.elements.unit_price.value),
        p_note: form.elements.note.value.trim()
      });
      if (error) throw error;
      notify('Votre proposition de tarif a été envoyée à l’acheteur.');
      try {
        await window.renderSeller(document.getElementById('app'));
      } catch (refreshError) {
        console.error('Proposition enregistrée, mais actualisation de la liste des devis impossible:', refreshError);
        notify('Proposition enregistrée. Actualisez l’espace vendeur pour voir son statut.');
      }
    } catch (error) {
      console.error('Réponse au devis impossible:', error);
      notify(error.message || 'Impossible de répondre à ce devis.');
    } finally {
      setFormBusy(form, false);
    }
  };

  window.mgRejectQuote = async function (quoteId, button) {
    if (!confirm('Refuser cette demande de devis ?')) return;
    setButtonBusy(button, true, 'Refus en cours…');
    try {
      const { error } = await requireSupabase().rpc('mg_respond_to_quote', {
        p_quote_id: quoteId, p_decision: 'rejected', p_unit_price: null, p_note: ''
      });
      if (error) throw error;
      notify('Demande de devis refusée.');
      try {
        await window.renderSeller(document.getElementById('app'));
      } catch (refreshError) {
        console.error('Demande refusée, mais actualisation de la liste des devis impossible:', refreshError);
        notify('Demande refusée dans PostgreSQL. Actualisez l’espace vendeur pour voir le statut.');
      }
    } catch (error) {
      console.error('Refus du devis impossible:', error);
      notify(error.message || 'Impossible de refuser ce devis.');
    } finally {
      setButtonBusy(button, false);
    }
  };

  window.mgOfferListedPrice = async function (quoteId, productId, quantity, button) {
    const product = [...state.products, ...sellerProducts].find((item) => String(item.id) === String(productId));
    if (!product) return notify('Produit introuvable; actualisez vos produits avant de répondre.');
    setButtonBusy(button, true, 'Envoi en cours…');
    try {
      const { error } = await requireSupabase().rpc('mg_respond_to_quote', {
        p_quote_id: quoteId,
        p_decision: 'responded',
        p_unit_price: priceForQuantity(product, Number(quantity)),
        p_note: 'Tarif actuel du catalogue.'
      });
      if (error) throw error;
      notify('Le tarif du catalogue a été proposé à l’acheteur.');
      try {
        await window.renderSeller(document.getElementById('app'));
      } catch (refreshError) {
        console.error('Tarif proposé, mais actualisation de la liste des devis impossible:', refreshError);
        notify('Proposition enregistrée. Actualisez l’espace vendeur pour voir son statut.');
      }
    } catch (error) {
      console.error('Réponse au devis au tarif catalogue impossible:', error);
      notify(error.message || 'Impossible de répondre à ce devis.');
    } finally {
      setButtonBusy(button, false);
    }
  };

  window.mgOpenQuoteAcceptance = function (quoteId, productId, quantity, productName, unitPrice) {
    document.getElementById('modaltitle').textContent = 'Confirmer le devis';
    document.getElementById('modalbody').innerHTML = `<form class="formgrid" onsubmit="mgAcceptQuote(event,${inlineJsArg(quoteId)},${inlineJsArg(productId)},${Number(quantity)})">
      <p class="field full">${Number(quantity)} unité(s) de <b>${escapeHtml(productName)}</b>.</p>
      <p class="field full">Proposition du vendeur : <b>${money(unitPrice)} / unité</b> · Total proposé : <b>${money(Number(quantity) * Number(unitPrice))}</b>.</p>
      <p class="field full muted">Le prix proposé vient de Supabase. Le stock est revérifié par PostgreSQL lors de la création de la commande et n’est pas réservé par le devis.</p>
      <label class="field">Nom du commerçant / boutique<input name="buyer_name" required maxlength="160" value="${escapeHtml(state.session?.shop || state.session?.name || '')}"></label>
      <label class="field">Téléphone<input name="phone" type="tel" required maxlength="32" value="${escapeHtml(state.session?.phone || '')}"></label>
      <label class="field">Ville / région<input name="city" required maxlength="120" value="${escapeHtml(state.session?.city || '')}"></label>
      <label class="field full">Livraison<textarea name="delivery" rows="2" maxlength="500"></textarea></label>
      <label class="field full">Note<textarea name="note" rows="2" maxlength="3000"></textarea></label>
      <button class="btn btn-primary" type="submit">Commander au tarif proposé</button>
    </form>`;
    document.getElementById('modalback').classList.add('open');
  };

  window.mgAcceptQuote = async function (event, quoteId, productId, quantity) {
    event.preventDefault();
    const form = event.currentTarget;
    const phone = form.elements.phone.value.trim();
    if (!validPhone(phone)) return notify('Numéro invalide. Exemple : 034 12 345 67');
    setFormBusy(form, true, 'Validation en cours…');
    try {
      const { data, error } = await requireSupabase().rpc('mg_place_order', {
        p_buyer_name: form.elements.buyer_name.value.trim(),
        p_phone: phone,
        p_city: form.elements.city.value.trim(),
        p_delivery: form.elements.delivery.value.trim(),
        p_note: form.elements.note.value.trim(),
        p_items: [{ product_id: productId, quantity, quote_id: quoteId }]
      });
      if (error) throw error;
      if (!Array.isArray(data?.orders) || data.orders.length === 0) {
        throw new Error('Supabase n’a pas confirmé la création de la commande.');
      }
      closeModal();
      go('orders');
      notify(`Commande créée au tarif convenu (${data.orders.length} vendeur(s)).`);
      try {
        await window.loadSupabaseProducts();
      } catch (refreshError) {
        console.error('Commande enregistrée, mais actualisation du stock impossible:', refreshError);
        notify('Commande enregistrée dans Supabase. Le stock affiché sera actualisé lors du prochain chargement.');
      }
    } catch (error) {
      console.error('Acceptation du devis impossible:', error);
      notify(error.message || 'Impossible de commander au tarif proposé.');
    } finally {
      setFormBusy(form, false);
    }
  };

  const cartProductRows = () => Object.entries(state.cart || {})
    .map(([id, quantity]) => ({ product: state.products.find((item) => String(item.id) === String(id)), quantity: Number(quantity) }))
    .filter((item) => item.product && item.quantity > 0);
  const cartLineIssue = ({ product, quantity }) => {
    if (!Number.isInteger(quantity) || quantity < product.min) {
      return `La quantité minimale est de ${product.min} unité(s).`;
    }
    if (quantity > product.stock) return `Stock insuffisant : ${product.stock} unité(s) disponible(s).`;
    return '';
  };
  const hasInvalidCartLine = (items) => items.some((item) => cartLineIssue(item));
  const cartTotal = () => cartProductRows()
    .reduce((sum, item) => sum + priceForQuantity(item.product, item.quantity) * item.quantity, 0);

  window.renderCart = function (element) {
    const items = cartProductRows();
    if (!items.length) {
      element.innerHTML = `<div class="empty"><i class="fa-solid fa-bag-shopping"></i><h3>Votre panier est vide</h3><p>Ajoutez des produits au panier ou demandez un devis au vendeur.</p><button class="btn btn-primary" onclick="go('catalog')">Découvrir le catalogue</button></div>`;
      return;
    }
    element.innerHTML = `<div class="sectionhead"><div><h2>Mon panier</h2><p>Les tarifs et totaux sont recalculés selon les quantités.</p></div></div>
      <div class="panel">${items.map(({ product, quantity }) => {
        const unitPrice = priceForQuantity(product, quantity);
        const issue = cartLineIssue({ product, quantity });
        return `<article class="rowcard"><div style="flex:1;min-width:0"><b>${escapeHtml(product.name)}</b>
          <p>${quantity} × ${money(unitPrice)} / unité = <b>${money(quantity * unitPrice)}</b></p>
          <p class="muted">${product.sellingMode === 'classic' ? 'Détail' : product.sellingMode === 'both' ? `Détail dès 1 · Gros dès ${product.wholesaleMin}` : `Gros · Minimum ${product.wholesaleMin}`} unité(s) · Stock affiché : ${product.stock}</p>
          ${issue ? `<p class="notice" role="alert">${escapeHtml(issue)} Ajustez la quantité avant de commander.</p>` : ''}
          </div><div class="flex gap-2"><button class="btn btn-light" onclick="quantity(${inlineJsArg(product.id)},-1)" aria-label="Diminuer" ${quantity <= product.min ? 'disabled' : ''}>−</button>
          <span class="btn btn-light" aria-label="Quantité">${quantity}</span><button class="btn btn-light" onclick="quantity(${inlineJsArg(product.id)},1)" aria-label="Augmenter" ${quantity >= product.stock ? 'disabled' : ''}>+</button>
          <button class="btn btn-danger" onclick="removeCart(${inlineJsArg(product.id)})">Retirer</button></div></article>`;
      }).join('')}
      <div class="divider"></div><div class="flex justify-between font-extrabold"><span>Total estimé</span><span>${money(cartTotal())}</span></div>
      <p class="muted mt-2">Estimation basée sur les tarifs chargés depuis Supabase. Le prix définitif et le stock sont revérifiés dans PostgreSQL à la commande.</p>
      ${hasInvalidCartLine(items) ? '<p class="notice mt-3" role="alert">Corrigez les quantités non conformes avant de continuer.</p>' : ''}
      <button class="btn btn-primary mt-4" onclick="go('checkout')" ${hasInvalidCartLine(items) ? 'disabled' : ''}>Continuer vers la commande</button></div>`;
  };

  window.renderCheckout = function (element) {
    const items = cartProductRows();
    if (!items.length) {
      go('cart');
      return;
    }
    if (hasInvalidCartLine(items)) {
      element.innerHTML = `<div class="empty"><i class="fa-solid fa-triangle-exclamation"></i><h3>Quantités à vérifier</h3><p>Une quantité ne respecte plus le minimum ou le stock affiché. Corrigez le panier avant de commander.</p><button class="btn btn-primary" onclick="go('cart')">Vérifier le panier</button></div>`;
      return;
    }
    element.innerHTML = `<div class="sectionhead"><div><h2>Informations de commande</h2><p>Vérifiez les tarifs selon les quantités choisies.</p></div></div>
      <form class="panel" onsubmit="submitOrder(event)"><div class="formgrid">
        <label class="field">Nom du commerçant / boutique<input id="buyerName" required value="${escapeHtml(state.session?.shop || state.session?.name || '')}"></label>
        <label class="field">Téléphone<input id="buyerPhone" type="tel" required value="${escapeHtml(state.session?.phone || '')}" placeholder="034 XX XXX XX"></label>
        <label class="field">Ville / région<input id="buyerCity" required value="${escapeHtml(state.session?.city || '')}"></label>
        <label class="field">Mode de livraison<select id="delivery"><option>Livraison par voiture — frais à confirmer</option></select><small class="muted">Les frais exacts seront confirmés avec le vendeur.</small></label>
        <label class="field full">Précisions<textarea id="buyerNote" rows="3" maxlength="3000"></textarea></label>
      </div><div class="divider"></div>
      ${items.map(({ product, quantity }) => {
        const unitPrice = priceForQuantity(product, quantity);
        return `<div class="flex justify-between"><span>${escapeHtml(product.name)} · ${quantity} × ${money(unitPrice)} / unité</span><b>${money(unitPrice * quantity)}</b></div>`;
      }).join('')}
      <div class="divider"></div><div class="flex justify-between font-extrabold mb-4"><span>Total estimé</span><span>${money(cartTotal())}</span></div>
      <button class="btn btn-primary" type="submit">Envoyer la commande <i class="fa-solid fa-paper-plane"></i></button>
      <p class="muted mt-3">Le total définitif est recalculé par Supabase à partir des prix vendeur. Aucun paiement n’est prélevé ici.</p></form>`;
  };

  window.openProduct = function (productId = null) {
    try { requireSeller(); } catch (error) { notify(error.message); return; }
    if (!categories.length) {
      notify('Aucune catégorie active n’est disponible dans Supabase.');
      return;
    }
    const product = productId
      ? [...state.products, ...sellerProducts].find((item) => String(item.id) === String(productId))
      : null;
    if (product && product.seller_id !== userId() && state.session.role !== 'admin') {
      notify('Vous ne pouvez modifier que vos propres produits.');
      return;
    }
    document.getElementById('modaltitle').textContent = product ? 'Modifier le produit' : 'Ajouter un produit';
    document.getElementById('modalbody').innerHTML = `<form id="product-form" onsubmit="saveProduct(event,${inlineJsArg(product?.id || '')})" class="formgrid">
      <label class="field full">Nom du produit<input id="pname" required maxlength="120" value="${escapeHtml(product?.name || '')}"></label>
      <label class="field full">Description<textarea id="pdescription" rows="3" maxlength="3000">${escapeHtml(product?.description || '')}</textarea></label>
      <label class="field">Catégorie<select id="pcat" required>${categories.map((item) => `<option value="${item.id}" ${item.id === product?.category_id ? 'selected' : ''}>${escapeHtml(item.name)}</option>`).join('')}</select></label>
      <label class="field">Mode de vente<select id="pmode" required onchange="mgProductModeChanged()">
        <option value="classic" ${product?.sellingMode === 'classic' ? 'selected' : ''}>Classique</option>
        <option value="wholesale" ${!product || product.sellingMode === 'wholesale' ? 'selected' : ''}>Gros</option>
        <option value="both" ${product?.sellingMode === 'both' ? 'selected' : ''}>Classique et gros</option>
      </select></label>
      <label class="field">Prix classique / unité (Ar)<input id="pprice" type="number" min="1" step="1" required value="${product?.price || ''}"></label>
      <label class="field">Prix de gros de base / unité (Ar)<input id="pwholesale" type="number" min="1" step="1" value="${product?.wholesalePrice ?? ''}"><small class="muted">Facultatif si des paliers définissent les tarifs.</small></label>
      <label class="field">Minimum de gros<input id="pmin" type="number" min="1" required value="${product?.wholesaleMin || product?.min || 2}"></label>
      <label class="field full">Paliers de prix de gros<input id="ptiers" maxlength="1000" value="${escapeHtml((product?.priceTiers || []).map((tier) => `${tier.quantity}:${tier.price}`).join(', '))}" placeholder="Ex. 10:9000, 25:8000"><small class="muted">Format quantité minimale : prix unitaire (Ar), séparés par des virgules. Maximum 20 paliers; chaque quantité doit atteindre le minimum de gros.</small></label>
      <label class="field">Stock disponible<input id="pstock" type="number" min="0" required value="${product?.stock ?? 0}"></label>
      <label class="field full">Tailles / variantes<input id="pvariants" maxlength="500" value="${escapeHtml(product?.variants || '')}"></label>
      <label class="field full">Photo du produit<input id="pimagefile" type="file" accept="image/jpeg,image/png,image/webp,image/avif"><small class="muted">JPG, PNG, WebP ou AVIF — 5 Mo maximum. Les images sont stockées dans Supabase Storage.</small></label>
      ${product?.image ? `<div class="field full"><img src="${escapeHtml(product.image)}" alt="Photo actuelle" style="max-width:180px;border-radius:10px"></div>` : ''}
      <div class="field full"><button class="btn btn-primary w-full" type="submit">${product ? 'Enregistrer les modifications' : 'Enregistrer comme brouillon'}</button></div></form>`;
    document.getElementById('modalback').classList.add('open');
    window.mgProductModeChanged();
  };

  window.mgProductModeChanged = function () {
    const classic = document.getElementById('pmode')?.value === 'classic';
    const minimum = document.getElementById('pmin');
    const tiers = document.getElementById('ptiers');
    if (!minimum || !tiers) return;
    if (classic) {
      minimum.value = '1';
      minimum.disabled = true;
      tiers.value = '';
      tiers.disabled = true;
    } else {
      if (minimum.disabled || Number(minimum.value) < 1) minimum.value = '2';
      minimum.disabled = false;
      tiers.disabled = false;
    }
  };

  window.saveProduct = async function (event, productId = '') {
    event.preventDefault();
    try {
      requireSeller();
      const client = requireSupabase();
      const name = document.getElementById('pname').value.trim();
      const categoryId = document.getElementById('pcat').value;
      const price = Number(document.getElementById('pprice').value);
      const wholesaleInput = document.getElementById('pwholesale').value.trim();
      const wholesalePrice = wholesaleInput ? Number(wholesaleInput) : null;
      const sellingMode = document.getElementById('pmode').value;
      const minInput = Number(document.getElementById('pmin').value);
      const min = sellingMode === 'classic' ? 1 : minInput;
      const stock = Number(document.getElementById('pstock').value);
      const tiersText = document.getElementById('ptiers').value.trim();
      const tiers = tiersText ? tiersText.split(',').map((part) => {
        const match = part.trim().match(/^([1-9]\d*)\s*:\s*([1-9]\d*)$/);
        if (!match) throw new Error('Utilisez le format quantité:prix pour chaque palier.');
        return { quantity_min: Number(match[1]), unit_price: Number(match[2]) };
      }) : [];
      const file = document.getElementById('pimagefile').files[0];
      if (!name || !categoryId || !['classic', 'wholesale', 'both'].includes(sellingMode)
        || !Number.isInteger(min) || min < 1 || !Number.isInteger(stock) || stock < 0
        || !Number.isSafeInteger(price) || price <= 0
        || (wholesalePrice !== null && (!Number.isSafeInteger(wholesalePrice) || wholesalePrice <= 0))) {
        throw new Error('Vérifiez le nom, la catégorie, le prix, le minimum et le stock.');
      }
      if (sellingMode === 'classic' && tiers.length) throw new Error('Les paliers ne sont disponibles qu’en mode gros.');
      if (tiers.length > 20 || tiers.some((tier) => tier.quantity_min < min)
        || new Set(tiers.map((tier) => tier.quantity_min)).size !== tiers.length) {
        throw new Error('Les paliers doivent être uniques, commencer au minimum de gros et ne pas dépasser 20 lignes.');
      }
      let previousTierPrice = wholesalePrice ?? price;
      for (const tier of [...tiers].sort((a, b) => a.quantity_min - b.quantity_min)) {
        if (tier.unit_price >= previousTierPrice) {
          throw new Error('Chaque palier de quantité supérieure doit proposer un prix unitaire inférieur.');
        }
        previousTierPrice = tier.unit_price;
      }
      if (file && (!['image/jpeg', 'image/png', 'image/webp', 'image/avif'].includes(file.type) || file.size > 5 * 1024 * 1024)) {
        throw new Error('Choisissez une image JPG, PNG, WebP ou AVIF de 5 Mo maximum.');
      }
      const current = productId
        ? [...state.products, ...sellerProducts].find((item) => String(item.id) === String(productId))
        : null;
      if (current && current.seller_id !== userId() && state.session.role !== 'admin') {
        throw new Error('Vous ne pouvez modifier que vos propres produits.');
      }
      const id = current?.id || crypto.randomUUID();
      let imagePath = current?.image_path || null;
      let imageUrl = current?.image || null;
      let uploadedPath = null;
      let mediaWarning = '';
      setBusy(true);
      if (file) {
        const extension = file.name.split('.').pop().toLowerCase().replace(/[^a-z0-9]/g, '') || 'image';
        uploadedPath = `${userId()}/${id}/${crypto.randomUUID()}.${extension}`;
        const { error: uploadError } = await client.storage.from('product-images').upload(uploadedPath, file, {
          contentType: file.type, upsert: false
        });
        if (uploadError) throw uploadError;
        imagePath = uploadedPath;
        imageUrl = client.storage.from('product-images').getPublicUrl(uploadedPath).data.publicUrl;
      }
      const record = {
        category_id: categoryId,
        name,
        description: document.getElementById('pdescription').value.trim(),
        variants: document.getElementById('pvariants').value.trim(),
        stock,
        image_path: imagePath,
        image_url: imageUrl
      };
      const query = current
        ? client.from('products').update(record).eq('id', id).select('id').single()
        : client.from('products').insert({
          id, ...record, seller_id: userId(), price,
          wholesale_price: sellingMode === 'classic' ? null : wholesalePrice,
          min_wholesale_qty: min,
          selling_mode: sellingMode,
          is_active: false
        }).select('id').single();
      const { error: saveError } = await query;
      if (saveError) {
        if (uploadedPath) {
          const { error: cleanupError } = await client.storage.from('product-images').remove([uploadedPath]);
          if (cleanupError) console.error('Image temporaire non supprimée après échec de la fiche:', cleanupError);
        }
        throw saveError;
      }
      const { error: pricingError } = await client.rpc('mg_save_product_pricing', {
        p_product_id: id,
        p_price: price,
        p_wholesale_price: sellingMode === 'classic' ? null : wholesalePrice,
        p_min_wholesale_qty: min,
        p_selling_mode: sellingMode,
        p_tiers: tiers
      });
      if (pricingError) {
        if (!current) {
          const { error: productCleanupError } = await client.from('products')
            .delete().eq('id', id).eq('seller_id', userId());
          if (productCleanupError) {
            console.error('Brouillon incomplet non supprimé après échec des tarifs:', productCleanupError);
          } else if (uploadedPath) {
            const { error: imageCleanupError } = await client.storage.from('product-images').remove([uploadedPath]);
            if (imageCleanupError) console.error('Image temporaire non supprimée après échec des tarifs:', imageCleanupError);
          }
        }
        throw pricingError;
      }
      if (file) {
        const { error: mediaDeleteError } = await client.from('product_media').delete().eq('product_id', id);
        if (mediaDeleteError) {
          console.error('Anciennes références média à nettoyer:', mediaDeleteError);
          mediaWarning = 'La fiche est enregistrée, mais les anciennes références média n’ont pas été nettoyées.';
        }
        const { error: mediaInsertError } = await client.from('product_media').insert({
          product_id: id, seller_id: userId(), media_url: imageUrl, storage_path: imagePath,
          media_type: 'image', position: 0
        });
        if (mediaInsertError) {
          console.error('Référence média non enregistrée:', mediaInsertError);
          mediaWarning = 'La fiche est enregistrée, mais la référence de la photo n’a pas été ajoutée à la galerie.';
        }
        if (current?.image_path && current.image_path !== uploadedPath) {
          const { error: oldImageError } = await client.storage.from('product-images').remove([current.image_path]);
          if (oldImageError) {
            console.error('Ancienne image non supprimée:', oldImageError);
            mediaWarning = 'La fiche est enregistrée, mais l’ancienne photo reste à supprimer dans Storage.';
          }
        }
      }
      closeModal();
      await window.loadSupabaseProducts();
      const { data: moderationResult, error: moderationError } = await client.from('products')
        .select('moderation_status').eq('id', id).single();
      if (moderationError) throw moderationError;
      const reviewMessage = moderationResult.moderation_status === 'pending'
        ? 'Produit enregistré et transmis à la modération avant publication.'
        : '';
      notify(mediaWarning || reviewMessage || (current ? 'Produit mis à jour dans Supabase.' : 'Brouillon enregistré dans Supabase.'));
    } catch (error) {
      console.error('Enregistrement du produit impossible:', error);
      notify(error.message || 'Impossible d’enregistrer ce produit.');
    } finally {
      setBusy(false);
    }
  };

  window.publishProduct = async function (productId) {
    return window.mgSetProductActive(productId, true);
  };

  window.mgSetProductActive = async function (productId, active, button) {
    const product = [...state.products, ...sellerProducts].find((item) => String(item.id) === String(productId));
    if (!product || (product.seller_id !== userId() && state.session?.role !== 'admin')) {
      notify('Vous ne pouvez modifier que vos propres produits.');
      return;
    }
    if (!active && !confirm('Désactiver cette offre ? Elle ne sera plus visible dans le catalogue.')) return;
    setButtonBusy(button, true, active ? 'Publication…' : 'Désactivation…');
    try {
      requireSeller();
      if (active && product.moderationStatus !== 'approved') {
        const { error: reviewError } = await requireSupabase().rpc('mg_submit_product_for_review', {
          p_product_id: productId
        });
        if (reviewError) throw reviewError;
        notify('Demande de modération envoyée. Le produit sera visible après approbation.');
        await window.renderSeller(document.getElementById('app'));
        return;
      }
      const { data, error } = await requireSupabase().from('products')
        .update({ is_active: active }).eq('id', productId).eq('seller_id', product.seller_id)
        .select('id,is_active').maybeSingle();
      if (error) throw error;
      if (!data || data.is_active !== active) throw new Error('Supabase n’a pas confirmé le changement de visibilité.');
      notify(active ? 'Produit publié dans le catalogue.' : 'Produit désactivé.');
      try {
        await window.renderSeller(document.getElementById('app'));
      } catch (refreshError) {
        console.error('Produit mis à jour, mais actualisation de la liste impossible:', refreshError);
        notify('Produit enregistré. Actualisez l’espace vendeur pour voir son nouvel état.');
      }
    } catch (error) {
      console.error('Mise à jour de la visibilité du produit impossible:', error);
      notify(error.message || 'Impossible de modifier la visibilité du produit.');
    } finally {
      setButtonBusy(button, false);
    }
  };

  window.deleteProduct = async function (productId) {
    const product = [...state.products, ...sellerProducts].find((item) => String(item.id) === String(productId));
    if (!product || (product.seller_id !== userId() && state.session?.role !== 'admin')) {
      notify('Vous ne pouvez supprimer que vos propres produits.');
      return;
    }
    if (!confirm('Supprimer ce produit de Supabase ?')) return;
    try {
      let cleanupWarning = false;
      const { error } = await requireSupabase().from('products').delete().eq('id', productId);
      if (error) throw error;
      if (product.image_path) {
        const { error: imageError } = await mgSupabase.storage.from('product-images').remove([product.image_path]);
        if (imageError) {
          console.error('Image de produit à nettoyer dans Storage:', imageError);
          notify('Produit supprimé, mais sa photo doit encore être nettoyée dans Storage.');
          cleanupWarning = true;
        }
      }
      await window.loadSupabaseProducts();
      if (!cleanupWarning) notify('Produit supprimé.');
    } catch (error) {
      console.error('Suppression du produit impossible:', error);
      notify(error.message || 'Impossible de supprimer ce produit.');
    }
  };

  window.renderSeller = async function (element) {
    if (!state.session) {
      element.innerHTML = `<div class="empty"><i class="fa-solid fa-store"></i><h3>Votre boutique commence ici</h3><p>Connectez-vous puis créez une demande vendeur pour présenter vos offres.</p><button class="btn btn-primary" onclick="regRole='seller';regTab='register';go('account')">Créer mon compte vendeur</button></div>`;
      return;
    }
    if (state.session.seller_status === 'pending') {
      element.innerHTML = `<div class="empty"><i class="fa-solid fa-hourglass-half"></i><h3>Demande en cours de vérification</h3><p>Votre demande vendeur doit être approuvée avant la gestion de produits.</p><button class="btn btn-light" onclick="go('account')">Retour à mon espace</button></div>`;
      return;
    }
    if (state.session.role !== 'seller' && state.session.role !== 'admin') {
      element.innerHTML = `<div class="panel"><h2 class="panel-title">Demander l’accès vendeur</h2><p class="muted mb-3">Votre boutique sera vérifiée par l’équipe avant toute publication.</p>${state.session.seller_rejection_reason ? `<p class="notice mb-3">${escapeHtml(state.session.seller_rejection_reason)}</p>` : ''}<form class="formgrid" onsubmit="submitSellerApplication(event)"><label class="field full">Nom de la boutique<input id="sellerShop" required minlength="2" maxlength="120" value="${escapeHtml(state.session.shop || '')}"></label><label class="field">Téléphone professionnel<input id="sellerPhone" type="tel" required value="${escapeHtml(state.session.phone || '')}"></label><label class="field">Ville / région<input id="sellerCity" required maxlength="120" value="${escapeHtml(state.session.city || '')}"></label><label class="field full">Activité principale<input id="sellerBusiness" maxlength="160" value="${escapeHtml(state.session.business || '')}"></label><label class="field full">Présentation de la boutique<textarea id="sellerAbout" rows="3" maxlength="3000">${escapeHtml(state.session.about || '')}</textarea></label><button class="btn btn-primary" type="submit">Envoyer la demande</button></form></div>`;
      return;
    }
    try {
      element.innerHTML = `<div class="panel" role="status">Chargement des produits, commandes et devis depuis PostgreSQL…</div>`;
      const client = requireSupabase();
      const [
        { data: products, error: productsError },
        { data: orders, error: ordersError },
        { data: quotes, error: quotesError },
        { data: dashboardStats, error: dashboardStatsError }
      ] = await Promise.all([
        client.from('products').select(PRODUCT_COLUMNS).eq('seller_id', userId()).order('created_at', { ascending: false }),
        client.from('orders').select('id,order_number,status,buyer_name,phone,city,delivery,note,total,created_at,order_items(id,product_name,unit_price,quantity,seller_id)')
          .order('created_at', { ascending: false }),
        client.from('quote_requests').select('id,buyer_id,product_id,requested_quantity,buyer_note,status,proposed_unit_price,seller_note,created_at,products(name)')
          .eq('seller_id', userId()).order('created_at', { ascending: false }),
        client.rpc('mg_seller_dashboard_stats')
      ]);
      if (productsError) throw productsError;
      if (ordersError) throw ordersError;
      if (quotesError) throw quotesError;
      if (dashboardStatsError) throw dashboardStatsError;
      const metricKeys = [
        'published_products', 'out_of_stock_products', 'received_orders',
        'pending_orders', 'completed_orders', 'confirmed_revenue', 'pending_quotes'
      ];
      if (!dashboardStats || metricKeys.some((key) => !Number.isFinite(Number(dashboardStats[key])))) {
        throw new Error('Les indicateurs vendeur n’ont pas été confirmés par PostgreSQL.');
      }
      const rows = products || [];
      const tierResult = rows.length
        ? await client.from('product_price_tiers').select('product_id,quantity_min,unit_price')
          .in('product_id', rows.map((row) => row.id)).order('quantity_min')
        : { data: [], error: null };
      if (tierResult.error) throw tierResult.error;
      const tiersByProduct = new Map();
      for (const tier of tierResult.data || []) {
        const tiers = tiersByProduct.get(tier.product_id) || [];
        tiers.push({ quantity: Number(tier.quantity_min), price: Number(tier.unit_price) });
        tiersByProduct.set(tier.product_id, tiers);
      }
      sellerProducts = rows.map((row) => ({
        id: row.id, seller_id: row.seller_id, category_id: row.category_id,
        name: row.name, description: row.description || '', variants: row.variants || '',
        price: Number(row.price), wholesalePrice: row.wholesale_price == null ? null : Number(row.wholesale_price),
        sellingMode: row.selling_mode || 'wholesale', wholesaleMin: Number(row.min_wholesale_qty),
        priceTiers: tiersByProduct.get(row.id) || [], stock: Number(row.stock),
        min: row.selling_mode === 'wholesale' ? Number(row.min_wholesale_qty) : 1,
        category: row.categories?.name || 'Autres',
        seller: row.seller_name, phone: row.seller_phone || '', image: row.image_url || '',
        image_path: row.image_path || '', active: row.is_active,
        moderationStatus: row.moderation_status || 'draft',
        moderationNote: row.moderation_note || '', remote: true
      }));
      const orderRows = (orders || []).filter((order) => order.order_items?.some((item) => item.seller_id === userId()));
      const historyResult = orderRows.length
        ? await client.from('order_status_history')
          .select('id,order_id,actor_id,previous_status,new_status,created_at')
          .in('order_id', orderRows.map((order) => order.id))
          .order('created_at', { ascending: true })
        : { data: [], error: null };
      if (historyResult.error) throw historyResult.error;
      const historyByOrder = new Map();
      for (const entry of historyResult.data || []) {
        const history = historyByOrder.get(entry.order_id) || [];
        history.push(entry);
        historyByOrder.set(entry.order_id, history);
      }

      const attentionProducts = rows.filter((item) => !item.is_active || Number(item.stock) === 0
        || item.moderation_status !== 'approved');
      element.innerHTML = `<div class="sectionhead"><div><h2>Espace vendeur</h2><p>Indicateurs et opérations chargés depuis PostgreSQL pour votre compte.</p></div><div class="flex gap-2 flex-wrap"><button class="btn btn-light" onclick="renderSeller(document.getElementById('app'))">Actualiser</button><button class="btn btn-primary" onclick="openProduct()">Ajouter un produit</button></div></div>
        <div class="metricgrid">
          <div class="metric"><small>Produits publiés</small><b>${Number(dashboardStats.published_products)}</b></div>
          <div class="metric"><small>En rupture</small><b>${Number(dashboardStats.out_of_stock_products)}</b></div>
          <div class="metric"><small>Commandes reçues</small><b>${Number(dashboardStats.received_orders)}</b></div>
          <div class="metric"><small>Commandes en attente</small><b>${Number(dashboardStats.pending_orders)}</b></div>
          <div class="metric"><small>Commandes terminées</small><b>${Number(dashboardStats.completed_orders)}</b></div>
          <div class="metric"><small>CA confirmé*</small><b>${money(dashboardStats.confirmed_revenue)}</b></div>
          <div class="metric"><small>Devis à traiter</small><b>${Number(dashboardStats.pending_quotes)}</b></div>
        </div>
        <p class="muted mb-4">* Somme des lignes de commandes confirmées, expédiées ou terminées; commandes annulées exclues.</p>
        <div class="panel"><h3 class="panel-title">Produits nécessitant une intervention</h3>${attentionProducts.length ? attentionProducts.map((item) => `<div class="rowcard"><div style="flex:1;min-width:0"><b>${escapeHtml(item.name)}</b><p class="muted">${item.moderation_status === 'pending' ? 'En attente de modération' : item.moderation_status === 'rejected' ? `Modifications demandées${item.moderation_note ? ` : ${escapeHtml(item.moderation_note)}` : ''}` : item.moderation_status === 'draft' ? 'Brouillon non soumis à modération' : item.stock === 0 ? 'Rupture de stock' : 'Offre désactivée'} · ${item.is_active ? 'Publié' : 'Non publié'}</p></div><button class="btn btn-light" onclick="openProduct('${item.id}')">Modifier</button>${!item.is_active ? `<button class="btn btn-primary" onclick="mgSetProductActive('${item.id}',true,this)">${item.moderation_status === 'approved' ? 'Republier' : 'Soumettre à modération'}</button>` : ''}</div>`).join('') : '<p class="muted">Aucun produit à traiter.</p>'}</div>
        <div class="panel mt-4"><h3 class="panel-title">Mes produits</h3>${rows.length ? rows.map((item) => `<div class="rowcard"><div style="flex:1;min-width:0"><b>${escapeHtml(item.name)}</b><p>${escapeHtml(item.categories?.name || '')} · Stock : ${item.stock} · Détail : ${money(item.price)}${item.wholesale_price == null ? '' : ` · Gros : ${money(item.wholesale_price)}`}</p><p class="muted">${item.selling_mode === 'both' ? 'Classique et gros' : item.selling_mode === 'classic' ? 'Classique' : 'Gros'} · Minimum gros : ${item.min_wholesale_qty} · ${item.moderation_status === 'pending' ? 'En modération' : item.moderation_status === 'rejected' ? 'Modifications demandées' : item.moderation_status === 'draft' ? 'Brouillon non soumis' : item.is_active ? 'Publié' : 'Désactivé'}${(tiersByProduct.get(item.id) || []).length ? ` · ${(tiersByProduct.get(item.id) || []).length} palier(s)` : ''}</p></div><div class="flex gap-2 flex-wrap"><button class="btn btn-light" onclick="openProduct('${item.id}')">Modifier</button><button class="btn ${item.is_active ? 'btn-light' : 'btn-primary'}" onclick="mgSetProductActive('${item.id}',${!item.is_active},this)">${item.is_active ? 'Désactiver' : item.moderation_status === 'approved' ? 'Republier' : 'Soumettre à modération'}</button><button class="btn btn-danger" onclick="deleteProduct('${item.id}')">Supprimer</button></div></div>`).join('') : '<p class="muted">Aucun produit. Ajoutez votre première offre.</p>'}</div>
        <div class="panel mt-4"><h3 class="panel-title">Demandes de devis reçues</h3>${quotes?.length ? quotes.map((quote) => `<article class="rowcard" style="flex-direction:column;align-items:stretch"><div class="flex justify-between"><b>${escapeHtml(quote.products?.name || 'Produit')}</b><span>${quote.requested_quantity} unité(s) · ${quote.status === 'pending' ? 'À traiter' : quote.status === 'responded' ? 'Proposition envoyée' : quote.status === 'accepted' ? 'Accepté et commandé' : quote.status === 'rejected' ? 'Refusé' : 'Annulé'}</span></div><p class="muted">${escapeHtml(quote.buyer_note || 'Aucune précision')} · ${new Date(quote.created_at).toLocaleString('fr-FR')}</p>${quote.proposed_unit_price != null ? `<p>Tarif proposé : ${money(quote.proposed_unit_price)} / unité · Total ${money(Number(quote.proposed_unit_price) * Number(quote.requested_quantity))}${quote.seller_note ? ` · ${escapeHtml(quote.seller_note)}` : ''}</p>` : ''}${quote.status === 'pending' ? `<div class="flex gap-2 flex-wrap"><button class="btn btn-light" type="button" onclick="mgOfferListedPrice('${quote.id}','${quote.product_id}',${quote.requested_quantity},this)">Proposer le tarif catalogue</button><button class="btn btn-danger" type="button" onclick="mgRejectQuote('${quote.id}',this)">Refuser</button></div><form class="formgrid" onsubmit="mgRespondToQuote(event,'${quote.id}')"><label class="field">Prix proposé (Ar / unité)<input name="unit_price" type="number" min="1" step="1" required></label><label class="field full">Conditions ou note<textarea name="note" rows="2" maxlength="2000" placeholder="Validité, livraison ou variantes"></textarea></label><button class="btn btn-primary" type="submit">Envoyer la proposition</button></form>` : ''}</article>`).join('') : '<p class="muted">Aucune demande de devis pour le moment.</p>'}</div>
        <div class="panel mt-4"><h3 class="panel-title">Commandes reçues</h3>${orderRows.length ? orderRows.map((order) => {
          const ownItems = order.order_items.filter((item) => item.seller_id === userId());
          const transitions = NEXT_ORDER_STATUSES[order.status] || [];
          const history = historyByOrder.get(order.id) || [];
          return `<article class="rowcard" style="flex-direction:column;align-items:stretch">
            <div class="flex justify-between flex-wrap gap-2"><b>${escapeHtml(order.order_number)}</b><span>${ORDER_STATUS_LABELS[order.status] || escapeHtml(order.status)}</span></div>
            <div class="flex justify-between"><span>${ownItems.reduce((sum, item) => sum + Number(item.quantity), 0)} unité(s) · Total de vos lignes</span><b>${money(ownItems.reduce((sum, item) => sum + Number(item.unit_price) * Number(item.quantity), 0))}</b></div>
            ${transitions.length ? `<div class="flex gap-2 flex-wrap" aria-label="Actions de statut">${transitions.map((next) => `<button class="btn ${next === 'cancelled' ? 'btn-danger' : 'btn-light'}" onclick="setStatus('${order.id}','${next}',this)">${next === 'confirmed' ? 'Confirmer' : next === 'shipped' ? 'Marquer expédiée' : next === 'delivered' ? 'Marquer terminée' : 'Annuler'}</button>`).join('')}</div>` : ''}
            <details><summary class="btn btn-light" style="cursor:pointer">Détails, livraison et historique</summary>
              <p class="mt-2"><b>Acheteur :</b> ${escapeHtml(order.buyer_name)} · ${escapeHtml(order.phone)}</p><p><b>Ville :</b> ${escapeHtml(order.city)}</p><p><b>Livraison :</b> ${escapeHtml(order.delivery || 'À convenir')}</p><p><b>Note :</b> ${escapeHtml(order.note || 'Aucune')}</p>
              <div class="divider"></div>${ownItems.map((item) => `<div class="flex justify-between"><span>${escapeHtml(item.product_name)} × ${item.quantity} · ${money(item.unit_price)} / unité</span><b>${money(Number(item.unit_price) * Number(item.quantity))}</b></div>`).join('')}
              <h4 class="font-bold mt-3">Historique du statut</h4>${history.length ? `<ol class="muted">${history.map((entry) => `<li>${entry.previous_status ? `${ORDER_STATUS_LABELS[entry.previous_status] || escapeHtml(entry.previous_status)} → ` : 'Créée : '}${ORDER_STATUS_LABELS[entry.new_status] || escapeHtml(entry.new_status)} · ${new Date(entry.created_at).toLocaleString('fr-FR')}</li>`).join('')}</ol>` : '<p class="muted">Aucun historique disponible.</p>'}
              <p class="muted mt-2">Les prix historiques sont en lecture seule. Les changements de statut passent par le RPC sécurisé.</p>
            </details>
          </article>`;
        }).join('') : '<p class="muted">Aucune commande reçue.</p>'}</div>`;
    } catch (error) {
      console.error('Chargement de l’espace vendeur impossible:', error);
      element.innerHTML = `<div class="empty"><h3>Espace vendeur indisponible</h3><p>${escapeHtml(error.message || 'Vérifiez les autorisations Supabase.')}</p><button class="btn btn-light" onclick="renderSeller(document.getElementById('app'))">Réessayer</button></div>`;
    }
  };

  window.submitSellerApplication = async function (event) {
    event.preventDefault();
    const shop = document.getElementById('sellerShop').value.trim();
    const phone = document.getElementById('sellerPhone').value.trim();
    if (!validPhone(phone)) return notify('Numéro invalide. Exemple : 034 12 345 67');
    const normalizedPhone = '+' + normPhone(phone);
    const city = document.getElementById('sellerCity').value.trim();
    const business = document.getElementById('sellerBusiness').value.trim();
    const about = document.getElementById('sellerAbout').value.trim();
    try {
      const { error } = await requireSupabase().rpc('mg_apply_as_seller', {
        p_shop_name: shop,
        p_business: business,
        p_phone: normalizedPhone,
        p_city: city,
        p_about: about
      });
      if (error) throw error;
      state.session = {
        ...state.session, shop, phone: normalizedPhone, city, business, about,
        requested_role: 'seller', seller_status: 'pending', seller_rejection_reason: ''
      };
      await window.renderSeller(document.getElementById('app'));
      notify('Demande vendeur envoyée pour validation.');
    } catch (error) {
      console.error('Demande vendeur impossible:', error);
      notify(error.message || 'Impossible d’envoyer la demande vendeur.');
    }
  };

  window.submitOrder = async function (event) {
    event.preventDefault();
    if (!userId()) return notify('Connectez-vous pour envoyer une commande.');
    const cartRows = cartProductRows();
    const invalidLine = cartRows.find((item) => cartLineIssue(item));
    if (invalidLine) {
      notify(`${invalidLine.product.name} : ${cartLineIssue(invalidLine)}`);
      go('cart');
      return;
    }
    const items = cartRows.map(({ product, quantity }) => ({
      product_id: product.id,
      quantity
    }));
    if (!items.length) return go('cart');
    const phone = document.getElementById('buyerPhone').value.trim();
    if (!validPhone(phone)) return notify('Numéro invalide. Exemple : 034 12 345 67');
    const form = event.currentTarget;
    setFormBusy(form, true, 'Enregistrement en cours…');
    try {
      const { data, error } = await requireSupabase().rpc('mg_place_order', {
        p_buyer_name: document.getElementById('buyerName').value.trim(),
        p_phone: phone,
        p_city: document.getElementById('buyerCity').value.trim(),
        p_delivery: document.getElementById('delivery').value,
        p_note: document.getElementById('buyerNote').value.trim(),
        p_items: items
      });
      if (error) throw error;
      if (!Array.isArray(data?.orders) || data.orders.length === 0) {
        throw new Error('Supabase n’a pas confirmé la création de la commande.');
      }
      state.cart = {};
      window.mgResetRemoteCart?.();
      go('orders');
      notify(`Commande enregistrée dans Supabase (${data.orders.length} vendeur(s)).`);
      try {
        await window.loadSupabaseProducts();
      } catch (refreshError) {
        console.error('Commande enregistrée, mais actualisation du stock impossible:', refreshError);
        notify('Commande enregistrée dans Supabase. Le stock affiché sera actualisé lors du prochain chargement.');
      }
    } catch (error) {
      console.error('Création de commande impossible:', error);
      notify(error.message || 'Impossible de transmettre la commande.');
    } finally {
      setFormBusy(form, false);
    }
  };

  window.renderOrders = async function (element) {
    if (!userId()) {
      element.innerHTML = `<div class="empty"><h3>Connectez-vous pour consulter vos commandes</h3><button class="btn btn-primary" onclick="go('account')">Connexion</button></div>`;
      return;
    }
    element.innerHTML = `<div class="panel" role="status">Chargement de vos commandes et demandes de devis…</div>`;
    try {
      const client = requireSupabase();
      const [
        { data, error },
        { data: quotes, error: quoteError }
      ] = await Promise.all([
        client.from('orders')
        .select('id,order_number,status,buyer_name,phone,city,delivery,note,total,created_at,order_items(product_name,unit_price,quantity,seller_id)')
        .eq('buyer_id', userId()).order('created_at', { ascending: false }),
        client.from('quote_requests')
          .select('id,product_id,seller_id,requested_quantity,buyer_note,status,proposed_unit_price,seller_note,created_at,products(name,stock,selling_mode,min_wholesale_qty)')
          .eq('buyer_id', userId()).order('created_at', { ascending: false })
      ]);
      if (error) throw error;
      if (quoteError) throw quoteError;
      const orders = data || [];
      const quoteRows = quotes || [];
      element.innerHTML = `<div class="sectionhead"><div><h2>Mes commandes et devis</h2><p>Commandes et réponses des vendeurs enregistrées dans Supabase.</p></div><button class="btn btn-light" onclick="renderOrders(document.getElementById('app'))">Actualiser</button></div>
        <div class="panel mb-4"><h3 class="panel-title">Mes demandes de devis</h3>${quoteRows.length ? quoteRows.map((quote) => `<article class="rowcard" style="flex-direction:column;align-items:stretch">
          <div class="flex justify-between"><b>${escapeHtml(quote.products?.name || 'Produit')}</b><span>${quote.requested_quantity} unité(s) · ${quote.status === 'responded' ? 'Réponse reçue' : quote.status === 'accepted' ? 'Commande créée' : quote.status === 'rejected' ? 'Refusé' : quote.status === 'cancelled' ? 'Annulé' : 'En attente'}</span></div>
          <p class="muted">Votre demande : ${escapeHtml(quote.buyer_note || 'sans précision')}</p>
          ${quote.proposed_unit_price != null ? `<p>Proposition du vendeur : <b>${money(quote.proposed_unit_price)} / unité</b> · Total pour ${quote.requested_quantity} unité(s) : <b>${money(Number(quote.proposed_unit_price) * Number(quote.requested_quantity))}</b></p>` : ''}
          ${quote.seller_note ? `<p>${escapeHtml(quote.seller_note)}</p>` : ''}
          ${quote.products?.stock != null ? `<p class="muted">Stock actuellement affiché : ${quote.products.stock} unité(s). Le devis ne réserve pas le stock; disponibilité revérifiée à la commande.</p>` : '<p class="muted">Stock à actualiser avant de commander ce devis.</p>'}
          ${quote.status === 'responded' ? `<div class="flex gap-2 flex-wrap"><button class="btn btn-primary" onclick="mgOpenQuoteAcceptance('${quote.id}','${quote.product_id}',${quote.requested_quantity},${inlineJsArg(quote.products?.name || 'Produit')},${Number(quote.proposed_unit_price)})" ${quote.products?.stock == null || Number(quote.products.stock) < Number(quote.requested_quantity) ? 'disabled' : ''}>Accepter et commander au tarif proposé</button><button class="btn btn-light" onclick="mgDeclineQuote('${quote.id}',this)">Refuser l’offre</button></div>` : ''}
        </article>`).join('') : '<p class="muted">Aucune demande de devis pour le moment.</p>'}</div>
        <h3 class="panel-title">Commandes</h3>${orders.length ? orders.map((order) => `<article class="panel mb-3"><div class="flex justify-between"><b>${escapeHtml(order.order_number)}</b><span>${escapeHtml(order.status)}</span></div><p class="muted">${new Date(order.created_at).toLocaleString('fr-FR')} · ${escapeHtml(order.city)}</p>${order.order_items.map((item) => `<div class="flex justify-between"><span>${escapeHtml(item.product_name)} × ${item.quantity}</span><b>${money(item.unit_price * item.quantity)}</b></div>`).join('')}<div class="divider"></div><b>Total : ${money(order.total)}</b></article>`).join('') : `<div class="empty"><i class="fa-solid fa-clipboard-list"></i><h3>Aucune commande</h3><p>Les commandes validées apparaîtront ici.</p><button class="btn btn-primary" onclick="go('catalog')">Découvrir le catalogue</button></div>`}`;
    } catch (error) {
      console.error('Chargement des commandes impossible:', error);
      element.innerHTML = `<div class="empty"><h3>Commandes indisponibles</h3><p>${escapeHtml(error.message || 'Vérifiez les permissions Supabase.')}</p></div>`;
    }
  };

  window.setStatus = async function (orderId, status, button) {
    setButtonBusy(button, true, 'Mise à jour…');
    try {
      const { error } = await requireSupabase().rpc('mg_update_order_status', {
        p_order_id: orderId, p_status: status
      });
      if (error) throw error;
      notify('Statut de commande enregistré dans PostgreSQL.');
      try {
        await window.renderSeller(document.getElementById('app'));
      } catch (refreshError) {
        console.error('Statut enregistré, mais actualisation des commandes impossible:', refreshError);
        notify('Statut enregistré dans PostgreSQL. Actualisez l’espace vendeur pour voir la mise à jour.');
      }
    } catch (error) {
      console.error('Mise à jour du statut impossible:', error);
      notify(error.message || 'Impossible de mettre à jour la commande.');
      try {
        await window.renderSeller(document.getElementById('app'));
      } catch (refreshError) {
        console.error('Actualisation des commandes après erreur impossible:', refreshError);
      }
    } finally {
      setButtonBusy(button, false);
    }
  };

  const ORDER_STATUS_LABELS = {
    pending: 'En attente',
    confirmed: 'Confirmée',
    shipped: 'Expédiée',
    delivered: 'Terminée',
    cancelled: 'Annulée'
  };
  const NEXT_ORDER_STATUSES = {
    pending: ['confirmed', 'cancelled'],
    confirmed: ['shipped', 'cancelled'],
    shipped: ['delivered'],
    delivered: [],
    cancelled: []
  };

  const renderSeller = window.renderSeller;
  window.renderSeller = async function (element) {
    await renderSeller(element);
    const session = state.session;
    if (!session || (session.role !== 'seller'
      && !(session.requested_role === 'seller' && session.seller_status === 'pending'))) return;

    try {
      const { data, error } = await requireSupabase().from('profiles')
        .select('public_phone_consent').eq('id', session.id).single();
      if (error) throw error;

      const panel = document.createElement('section');
      panel.className = 'panel';
      panel.style.marginBottom = '16px';
      const label = document.createElement('label');
      label.className = 'checkline field';
      label.style.cssText = 'flex-direction:row;font-weight:500;align-items:flex-start';
      const checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      checkbox.checked = Boolean(data.public_phone_consent);
      checkbox.style.cssText = 'width:20px;height:20px;flex:none;padding:0;margin-top:2px';
      const description = document.createElement('span');
      description.textContent = 'J’autorise l’affichage public de mon téléphone professionnel pour que les acheteurs puissent me contacter sur WhatsApp. Ce choix est facultatif et modifiable.';
      label.append(checkbox, description);
      panel.append(label);
      element.prepend(panel);

      checkbox.addEventListener('change', async () => {
        const enabled = checkbox.checked;
        checkbox.disabled = true;
        try {
          const { error: consentError } = await requireSupabase().rpc('mg_set_public_phone_consent', {
            p_enabled: enabled
          });
          if (consentError) throw consentError;
          notify(enabled
            ? 'Votre téléphone sera affiché avec vos produits publics.'
            : 'Votre téléphone ne sera plus affiché avec vos produits.');
        } catch (error) {
          console.error('Mise à jour du consentement téléphone impossible:', error);
          checkbox.checked = !enabled;
          notify(error.message || 'Impossible de modifier ce choix.');
        } finally {
          checkbox.disabled = false;
        }
      });
    } catch (error) {
      console.error('Chargement du consentement téléphone impossible:', error);
      notify(error.message || 'Impossible de charger votre choix de confidentialité.');
    }
  };

  const renderFeatures = window.mgRenderFeatures;
  window.mgRenderFeatures = async function (element) {
    await renderFeatures(element);
    const notice = [...(element?.querySelectorAll('.panel p.muted') || [])]
      .find((paragraph) => paragraph.textContent.startsWith('Cette version enregistre des liens de médias.'));
    if (notice?.textContent.startsWith('Cette version enregistre des liens de médias.')) {
      notice.textContent = 'Les photos principales peuvent être téléversées dans Storage. Les médias secondaires sont enregistrés comme liens URL et ne sont pas téléversés dans Storage.';
    }
  };

  const showLegal = window.showLegal;
  window.showLegal = function (kind) {
    if (kind !== 'privacy') return showLegal(kind);
    document.getElementById('modaltitle').textContent = 'Politique de confidentialité — projet';
    document.getElementById('modalbody').innerHTML = `
      <p class="muted">Version de travail à valider avant toute ouverture publique.</p>
      <h4 class="font-bold mt-3">1. Données traitées</h4>
      <p class="muted">MadaGrossiste traite les informations de compte et de profil, les coordonnées professionnelles, les produits publiés, les paniers, les favoris, les demandes de commande, les adresses, les messages et les notifications nécessaires au fonctionnement du service.</p>
      <h4 class="font-bold mt-3">2. Visibilité des coordonnées</h4>
      <p class="muted">Le téléphone professionnel d’un vendeur n’est pas affiché par défaut. Il n’apparaît sur ses offres que si le vendeur autorise explicitement cet affichage; il peut retirer son accord depuis son espace vendeur.</p>
      <h4 class="font-bold mt-3">3. Hébergement et prestataires</h4>
      <p class="muted">Les données marketplace sont hébergées dans Supabase. L’application et ses fonctions serveur sont hébergées par Netlify. Les questions envoyées à l’assistant sont transmises au fournisseur IA configuré côté serveur (OpenAI ou Google Gemini). N’envoyez pas de mot de passe, de coordonnées bancaires ni de code secret de paiement dans les messages.</p>
      <h4 class="font-bold mt-3">4. Sécurité, conservation et droits</h4>
      <p class="muted">Les accès aux données sont limités par les règles de sécurité de la base. Les durées de conservation, sauvegardes, procédures d’accès, de rectification et de suppression, ainsi que le responsable du traitement et ses coordonnées doivent encore être précisés avant l’ouverture publique.</p>
      <h4 class="font-bold mt-3">5. Contact</h4>
      <p class="muted">Contact provisoire : WhatsApp 032 52 97 833. Ce document est un brouillon et doit être vérifié avant le lancement public.</p>`;
    document.getElementById('modalback').classList.add('open');
  };

})();
